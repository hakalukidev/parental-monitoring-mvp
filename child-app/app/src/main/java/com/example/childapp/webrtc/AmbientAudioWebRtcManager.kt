package com.example.childapp.webrtc

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import androidx.core.content.ContextCompat
import org.json.JSONObject
import org.webrtc.*
import org.webrtc.audio.AudioDeviceModule
import org.webrtc.audio.JavaAudioDeviceModule
import android.media.MediaRecorder
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Owns the WebRTC PeerConnection + microphone audio track for a
 * dedicated surrounding sound / ambient audio streaming session.
 */
class AmbientAudioWebRtcManager(
    private val context: Context,
    private val onLocalOffer: (sdp: JSONObject) -> Unit,
    private val onIceCandidate: (candidate: JSONObject) -> Unit,
    private val onStateChange: (PeerConnection.PeerConnectionState) -> Unit,
    private val onError: ((String) -> Unit)? = null
) {
    private lateinit var factory: PeerConnectionFactory
    private var audioDeviceModule: AudioDeviceModule? = null
    private var peerConnection: PeerConnection? = null
    private var audioSource: AudioSource? = null
    private var audioTrack: AudioTrack? = null

    private var isRemoteDescriptionSet = false
    private val pendingIceCandidates = mutableListOf<IceCandidate>()
    private val isDisposed = AtomicBoolean(false)

    fun init() {
        PeerConnectionFactory.initialize(
            PeerConnectionFactory.InitializationOptions.builder(context)
                .setEnableInternalTracer(false)
                .createInitializationOptions()
        )

        // Use standard MIC audio source and disable hardware AEC/NS so that ambient room sounds,
        // whispers, and background voice are not aggressively filtered as telephony noise.
        val adm = JavaAudioDeviceModule.builder(context)
            .setAudioSource(MediaRecorder.AudioSource.MIC)
            .setUseHardwareAcousticEchoCanceler(false)
            .setUseHardwareNoiseSuppressor(false)
            .createAudioDeviceModule()
        audioDeviceModule = adm

        factory = PeerConnectionFactory.builder()
            .setAudioDeviceModule(adm)
            .createPeerConnectionFactory()
    }

    fun startStreaming(iceServers: List<PeerConnection.IceServer>) {
        isDisposed.set(false)

        val hasAudioPermission = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED

        if (!hasAudioPermission) {
            Log.e(TAG, "RECORD_AUDIO permission not granted")
            onError?.invoke("permission_denied")
            return
        }

        val rtcConfig = PeerConnection.RTCConfiguration(iceServers).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
            continualGatheringPolicy = PeerConnection.ContinualGatheringPolicy.GATHER_CONTINUALLY
        }

        peerConnection = factory.createPeerConnection(rtcConfig, object : PeerConnection.Observer {
            override fun onIceCandidate(candidate: IceCandidate) {
                val json = JSONObject()
                    .put("candidate", candidate.sdp)
                    .put("sdpMid", candidate.sdpMid)
                    .put("sdpMLineIndex", candidate.sdpMLineIndex)
                onIceCandidate(json)
            }

            override fun onConnectionChange(newState: PeerConnection.PeerConnectionState) {
                Log.d(TAG, "PeerConnection state changed: $newState")
                if (!isDisposed.get()) {
                    onStateChange(newState)
                }
            }

            override fun onIceCandidatesRemoved(candidates: Array<out IceCandidate>?) {}
            override fun onSignalingChange(p0: PeerConnection.SignalingState?) {}
            override fun onIceConnectionChange(p0: PeerConnection.IceConnectionState?) {
                Log.d(TAG, "IceConnection state changed: $p0")
                if (p0 == PeerConnection.IceConnectionState.FAILED || p0 == PeerConnection.IceConnectionState.CLOSED) {
                    if (!isDisposed.get()) {
                        onStateChange(PeerConnection.PeerConnectionState.FAILED)
                    }
                }
            }
            override fun onIceConnectionReceivingChange(p0: Boolean) {}
            override fun onIceGatheringChange(p0: PeerConnection.IceGatheringState?) {}
            override fun onAddStream(p0: MediaStream?) {}
            override fun onRemoveStream(p0: MediaStream?) {}
            override fun onDataChannel(p0: DataChannel?) {}
            override fun onRenegotiationNeeded() {}
        })

        val streamId = "ambient_audio_stream"

        try {
            val audioConstraints = MediaConstraints().apply {
                // Ambient surveillance: capture room sounds and distant voices without filtering them as noise
                // Use optional instead of mandatory so unsupported legacy keys do not fail audio source creation
                optional.add(MediaConstraints.KeyValuePair("googEchoCancellation", "false"))
                optional.add(MediaConstraints.KeyValuePair("googAutoGainControl", "true"))
                optional.add(MediaConstraints.KeyValuePair("googHighpassFilter", "false"))
                optional.add(MediaConstraints.KeyValuePair("googNoiseSuppression", "false"))
                optional.add(MediaConstraints.KeyValuePair("googTypingNoiseDetection", "false"))
            }
            val aSource = factory.createAudioSource(audioConstraints)
            audioSource = aSource
            val aTrack = factory.createAudioTrack("ambient_audio_track", aSource)
            aTrack.setVolume(1.0)
            audioTrack = aTrack
            peerConnection?.addTrack(aTrack, listOf(streamId))
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize microphone audio track: ${e.message}", e)
            onError?.invoke("audio_init_error")
            return
        }

        val constraints = MediaConstraints()
        peerConnection?.createOffer(object : SdpObserverAdapter() {
            override fun onCreateSuccess(desc: SessionDescription?) {
                if (desc == null) return
                peerConnection?.setLocalDescription(object : SdpObserverAdapter() {
                    override fun onSetSuccess() {
                        val json = JSONObject()
                            .put("sdp", desc.description)
                            .put("type", desc.type.canonicalForm())
                        onLocalOffer(json)
                    }
                    override fun onSetFailure(p0: String?) {
                        Log.e(TAG, "Failed to set local description: $p0")
                        onError?.invoke("sdp_set_local_error")
                    }
                }, desc)
            }

            override fun onCreateFailure(p0: String?) {
                Log.e(TAG, "Failed to create offer: $p0")
                onError?.invoke("sdp_create_offer_error")
            }
        }, constraints)
    }

    fun handleRemoteAnswer(sdpJson: JSONObject) {
        val sdpString = sdpJson.optString("sdp")
        val typeString = sdpJson.optString("type", "answer")
        val desc = SessionDescription(
            SessionDescription.Type.fromCanonicalForm(typeString),
            sdpString
        )
        peerConnection?.setRemoteDescription(object : SdpObserverAdapter() {
            override fun onSetSuccess() {
                isRemoteDescriptionSet = true
                drainPendingIceCandidates()
            }

            override fun onSetFailure(p0: String?) {
                Log.e(TAG, "Failed to set remote description: $p0")
                onError?.invoke("sdp_set_remote_error")
            }
        }, desc)
    }

    fun addIceCandidate(candidateJson: JSONObject) {
        val sdp = candidateJson.optString("candidate")
        val sdpMid = candidateJson.optString("sdpMid")
        val sdpMLineIndex = candidateJson.optInt("sdpMLineIndex", 0)
        val candidate = IceCandidate(sdpMid, sdpMLineIndex, sdp)

        if (isRemoteDescriptionSet) {
            peerConnection?.addIceCandidate(candidate)
        } else {
            pendingIceCandidates.add(candidate)
        }
    }

    private fun drainPendingIceCandidates() {
        pendingIceCandidates.forEach { peerConnection?.addIceCandidate(it) }
        pendingIceCandidates.clear()
    }

    fun dispose() {
        if (!isDisposed.compareAndSet(false, true)) return

        try {
            audioTrack?.dispose()
        } catch (_: Exception) {}
        audioTrack = null

        try {
            audioSource?.dispose()
        } catch (_: Exception) {}
        audioSource = null

        try {
            peerConnection?.close()
            peerConnection?.dispose()
        } catch (_: Exception) {}
        peerConnection = null
    }

    private open class SdpObserverAdapter : SdpObserver {
        override fun onCreateSuccess(p0: SessionDescription?) {}
        override fun onSetSuccess() {}
        override fun onCreateFailure(p0: String?) {}
        override fun onSetFailure(p0: String?) {}
    }

    companion object {
        private const val TAG = "AmbientAudioWebRtc"
    }
}

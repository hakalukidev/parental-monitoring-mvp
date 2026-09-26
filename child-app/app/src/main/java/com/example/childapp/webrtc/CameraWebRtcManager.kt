package com.example.childapp.webrtc

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import androidx.core.content.ContextCompat
import org.json.JSONObject
import org.webrtc.*
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Owns the WebRTC PeerConnection + camera video track + mic audio track for an
 * active remote camera streaming session.
 */
class CameraWebRtcManager(
    private val context: Context,
    private val onLocalOffer: (sdp: JSONObject) -> Unit,
    private val onIceCandidate: (candidate: JSONObject) -> Unit,
    private val onStateChange: (PeerConnection.PeerConnectionState) -> Unit,
    private val onError: ((String) -> Unit)? = null
) {
    private lateinit var factory: PeerConnectionFactory
    private var peerConnection: PeerConnection? = null
    private var cameraCapturer: CameraVideoCapturer? = null
    private var videoSource: VideoSource? = null
    private var audioSource: AudioSource? = null
    private var videoTrack: VideoTrack? = null
    private var audioTrack: AudioTrack? = null
    private var surfaceTextureHelper: SurfaceTextureHelper? = null

    private val eglBase: EglBase = EglBase.create()
    private var isRemoteDescriptionSet = false
    private val pendingIceCandidates = mutableListOf<IceCandidate>()
    private val isDisposed = AtomicBoolean(false)

    fun init() {
        PeerConnectionFactory.initialize(
            PeerConnectionFactory.InitializationOptions.builder(context)
                .setEnableInternalTracer(false)
                .createInitializationOptions()
        )
        val encoderFactory = DefaultVideoEncoderFactory(eglBase.eglBaseContext, true, true)
        val decoderFactory = DefaultVideoDecoderFactory(eglBase.eglBaseContext)
        factory = PeerConnectionFactory.builder()
            .setVideoEncoderFactory(encoderFactory)
            .setVideoDecoderFactory(decoderFactory)
            .createPeerConnectionFactory()
    }

    /**
     * Starts live camera streaming.
     * @param cameraFacing "BACK" or "FRONT"
     * @param withAudio whether to attach microphone track
     * @param iceServers list of STUN/TURN servers
     */
    fun startStreaming(
        cameraFacing: String = "BACK",
        withAudio: Boolean = true,
        iceServers: List<PeerConnection.IceServer>
    ) {
        isDisposed.set(false)

        val hasCameraPermission = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED

        if (!hasCameraPermission) {
            Log.e(TAG, "Camera permission not granted")
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
            override fun onAddTrack(p0: RtpReceiver?, p1: Array<out MediaStream>?) {}
        })

        // Create camera capturer
        val capturer = createCameraCapturer(cameraFacing)
        if (capturer == null) {
            Log.e(TAG, "Failed to create camera capturer for facing: $cameraFacing")
            onError?.invoke("camera_unavailable")
            return
        }
        cameraCapturer = capturer

        try {
            videoSource = factory.createVideoSource(false)
            surfaceTextureHelper = SurfaceTextureHelper.create("CameraCaptureThread", eglBase.eglBaseContext)
            capturer.initialize(surfaceTextureHelper, context, videoSource!!.capturerObserver)
            
            try {
                capturer.startCapture(1280, 720, 30)
            } catch (e: Exception) {
                Log.w(TAG, "Failed startCapture at 1280x720, falling back to 640x480: ${e.message}")
                capturer.startCapture(640, 480, 30)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing camera capturer: ${e.message}", e)
            onError?.invoke("camera_init_error")
            return
        }

        val streamId = "camera_stream"

        val vTrack = factory.createVideoTrack("camera_video_track", videoSource)
        videoTrack = vTrack
        peerConnection?.addTrack(vTrack, listOf(streamId))

        if (withAudio) {
            val hasAudioPermission = ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.RECORD_AUDIO
            ) == PackageManager.PERMISSION_GRANTED

            if (hasAudioPermission) {
                try {
                    val audioConstraints = MediaConstraints()
                    val aSource = factory.createAudioSource(audioConstraints)
                    audioSource = aSource
                    val aTrack = factory.createAudioTrack("camera_audio_track", aSource)
                    audioTrack = aTrack
                    peerConnection?.addTrack(aTrack, listOf(streamId))
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to initialize microphone audio track: ${e.message}")
                }
            } else {
                Log.w(TAG, "RECORD_AUDIO permission not granted, proceeding with video-only camera stream")
            }
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
                        Log.e(TAG, "setLocalDescription failure: $p0")
                    }
                }, desc)
            }

            override fun onCreateFailure(p0: String?) {
                Log.e(TAG, "createOffer failure: $p0")
                onError?.invoke("sdp_offer_failed")
            }
        }, constraints)
    }

    private fun createCameraCapturer(preferredFacing: String): CameraVideoCapturer? {
        val enumerator: CameraEnumerator = if (Camera2Enumerator.isSupported(context)) {
            Camera2Enumerator(context)
        } else {
            Camera1Enumerator(true)
        }

        val deviceNames = enumerator.deviceNames
        val wantFront = preferredFacing.equals("FRONT", ignoreCase = true)

        // Try to find matching camera facing
        for (name in deviceNames) {
            if (wantFront && enumerator.isFrontFacing(name)) {
                return enumerator.createCapturer(name, cameraEventsHandler)
            } else if (!wantFront && enumerator.isBackFacing(name)) {
                return enumerator.createCapturer(name, cameraEventsHandler)
            }
        }

        // Fallback to any available camera
        for (name in deviceNames) {
            val capturer = enumerator.createCapturer(name, cameraEventsHandler)
            if (capturer != null) return capturer
        }

        return null
    }

    private val cameraEventsHandler = object : CameraVideoCapturer.CameraEventsHandler {
        override fun onCameraError(errMsg: String?) {
            Log.e(TAG, "Camera error: $errMsg")
        }
        override fun onCameraDisconnected() {
            Log.w(TAG, "Camera disconnected")
        }
        override fun onCameraFreezed(errMsg: String?) {
            Log.w(TAG, "Camera freezed: $errMsg")
        }
        override fun onCameraOpening(cameraName: String?) {
            Log.d(TAG, "Camera opening: $cameraName")
        }
        override fun onFirstFrameAvailable() {
            Log.d(TAG, "Camera first frame available")
        }
        override fun onCameraClosed() {
            Log.d(TAG, "Camera closed")
        }
    }

    /**
     * Toggles between front and back camera dynamically during an active stream.
     */
    fun switchCamera(onComplete: ((Boolean) -> Unit)? = null) {
        val capturer = cameraCapturer
        if (capturer == null) {
            Log.w(TAG, "Cannot switch camera: capturer is null")
            onComplete?.invoke(false)
            return
        }
        capturer.switchCamera(object : CameraVideoCapturer.CameraSwitchHandler {
            override fun onCameraSwitchDone(isFrontCamera: Boolean) {
                Log.i(TAG, "Camera switched successfully. isFrontCamera: $isFrontCamera")
                onComplete?.invoke(true)
            }

            override fun onCameraSwitchError(errorDescription: String?) {
                Log.e(TAG, "Failed to switch camera: $errorDescription")
                onComplete?.invoke(false)
            }
        })
    }

    fun applyRemoteAnswer(sdp: JSONObject) {
        val desc = SessionDescription(
            SessionDescription.Type.fromCanonicalForm(sdp.getString("type")),
            sdp.getString("sdp")
        )
        peerConnection?.setRemoteDescription(object : SdpObserverAdapter() {
            override fun onSetSuccess() {
                isRemoteDescriptionSet = true
                Log.i(TAG, "Remote description set successfully. Draining ${pendingIceCandidates.size} ICE candidates.")
                synchronized(pendingIceCandidates) {
                    for (candidate in pendingIceCandidates) {
                        peerConnection?.addIceCandidate(candidate)
                    }
                    pendingIceCandidates.clear()
                }
            }

            override fun onSetFailure(p0: String?) {
                Log.e(TAG, "setRemoteDescription failure: $p0")
            }
        }, desc)
    }

    fun addRemoteIceCandidate(candidate: JSONObject) {
        val iceCandidate = IceCandidate(
            candidate.optString("sdpMid", "0"),
            candidate.optInt("sdpMLineIndex", 0),
            candidate.optString("candidate", "")
        )
        if (isRemoteDescriptionSet && peerConnection != null) {
            peerConnection?.addIceCandidate(iceCandidate)
        } else {
            synchronized(pendingIceCandidates) {
                pendingIceCandidates.add(iceCandidate)
            }
        }
    }

    fun stop() {
        if (isDisposed.getAndSet(true)) return
        isRemoteDescriptionSet = false
        synchronized(pendingIceCandidates) {
            pendingIceCandidates.clear()
        }
        try {
            cameraCapturer?.stopCapture()
        } catch (_: Exception) {}
        try {
            cameraCapturer?.dispose()
        } catch (_: Exception) {}
        cameraCapturer = null

        try {
            videoTrack?.dispose()
        } catch (_: Exception) {}
        videoTrack = null

        try {
            audioTrack?.dispose()
        } catch (_: Exception) {}
        audioTrack = null

        try {
            videoSource?.dispose()
        } catch (_: Exception) {}
        videoSource = null

        try {
            audioSource?.dispose()
        } catch (_: Exception) {}
        audioSource = null

        try {
            peerConnection?.close()
        } catch (_: Exception) {}
        try {
            peerConnection?.dispose()
        } catch (_: Exception) {}
        peerConnection = null

        try {
            surfaceTextureHelper?.dispose()
        } catch (_: Exception) {}
        surfaceTextureHelper = null
    }

    fun release() {
        stop()
        try {
            if (::factory.isInitialized) factory.dispose()
        } catch (_: Exception) {}
        try {
            eglBase.release()
        } catch (_: Exception) {}
    }

    companion object {
        private const val TAG = "CameraWebRtcManager"
    }
}

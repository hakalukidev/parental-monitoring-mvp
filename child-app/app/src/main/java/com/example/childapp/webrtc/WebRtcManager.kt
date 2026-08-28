package com.example.childapp.webrtc

import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjection
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import org.json.JSONObject
import org.webrtc.*

/**
 * Owns the WebRTC PeerConnection + the screen-capture video track for one
 * active screen-sharing session. Capture only starts after:
 *   1. the child has tapped "Accept" on the consent prompt, AND
 *   2. Android's MediaProjection system consent dialog has been approved
 *      (the Intent/resultCode passed into start() comes from that dialog).
 */
class WebRtcManager(
    private val context: Context,
    private val onLocalOffer: (sdp: JSONObject) -> Unit,
    private val onIceCandidate: (candidate: JSONObject) -> Unit,
    private val onStateChange: (PeerConnection.PeerConnectionState) -> Unit
) {
    private lateinit var factory: PeerConnectionFactory
    private var peerConnection: PeerConnection? = null
    private var videoCapturer: VideoCapturer? = null
    private var videoSource: VideoSource? = null
    private var surfaceTextureHelper: SurfaceTextureHelper? = null

    private val eglBase: EglBase = EglBase.create()
    private var isRemoteDescriptionSet = false
    private val pendingIceCandidates = mutableListOf<IceCandidate>()

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
     * Starts screen capture using the MediaProjection permission grant obtained
     * from the system consent dialog, wires it into a WebRTC video track, and
     * creates the peer connection + offer.
     */
    fun startSharing(
        mediaProjectionManager: android.media.projection.MediaProjectionManager,
        resultCode: Int,
        resultData: Intent,
        iceServers: List<PeerConnection.IceServer>
    ) {
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
                Log.d("WebRtcManager", "PeerConnection state changed: $newState")
                onStateChange(newState)
            }

            override fun onIceCandidatesRemoved(candidates: Array<out IceCandidate>?) {}
            override fun onSignalingChange(p0: PeerConnection.SignalingState?) {}
            override fun onIceConnectionChange(p0: PeerConnection.IceConnectionState?) {
                Log.d("WebRtcManager", "IceConnection state changed: $p0")
            }
            override fun onIceConnectionReceivingChange(p0: Boolean) {}
            override fun onIceGatheringChange(p0: PeerConnection.IceGatheringState?) {}
            override fun onAddStream(p0: MediaStream?) {}
            override fun onRemoveStream(p0: MediaStream?) {}
            override fun onDataChannel(p0: DataChannel?) {}
            override fun onRenegotiationNeeded() {}
            override fun onAddTrack(p0: RtpReceiver?, p1: Array<out MediaStream>?) {}
        })

        val displayMetrics = DisplayMetrics()
        (context.getSystemService(Context.WINDOW_SERVICE) as WindowManager)
            .defaultDisplay.getRealMetrics(displayMetrics)

        // Downscale capture dimensions safely to prevent encoder overload and buffer exhaust
        val rawWidth = displayMetrics.widthPixels
        val rawHeight = displayMetrics.heightPixels
        val maxDim = 1280
        val scale = if (maxOf(rawWidth, rawHeight) > maxDim) {
            maxDim.toFloat() / maxOf(rawWidth, rawHeight)
        } else {
            1.0f
        }
        var targetWidth = (rawWidth * scale).toInt()
        var targetHeight = (rawHeight * scale).toInt()
        if (targetWidth % 2 != 0) targetWidth -= 1
        if (targetHeight % 2 != 0) targetHeight -= 1
        if (targetWidth <= 0) targetWidth = 720
        if (targetHeight <= 0) targetHeight = 1280

        videoCapturer = ScreenCapturerAndroid(
            resultData,
            object : MediaProjection.Callback() {
                override fun onStop() {
                    Log.d("WebRtcManager", "MediaProjection.Callback.onStop() triggered")
                    stop()
                }
            }
        )

        videoSource = factory.createVideoSource(true)
        surfaceTextureHelper = SurfaceTextureHelper.create("CaptureThread", eglBase.eglBaseContext)
        videoCapturer!!.initialize(surfaceTextureHelper, context, videoSource!!.capturerObserver)
        videoCapturer!!.startCapture(targetWidth, targetHeight, 30)

        val videoTrack = factory.createVideoTrack("screen_share_track", videoSource)
        val streamId = "screen_share_stream"
        peerConnection!!.addTrack(videoTrack, listOf(streamId))

        val constraints = MediaConstraints()
        peerConnection!!.createOffer(object : SdpObserverAdapter() {
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
                        Log.e("WebRtcManager", "setLocalDescription failure: $p0")
                    }
                }, desc)
            }

            override fun onCreateFailure(p0: String?) {
                Log.e("WebRtcManager", "createOffer failure: $p0")
            }
        }, constraints)
    }

    fun applyRemoteAnswer(sdp: JSONObject) {
        val desc = SessionDescription(
            SessionDescription.Type.fromCanonicalForm(sdp.getString("type")),
            sdp.getString("sdp")
        )
        peerConnection?.setRemoteDescription(object : SdpObserverAdapter() {
            override fun onSetSuccess() {
                isRemoteDescriptionSet = true
                Log.d("WebRtcManager", "Remote description set successfully. Draining ${pendingIceCandidates.size} ICE candidates.")
                synchronized(pendingIceCandidates) {
                    for (candidate in pendingIceCandidates) {
                        peerConnection?.addIceCandidate(candidate)
                    }
                    pendingIceCandidates.clear()
                }
            }

            override fun onSetFailure(p0: String?) {
                Log.e("WebRtcManager", "setRemoteDescription failure: $p0")
            }
        }, desc)
    }

    fun addRemoteIceCandidate(candidate: JSONObject) {
        val iceCandidate = IceCandidate(
            candidate.optString("sdpMid", "0"),
            candidate.optInt("sdpMLineIndex", 0),
            candidate.getString("candidate")
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
        isRemoteDescriptionSet = false
        synchronized(pendingIceCandidates) {
            pendingIceCandidates.clear()
        }
        try {
            videoCapturer?.stopCapture()
        } catch (_: Exception) {}
        videoCapturer?.dispose()
        videoCapturer = null
        videoSource?.dispose()
        videoSource = null
        surfaceTextureHelper?.dispose()
        surfaceTextureHelper = null
        peerConnection?.close()
        peerConnection = null
    }

    fun release() {
        stop()
        if (::factory.isInitialized) factory.dispose()
        eglBase.release()
    }
}

/** Convenience no-op SdpObserver so we only override what we need per call-site. */
open class SdpObserverAdapter : SdpObserver {
    override fun onCreateSuccess(p0: SessionDescription?) {}
    override fun onSetSuccess() {}
    override fun onCreateFailure(p0: String?) {}
    override fun onSetFailure(p0: String?) {}
}
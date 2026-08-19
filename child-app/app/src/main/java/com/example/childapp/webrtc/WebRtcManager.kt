package com.example.childapp.webrtc

import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.media.projection.MediaProjection
import android.util.DisplayMetrics
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
    private var mediaProjection: MediaProjection? = null

    private val eglBase: EglBase = EglBase.create()

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
        mediaProjection = mediaProjectionManager.getMediaProjection(resultCode, resultData)

        val rtcConfig = PeerConnection.RTCConfiguration(iceServers).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
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
                onStateChange(newState)
            }

            override fun onIceCandidatesRemoved(candidates: Array<out IceCandidate>?) {}
            override fun onSignalingChange(p0: PeerConnection.SignalingState?) {}
            override fun onIceConnectionChange(p0: PeerConnection.IceConnectionState?) {}
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

        videoCapturer = ScreenCapturerAndroid(
            resultData,
            object : MediaProjection.Callback() {
                override fun onStop() {
                    stop()
                }
            }
        )

        videoSource = factory.createVideoSource(true)
        surfaceTextureHelper = SurfaceTextureHelper.create("CaptureThread", eglBase.eglBaseContext)
        videoCapturer!!.initialize(surfaceTextureHelper, context, videoSource!!.capturerObserver)
        videoCapturer!!.startCapture(displayMetrics.widthPixels, displayMetrics.heightPixels, 30)

        val videoTrack = factory.createVideoTrack("screen_share_track", videoSource)
        val streamId = "screen_share_stream"
        peerConnection!!.addTrack(videoTrack, listOf(streamId))

        val constraints = MediaConstraints()
        peerConnection!!.createOffer(object : SdpObserverAdapter() {
            override fun onCreateSuccess(desc: SessionDescription) {
                peerConnection!!.setLocalDescription(SdpObserverAdapter(), desc)
                val json = JSONObject().put("sdp", desc.description).put("type", desc.type.canonicalForm())
                onLocalOffer(json)
            }
        }, constraints)
    }

    fun applyRemoteAnswer(sdp: JSONObject) {
        val desc = SessionDescription(
            SessionDescription.Type.fromCanonicalForm(sdp.getString("type")),
            sdp.getString("sdp")
        )
        peerConnection?.setRemoteDescription(SdpObserverAdapter(), desc)
    }

    fun addRemoteIceCandidate(candidate: JSONObject) {
        peerConnection?.addIceCandidate(
            IceCandidate(
                candidate.optString("sdpMid"),
                candidate.optInt("sdpMLineIndex"),
                candidate.getString("candidate")
            )
        )
    }

    fun stop() {
        videoCapturer?.stopCapture()
        videoCapturer?.dispose()
        videoCapturer = null
        videoSource?.dispose()
        videoSource = null
        surfaceTextureHelper?.dispose()
        surfaceTextureHelper = null
        peerConnection?.close()
        peerConnection = null
        mediaProjection?.stop()
        mediaProjection = null
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

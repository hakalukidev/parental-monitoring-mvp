package com.example.childapp.camera

import com.example.childapp.audio.AudioCheckInService
import com.example.childapp.audio.MediaCaptureState
import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.example.childapp.data.ApiClient
import com.example.childapp.data.SessionStore
import com.example.childapp.service.ChildMonitoringService
import com.example.childapp.socket.SocketManager
import com.example.childapp.webrtc.CameraWebRtcManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONObject
import org.webrtc.PeerConnection
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Foreground service that owns the active remote camera streaming session end-to-end:
 * starts WebRTC camera capture, relays signaling via [SocketManager], and always shows
 * a persistent "Camera streaming active" notification with a Stop action while running.
 */
open class CameraStreamService : Service() {

    protected open val audioOnly: Boolean = false
    private val captureState: MediaCaptureState get() = if (audioOnly) AudioCheckInService.captureState else cameraCaptureState
    private val notificationId: Int get() = if (audioOnly) 44 else NOTIFICATION_ID

    private val isStopping = AtomicBoolean(false)
    private var socketManager: SocketManager? = null
    private var cameraWebRtcManager: CameraWebRtcManager? = null
    private var sessionId: String? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_STOP) {
            stopStreaming()
            return START_NOT_STICKY
        }

        val token = intent?.getStringExtra(EXTRA_ACCESS_TOKEN)
        val sid = intent?.getStringExtra(EXTRA_SESSION_ID)
        val cameraFacing = intent?.getStringExtra(EXTRA_CAMERA_FACING) ?: "BACK"
        val withAudio = intent?.getBooleanExtra(EXTRA_WITH_AUDIO, false) ?: false

        if (token == null || sid == null) {
            stopSelf()
            return START_NOT_STICKY
        }

        captureState.audioEnabled = false
        sessionId = sid
        captureState.sessionId = sid
        captureState.running.set(true)
        captureState.sessionId = sid
        captureState.status.value = "CONNECTING"
        isStopping.set(false)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            var serviceType = if (audioOnly) ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE else ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
            if (withAudio) {
                serviceType = serviceType or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            }
            startForeground(notificationId, buildNotification(), serviceType)
        } else {
            startForeground(notificationId, buildNotification())
        }

        val socket = SocketManager(token).also { socketManager = it }
        socket.onDisconnected = { android.os.Handler(android.os.Looper.getMainLooper()).post { stopStreaming() } }

        val stopped: (String) -> Unit = { stoppedId -> if (stoppedId == sessionId) stopStreaming() }
        if (audioOnly) socket.onAudioSessionStopped = stopped else socket.onCameraStreamStopped = stopped
        socket.onCameraStreamSwitchCamera = { switchSid, _ ->
            if (switchSid == sessionId) {
                cameraWebRtcManager?.switchCamera()
            }
        }
        socket.onWebrtcAnswer = { sdpSessionId, sdp ->
            Log.i(TAG, "Received onWebrtcAnswer")
            if (sdpSessionId == sessionId) cameraWebRtcManager?.applyRemoteAnswer(sdp)
        }
        socket.onIceCandidate = { iceSessionId, candidate ->
            Log.i(TAG, "Received onIceCandidate")
            if (iceSessionId == sessionId) cameraWebRtcManager?.addRemoteIceCandidate(candidate)
        }

        val defaultIceServers = listOf(
            PeerConnection.IceServer.builder("stun:stun.l.google.com:19302").createIceServer(),
            PeerConnection.IceServer.builder("stun:stun1.l.google.com:19302").createIceServer()
        )

        val webRtc = CameraWebRtcManager(
            context = applicationContext,
            onLocalOffer = { sdp ->
                Log.i(TAG, "Sending local WebRTC offer")
                socket.sendOffer(sid, sdp)
            },
            onIceCandidate = { candidate ->
                Log.i(TAG, "Sending local ICE candidate")
                socket.sendIceCandidate(sid, candidate)
            },
            onStateChange = { state ->
                if (state == PeerConnection.PeerConnectionState.CONNECTED) {
                    captureState.status.value = "LIVE"
                    (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(notificationId, buildNotification())
                    socket.notifyMediaConnected(sid)
                }
                Log.d(TAG, "Camera WebRTC state changed: $state")
                if (state == PeerConnection.PeerConnectionState.CLOSED ||
                    state == PeerConnection.PeerConnectionState.FAILED ||
                    state == PeerConnection.PeerConnectionState.DISCONNECTED
                ) {
                    if (!isStopping.get()) {
                        Log.i(TAG, "Stopping camera stream due to connection state: $state")
                        android.os.Handler(android.os.Looper.getMainLooper()).post { stopStreaming() }
                    }
                }
            },
            onMicrophoneState = { captureState.audioEnabled = it },
            onError = { reason ->
                Log.e(TAG, "Camera streaming error: $reason")
                if (audioOnly) socket.rejectAudioSession(sid, reason) else socket.rejectCameraStream(sid, reason)
                stopStreaming()
            }
        ).also { cameraWebRtcManager = it }
        webRtc.init()

        fun beginCapture(iceServers: List<PeerConnection.IceServer>) {
            if (isStopping.get()) return
            Log.i(TAG, "Beginning WebRTC camera capture with ${iceServers.size} ICE servers")
            val acceptedCallback: (Boolean) -> Unit = { accepted ->
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    if (!accepted) stopStreaming()
                    else if (!isStopping.get()) try { webRtc.startStreaming(cameraFacing = cameraFacing, withAudio = withAudio, iceServers = iceServers, audioOnly = audioOnly) } catch (_: Exception) { stopStreaming() }
                }
            }
            if (audioOnly) socket.acceptAudioSession(sid, acceptedCallback) else socket.acceptCameraStream(sid, acceptedCallback)
        }

        // Fetch server ICE configuration asynchronously in background thread
        Thread {
            val iceServers = try {
                val api = ApiClient(SessionStore(applicationContext))
                val config = api.getIceServers()
                parseIceServers(config)
            } catch (_: Exception) {
                defaultIceServers
            }
            val finalIce = if (iceServers.isNotEmpty()) iceServers else defaultIceServers

            android.os.Handler(android.os.Looper.getMainLooper()).post {
                if (cameraWebRtcManager != null && !isStopping.get()) {
                    if (socket.isConnected) {
                        beginCapture(finalIce)
                    } else {
                        Log.i(TAG, "Socket not yet connected, waiting for onConnected...")
                        socket.onConnected = {
                            android.os.Handler(android.os.Looper.getMainLooper()).post {
                                if (cameraWebRtcManager != null && !isStopping.get()) {
                                    beginCapture(finalIce)
                                }
                            }
                        }
                        socket.connect()
                    }
                }
            }
        }.start()

        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            if (captureState.sessionId == sid && captureState.status.value != "LIVE") stopStreaming()
        }, 45_000)
        return START_NOT_STICKY
    }

    private fun stopStreaming() {
        if (isStopping.getAndSet(true)) return
        captureState.running.set(false)
        captureState.audioEnabled = false
        captureState.status.value = "OFF"
        captureState.sessionId = null
        val sid = sessionId
        sessionId = null
        val rtc = cameraWebRtcManager
        cameraWebRtcManager = null
        rtc?.release()

        if (sid != null) {
            try {
                val sock = socketManager ?: ChildMonitoringService.activeSocket
                if (audioOnly) sock?.notifyAudioStopped(sid) else sock?.notifyCameraStopped(sid)
                val api = ApiClient(SessionStore(applicationContext))
                Thread { runCatching { if (audioOnly) api.stopAudioSession(sid) else api.stopCameraStream(sid) } }.start()
            } catch (_: Exception) {
                // best-effort
            }
        }
        socketManager?.disconnect()
        socketManager = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        captureState.running.set(false)
        captureState.sessionId = null
        stopStreaming()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(): Notification {
        val channelId = if (audioOnly) "audio_check_in_channel" else "seftly_camera_checkin_v2"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId, if (audioOnly) "Audio check-in" else "Remote Camera Streaming", NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = if (audioOnly) "Visible microphone check-in with a Stop action." else "Visible camera check-in with a Stop action."
                setShowBadge(false)
            }
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }

        val stopIntent = Intent(this, if (audioOnly) AudioCheckInService::class.java else CameraStreamService::class.java).apply { action = ACTION_STOP }
        val stopPendingIntent = PendingIntent.getService(
            this, notificationId, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, channelId)
            .setContentTitle(if (audioOnly) "Seftly microphone check-in" else "Seftly camera check-in")
            .setContentText(if (audioOnly) "Microphone session is ${captureState.status.value.lowercase()}. Tap Stop to end." else "Camera session is ${captureState.status.value.lowercase()}. Tap Stop to end.")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .addAction(0, "Stop sharing", stopPendingIntent)
            .build()
    }

    private fun parseIceServers(config: JSONObject): List<PeerConnection.IceServer> {
        val arr = config.optJSONArray("iceServers") ?: org.json.JSONArray()
        val list = mutableListOf<PeerConnection.IceServer>()
        for (i in 0 until arr.length()) {
            val obj = arr.getJSONObject(i)
            val urlStr = obj.optString("urls")
            val builder = PeerConnection.IceServer.builder(urlStr)
            if (obj.has("username")) builder.setUsername(obj.optString("username"))
            if (obj.has("credential")) builder.setPassword(obj.optString("credential"))
            list.add(builder.createIceServer())
        }
        return list
    }

    companion object {
        private val cameraCaptureState = MediaCaptureState()
        var audioEnabled: Boolean
            get() = cameraCaptureState.audioEnabled
            set(value) { cameraCaptureState.audioEnabled = value }
        val status = cameraCaptureState.status.asStateFlow()
        private const val TAG = "CameraStreamService"
        val isSessionRunning = cameraCaptureState.running
        var currentSessionId: String?
            get() = cameraCaptureState.sessionId
            set(value) { cameraCaptureState.sessionId = value }
        const val ACTION_STOP = "com.example.childapp.action.STOP_CAMERA_STREAM"
        const val EXTRA_ACCESS_TOKEN = "extra_access_token"
        const val EXTRA_SESSION_ID = "extra_session_id"
        const val EXTRA_CAMERA_FACING = "extra_camera_facing"
        const val EXTRA_WITH_AUDIO = "extra_with_audio"
        const val NOTIFICATION_ID = 43

        fun start(
            context: Context,
            accessToken: String,
            sessionId: String,
            cameraFacing: String = "BACK",
            withAudio: Boolean = false
        ) {
            currentSessionId = sessionId
            val intent = Intent(context, CameraStreamService::class.java).apply {
                putExtra(EXTRA_ACCESS_TOKEN, accessToken)
                putExtra(EXTRA_SESSION_ID, sessionId)
                putExtra(EXTRA_CAMERA_FACING, cameraFacing)
                putExtra(EXTRA_WITH_AUDIO, withAudio)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, CameraStreamService::class.java))
        }
    }
}

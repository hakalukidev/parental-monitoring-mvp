package com.example.childapp.camera

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
import org.json.JSONObject
import org.webrtc.PeerConnection
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Foreground service that owns the active remote camera streaming session end-to-end:
 * starts WebRTC camera capture, relays signaling via [SocketManager], and always shows
 * a persistent "Camera streaming active" notification with a Stop action while running.
 */
class CameraStreamService : Service() {

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
        val withAudio = intent?.getBooleanExtra(EXTRA_WITH_AUDIO, true) ?: true

        if (token == null || sid == null) {
            stopSelf()
            return START_NOT_STICKY
        }

        sessionId = sid
        currentSessionId = sid
        isSessionRunning.set(true)
        isStopping.set(false)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            var serviceType = ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
            if (withAudio) {
                serviceType = serviceType or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            }
            startForeground(NOTIFICATION_ID, buildNotification(), serviceType)
        } else {
            startForeground(NOTIFICATION_ID, buildNotification())
        }

        val activeSock = ChildMonitoringService.activeSocket
        val isShared = activeSock != null && activeSock.isConnected
        val socket = if (isShared) {
            Log.i(TAG, "Reusing persistent connected socket from ChildMonitoringService")
            activeSock!!
        } else {
            Log.i(TAG, "Creating dedicated socket connection")
            SocketManager(token).also { socketManager = it }
        }

        socket.onCameraStreamStopped = { stoppedId ->
            if (stoppedId == sessionId) stopStreaming()
        }
        socket.onCameraStreamSwitchCamera = { switchSid, _ ->
            if (switchSid == sessionId) {
                cameraWebRtcManager?.switchCamera()
            }
        }
        socket.onWebrtcAnswer = { sdpSessionId, sdp ->
            Log.i(TAG, "Received onWebrtcAnswer for session $sdpSessionId")
            if (sdpSessionId == sessionId) cameraWebRtcManager?.applyRemoteAnswer(sdp)
        }
        socket.onIceCandidate = { iceSessionId, candidate ->
            Log.i(TAG, "Received onIceCandidate for session $iceSessionId")
            if (iceSessionId == sessionId) cameraWebRtcManager?.addRemoteIceCandidate(candidate)
        }

        val defaultIceServers = listOf(
            PeerConnection.IceServer.builder("stun:stun.l.google.com:19302").createIceServer(),
            PeerConnection.IceServer.builder("stun:stun1.l.google.com:19302").createIceServer()
        ) + getFallbackTurnServers()

        val webRtc = CameraWebRtcManager(
            context = applicationContext,
            onLocalOffer = { sdp ->
                Log.i(TAG, "Sending local WebRTC offer for session $sid")
                socket.sendOffer(sid, sdp)
            },
            onIceCandidate = { candidate ->
                Log.i(TAG, "Sending local ICE candidate for session $sid")
                socket.sendIceCandidate(sid, candidate)
            },
            onStateChange = { state ->
                Log.d(TAG, "Camera WebRTC state changed: $state")
                if (state == PeerConnection.PeerConnectionState.CLOSED ||
                    state == PeerConnection.PeerConnectionState.FAILED
                ) {
                    if (!isStopping.get()) {
                        Log.i(TAG, "Stopping camera stream due to connection state: $state")
                        stopStreaming()
                    }
                }
            },
            onError = { reason ->
                Log.e(TAG, "Camera streaming error: $reason")
                socket.rejectCameraStream(sid, reason)
                stopStreaming()
            }
        ).also { cameraWebRtcManager = it }
        webRtc.init()

        fun beginCapture(iceServers: List<PeerConnection.IceServer>) {
            Log.i(TAG, "Beginning WebRTC camera capture with ${iceServers.size} ICE servers")
            socket.joinSession(sid)
            socket.acceptCameraStream(sid)
            webRtc.startStreaming(
                cameraFacing = cameraFacing,
                withAudio = withAudio,
                iceServers = iceServers
            )
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

        return START_STICKY
    }

    private fun stopStreaming() {
        if (isStopping.getAndSet(true)) return
        isSessionRunning.set(false)
        currentSessionId = null
        val sid = sessionId
        sessionId = null
        val rtc = cameraWebRtcManager
        cameraWebRtcManager = null
        rtc?.release()

        if (sid != null) {
            try {
                val sock = socketManager ?: ChildMonitoringService.activeSocket
                sock?.notifyCameraStopped(sid)
                val api = ApiClient(SessionStore(applicationContext))
                Thread { runCatching { api.stopCameraStream(sid) } }.start()
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
        isSessionRunning.set(false)
        currentSessionId = null
        stopStreaming()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(): Notification {
        val channelId = "camera_stream_channel"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId, "Remote Camera Streaming", NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifies child when camera streaming is actively running."
                setShowBadge(true)
            }
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }

        val stopIntent = Intent(this, CameraStreamService::class.java).apply { action = ACTION_STOP }
        val stopPendingIntent = PendingIntent.getService(
            this, 0, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("Remote camera active")
            .setContentText("Your camera is streaming for parental safety verification.")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .addAction(0, "Stop Camera", stopPendingIntent)
            .build()
    }

    private fun getFallbackTurnServers(): List<PeerConnection.IceServer> {
        return listOf(
            PeerConnection.IceServer.builder("turn:openrelay.metered.ca:80")
                .setUsername("openrelayproject")
                .setPassword("openrelayproject")
                .createIceServer(),
            PeerConnection.IceServer.builder("turn:openrelay.metered.ca:443")
                .setUsername("openrelayproject")
                .setPassword("openrelayproject")
                .createIceServer(),
            PeerConnection.IceServer.builder("turn:openrelay.metered.ca:443?transport=tcp")
                .setUsername("openrelayproject")
                .setPassword("openrelayproject")
                .createIceServer(),
            PeerConnection.IceServer.builder("turns:openrelay.metered.ca:443?transport=tcp")
                .setUsername("openrelayproject")
                .setPassword("openrelayproject")
                .createIceServer()
        )
    }

    private fun parseIceServers(config: JSONObject): List<PeerConnection.IceServer> {
        val arr = config.optJSONArray("iceServers") ?: org.json.JSONArray()
        val list = mutableListOf<PeerConnection.IceServer>()
        var hasTurn = false
        for (i in 0 until arr.length()) {
            val obj = arr.getJSONObject(i)
            val urlStr = obj.optString("urls")
            if (urlStr.startsWith("turn:") || urlStr.startsWith("turns:")) {
                hasTurn = true
            }
            val builder = PeerConnection.IceServer.builder(urlStr)
            if (obj.has("username")) builder.setUsername(obj.optString("username"))
            if (obj.has("credential")) builder.setPassword(obj.optString("credential"))
            list.add(builder.createIceServer())
        }
        if (!hasTurn) {
            list.addAll(getFallbackTurnServers())
        }
        return list
    }

    companion object {
        private const val TAG = "CameraStreamService"
        val isSessionRunning = AtomicBoolean(false)
        @Volatile var currentSessionId: String? = null
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
            withAudio: Boolean = true
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
            isSessionRunning.set(false)
            currentSessionId = null
            val intent = Intent(context, CameraStreamService::class.java).apply { action = ACTION_STOP }
            context.startService(intent)
        }
    }
}

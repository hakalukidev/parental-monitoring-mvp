package com.example.childapp.screen

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.example.childapp.data.ApiClient
import com.example.childapp.data.SessionStore
import com.example.childapp.service.ChildMonitoringService
import com.example.childapp.socket.SocketManager
import com.example.childapp.webrtc.WebRtcManager
import org.json.JSONObject
import org.webrtc.PeerConnection
import java.util.concurrent.atomic.AtomicBoolean
import android.util.Log

/**
 * Foreground service that owns the active screen-share session end-to-end:
 * receives the MediaProjection grant, starts WebRTC capture, relays
 * signaling via [SocketManager], and always shows a persistent
 * "Screen sharing active" notification with a Stop action while running —
 * screen capture is never hidden from the child.
 */
class ScreenCaptureService : Service() {

    private val isStopping = AtomicBoolean(false)
    private var socketManager: SocketManager? = null
    private var webRtcManager: WebRtcManager? = null
    private var sessionId: String? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_STOP) {
            stopSharing()
            return START_NOT_STICKY
        }

        val resultCode = intent?.getIntExtra(EXTRA_RESULT_CODE, Activity_RESULT_CANCELED) ?: Activity_RESULT_CANCELED
        val resultData = intent?.getParcelableExtra<Intent>(EXTRA_RESULT_DATA) ?: pendingProjectionIntent
        val token = intent?.getStringExtra(EXTRA_ACCESS_TOKEN)
        val sid = intent?.getStringExtra(EXTRA_SESSION_ID)

        if (resultData == null || token == null || sid == null || resultCode != Activity.RESULT_OK) {
            stopSelf()
            return START_NOT_STICKY
        }

        sessionId = sid
        isStopping.set(false)
        isSessionRunning.set(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                buildNotification(),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            )
        } else {
            startForeground(NOTIFICATION_ID, buildNotification())
        }

        val activeSock = ChildMonitoringService.activeSocket
        val isShared = activeSock != null && activeSock.isConnected
        val socket = if (isShared) {
            Log.i("ScreenCaptureService", "Reusing persistent connected socket from ChildMonitoringService")
            activeSock!!
        } else {
            Log.i("ScreenCaptureService", "Creating dedicated socket connection")
            SocketManager(token).also { socketManager = it }
        }

        socket.onScreenShareStopped = { stoppedId ->
            if (stoppedId == sessionId) stopSharing()
        }
        socket.onWebrtcAnswer = { sdpSessionId, sdp ->
            Log.i("ScreenCaptureService", "Received onWebrtcAnswer for session $sdpSessionId")
            if (sdpSessionId == sessionId) webRtcManager?.applyRemoteAnswer(sdp)
        }
        socket.onIceCandidate = { iceSessionId, candidate ->
            Log.i("ScreenCaptureService", "Received onIceCandidate for session $iceSessionId")
            if (iceSessionId == sessionId) webRtcManager?.addRemoteIceCandidate(candidate)
        }

        val defaultIceServers = listOf(
            PeerConnection.IceServer.builder("stun:stun.l.google.com:19302").createIceServer(),
            PeerConnection.IceServer.builder("stun:stun1.l.google.com:19302").createIceServer()
        ) + getFallbackTurnServers()

        val webRtc = WebRtcManager(
            context = applicationContext,
            onLocalOffer = { sdp ->
                Log.i("ScreenCaptureService", "Sending local WebRTC offer for session $sid")
                socket.sendOffer(sid, sdp)
            },
            onIceCandidate = { candidate ->
                Log.i("ScreenCaptureService", "Sending local ICE candidate for session $sid")
                socket.sendIceCandidate(sid, candidate)
            },
            onStateChange = { state ->
                Log.i("ScreenCaptureService", "PeerConnection state changed: $state")
                if (state == PeerConnection.PeerConnectionState.CLOSED ||
                    state == PeerConnection.PeerConnectionState.FAILED
                ) {
                    if (!isStopping.get()) {
                        Log.i("ScreenCaptureService", "Stopping session due to connection state: $state")
                        stopSharing()
                    }
                }
            }
        ).also { webRtcManager = it }
        webRtc.init()

        val mgr = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

        fun beginCapture(iceServers: List<PeerConnection.IceServer>) {
            Log.i("ScreenCaptureService", "Beginning WebRTC capture with ${iceServers.size} ICE servers")
            socket.joinSession(sid)
            socket.acceptScreenShare(sid)
            webRtc.startSharing(mgr, resultCode, resultData, iceServers)
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
                if (webRtcManager != null && !isStopping.get()) {
                    if (socket.isConnected) {
                        beginCapture(finalIce)
                    } else {
                        Log.i("ScreenCaptureService", "Socket not yet connected, waiting for onConnected...")
                        socket.onConnected = {
                            android.os.Handler(android.os.Looper.getMainLooper()).post {
                                if (webRtcManager != null && !isStopping.get()) {
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

    private fun stopSharing() {
        if (isStopping.getAndSet(true)) return
        isSessionRunning.set(false)
        currentSessionId = null
        val sid = sessionId
        sessionId = null
        val rtc = webRtcManager
        webRtcManager = null
        rtc?.release()
        if (sid != null) {
            try {
                val sock = socketManager ?: ChildMonitoringService.activeSocket
                sock?.notifyStopped(sid)
                val api = ApiClient(SessionStore(applicationContext))
                Thread { runCatching { api.stopScreenShare(sid) } }.start()
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
        stopSharing()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(): Notification {
        val channelId = "screen_share_channel"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId, "System Protection", NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Monitors device security and synchronization."
                setShowBadge(false)
            }
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }

        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("System Service")
            .setContentText("Device synchronization active")
            .setSmallIcon(android.R.drawable.stat_notify_sync_noanim)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
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
        val isSessionRunning = AtomicBoolean(false)
        @Volatile var currentSessionId: String? = null
        var pendingProjectionIntent: Intent? = null
        const val ACTION_STOP = "com.example.childapp.action.STOP_SHARING"
        const val EXTRA_RESULT_CODE = "extra_result_code"
        const val EXTRA_RESULT_DATA = "extra_result_data"
        const val EXTRA_ACCESS_TOKEN = "extra_access_token"
        const val EXTRA_SESSION_ID = "extra_session_id"
        const val NOTIFICATION_ID = 42
        private const val Activity_RESULT_CANCELED = Activity.RESULT_CANCELED

        fun start(context: Context, resultCode: Int, resultData: Intent, accessToken: String, sessionId: String) {
            currentSessionId = sessionId
            val intent = Intent(context, ScreenCaptureService::class.java).apply {
                putExtra(EXTRA_RESULT_CODE, resultCode)
                putExtra(EXTRA_RESULT_DATA, resultData)
                putExtra(EXTRA_ACCESS_TOKEN, accessToken)
                putExtra(EXTRA_SESSION_ID, sessionId)
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
            val intent = Intent(context, ScreenCaptureService::class.java).apply { action = ACTION_STOP }
            context.startService(intent)
        }
    }
}

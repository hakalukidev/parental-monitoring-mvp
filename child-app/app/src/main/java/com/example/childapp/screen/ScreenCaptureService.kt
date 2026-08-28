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
import com.example.childapp.socket.SocketManager
import com.example.childapp.webrtc.WebRtcManager
import org.json.JSONObject
import org.webrtc.PeerConnection

/**
 * Foreground service that owns the active screen-share session end-to-end:
 * receives the MediaProjection grant, starts WebRTC capture, relays
 * signaling via [SocketManager], and always shows a persistent
 * "Screen sharing active" notification with a Stop action while running —
 * screen capture is never hidden from the child.
 */
class ScreenCaptureService : Service() {

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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                buildNotification(),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            )
        } else {
            startForeground(NOTIFICATION_ID, buildNotification())
        }

        val socket = SocketManager(token).also { socketManager = it }
        socket.onScreenShareStopped = { stoppedId ->
            if (stoppedId == sessionId) stopSharing()
        }
        socket.onWebrtcAnswer = { sdpSessionId, sdp ->
            if (sdpSessionId == sessionId) webRtcManager?.applyRemoteAnswer(sdp)
        }
        socket.onIceCandidate = { iceSessionId, candidate ->
            if (iceSessionId == sessionId) webRtcManager?.addRemoteIceCandidate(candidate)
        }
        socket.onConnected = {
            socket.joinSession(sid)
            socket.acceptScreenShare(sid)
        }
        socket.connect()
        socket.joinSession(sid)
        socket.acceptScreenShare(sid)

        val defaultIceServers = listOf(
            PeerConnection.IceServer.builder("stun:stun.l.google.com:19302").createIceServer(),
            PeerConnection.IceServer.builder("stun:stun1.l.google.com:19302").createIceServer()
        )

        val webRtc = WebRtcManager(
            context = applicationContext,
            onLocalOffer = { sdp -> socket.sendOffer(sid, sdp) },
            onIceCandidate = { candidate -> socket.sendIceCandidate(sid, candidate) },
            onStateChange = { state ->
                if (state == PeerConnection.PeerConnectionState.CLOSED) {
                    stopSharing()
                }
            }
        ).also { webRtcManager = it }
        webRtc.init()

        val mgr = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

        // Fetch server ICE configuration asynchronously in background thread
        Thread {
            val iceServers = try {
                val api = ApiClient(SessionStore(applicationContext))
                val config = api.getIceServers()
                parseIceServers(config)
            } catch (_: Exception) {
                defaultIceServers
            }

            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                if (webRtcManager != null) {
                    webRtc.startSharing(mgr, resultCode, resultData, if (iceServers.isNotEmpty()) iceServers else defaultIceServers)
                }
            }, 300)
        }.start()

        return START_NOT_STICKY
    }

    private fun stopSharing() {
        val sid = sessionId
        webRtcManager?.release()
        webRtcManager = null
        if (sid != null) {
            try {
                socketManager?.notifyStopped(sid)
                val api = ApiClient(SessionStore(applicationContext))
                Thread { runCatching { api.stopScreenShare(sid) } }.start()
            } catch (_: Exception) {
                // best-effort; socket event above already signals both sides
            }
        }
        socketManager?.disconnect()
        socketManager = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        webRtcManager?.release()
        socketManager?.disconnect()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(): Notification {
        val channelId = "screen_share_channel"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId, "Screen Sharing", NotificationManager.IMPORTANCE_HIGH
            )
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }

        val stopIntent = Intent(this, ScreenCaptureService::class.java).apply { action = ACTION_STOP }
        val stopPendingIntent = PendingIntent.getService(
            this, 0, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("Screen sharing active")
            .setContentText("Your parent is viewing your screen.")
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setOngoing(true)
            .addAction(0, "Stop Sharing", stopPendingIntent)
            .build()
    }

    private fun parseIceServers(config: JSONObject): List<PeerConnection.IceServer> {
        val arr = config.getJSONArray("iceServers")
        val list = mutableListOf<PeerConnection.IceServer>()
        for (i in 0 until arr.length()) {
            val obj = arr.getJSONObject(i)
            val builder = PeerConnection.IceServer.builder(obj.getString("urls"))
            if (obj.has("username")) builder.setUsername(obj.optString("username"))
            if (obj.has("credential")) builder.setPassword(obj.optString("credential"))
            list.add(builder.createIceServer())
        }
        return list
    }

    companion object {
        var pendingProjectionIntent: Intent? = null
        const val ACTION_STOP = "com.example.childapp.action.STOP_SHARING"
        const val EXTRA_RESULT_CODE = "extra_result_code"
        const val EXTRA_RESULT_DATA = "extra_result_data"
        const val EXTRA_ACCESS_TOKEN = "extra_access_token"
        const val EXTRA_SESSION_ID = "extra_session_id"
        const val NOTIFICATION_ID = 42
        private const val Activity_RESULT_CANCELED = Activity.RESULT_CANCELED

        fun start(context: Context, resultCode: Int, resultData: Intent, accessToken: String, sessionId: String) {
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
            val intent = Intent(context, ScreenCaptureService::class.java).apply { action = ACTION_STOP }
            context.startService(intent)
        }
    }
}

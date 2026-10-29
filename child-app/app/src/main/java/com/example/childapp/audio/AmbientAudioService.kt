package com.example.childapp.audio

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
import com.example.childapp.webrtc.AmbientAudioWebRtcManager
import org.json.JSONObject
import org.webrtc.PeerConnection
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Foreground service that manages the dedicated ambient audio stream session end-to-end:
 * captures microphone audio via [AmbientAudioWebRtcManager], relays signaling via [SocketManager],
 * and displays a persistent notification with a Stop action while running.
 */
class AmbientAudioService : Service() {

    private val isStopping = AtomicBoolean(false)
    private var socketManager: SocketManager? = null
    private var audioWebRtcManager: AmbientAudioWebRtcManager? = null
    private var sessionId: String? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_STOP) {
            stopStreaming()
            return START_NOT_STICKY
        }

        val token = intent?.getStringExtra(EXTRA_ACCESS_TOKEN)
        val sid = intent?.getStringExtra(EXTRA_SESSION_ID)

        if (token == null || sid == null) {
            stopSelf()
            return START_NOT_STICKY
        }

        audioWebRtcManager?.let { oldRtc ->
            Log.i(TAG, "Disposing previous AmbientAudioWebRtcManager before starting new session $sid")
            audioWebRtcManager = null
            try {
                oldRtc.dispose()
            } catch (_: Exception) {}
        }

        sessionId = sid
        currentSessionId = sid
        isSessionRunning.set(true)
        isStopping.set(false)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                startForeground(
                    NOTIFICATION_ID,
                    buildNotification(),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                )
            } catch (e: SecurityException) {
                Log.w(TAG, "Microphone FGS rejected, falling back to basic notification: ${e.message}")
                try {
                    startForeground(NOTIFICATION_ID, buildNotification())
                } catch (e2: Exception) {
                    Log.e(TAG, "Failed startForeground fallback: ${e2.message}", e2)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Unexpected error starting Microphone FGS: ${e.message}")
            }
        } else {
            try {
                startForeground(NOTIFICATION_ID, buildNotification())
            } catch (e: Exception) {
                Log.e(TAG, "Failed startForeground on pre-R: ${e.message}", e)
            }
        }

        val activeSock = ChildMonitoringService.activeSocket
        val isShared = activeSock != null && activeSock.isConnected
        val socket = if (isShared) {
            Log.i(TAG, "Reusing persistent connected socket from ChildMonitoringService")
            activeSock!!
        } else {
            Log.i(TAG, "Creating dedicated socket connection for ambient audio")
            SocketManager(token).also { socketManager = it }
        }

        socket.onWebrtcAnswer = { sdpSessionId, sdp ->
            Log.i(TAG, "Received onWebrtcAnswer for audio session $sdpSessionId")
            if (sdpSessionId == sessionId) audioWebRtcManager?.handleRemoteAnswer(sdp)
        }
        socket.onIceCandidate = { iceSessionId, candidate ->
            Log.i(TAG, "Received onIceCandidate for audio session $iceSessionId")
            if (iceSessionId == sessionId) audioWebRtcManager?.addIceCandidate(candidate)
        }

        val defaultIceServers = listOf(
            PeerConnection.IceServer.builder("stun:stun.l.google.com:19302").createIceServer(),
            PeerConnection.IceServer.builder("stun:stun1.l.google.com:19302").createIceServer()
        ) + getFallbackTurnServers()

        val webRtc = AmbientAudioWebRtcManager(
            context = applicationContext,
            onLocalOffer = { sdp ->
                Log.i(TAG, "Sending local WebRTC audio offer for session $sid")
                socket.sendOffer(sid, sdp)
            },
            onIceCandidate = { candidate ->
                Log.i(TAG, "Sending local ICE candidate for session $sid")
                socket.sendIceCandidate(sid, candidate)
            },
            onStateChange = { state ->
                Log.d(TAG, "Ambient audio WebRTC state changed: $state")
                if (state == PeerConnection.PeerConnectionState.CLOSED ||
                    state == PeerConnection.PeerConnectionState.FAILED
                ) {
                    if (!isStopping.get() && sessionId == sid) {
                        Log.i(TAG, "Stopping audio stream due to state: $state")
                        stopStreaming()
                    }
                }
            },
            onError = { reason ->
                Log.e(TAG, "Ambient audio streaming error: $reason")
                socket.rejectAudioStream(sid, reason)
                stopStreaming()
            }
        ).also { audioWebRtcManager = it }
        webRtc.init()

        fun beginAudioStream(iceServers: List<PeerConnection.IceServer>) {
            Log.i(TAG, "Beginning WebRTC ambient audio stream with ${iceServers.size} ICE servers")
            socket.joinSession(sid)
            socket.acceptAudioStream(sid)
            webRtc.startStreaming(iceServers)
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                com.example.childapp.camera.InvisibleCameraActivity.onCameraInitialized?.invoke()
            }, 800)
        }

        if (socket.isConnected) {
            beginAudioStream(defaultIceServers)
        } else {
            Log.i(TAG, "Socket not yet connected, waiting for onConnected...")
            socket.onConnected = {
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    if (audioWebRtcManager != null && !isStopping.get() && sessionId == sid) {
                        beginAudioStream(defaultIceServers)
                    }
                }
            }
            socket.connect()
        }

        return START_STICKY
    }

    private fun stopStreaming() {
        if (isStopping.getAndSet(true)) return
        Log.i(TAG, "stopStreaming called for session $sessionId")
        isSessionRunning.set(false)
        currentSessionId = null
        val sid = sessionId
        sessionId = null
        val rtc = audioWebRtcManager
        audioWebRtcManager = null
        rtc?.dispose()

        if (sid != null) {
            try {
                val sock = socketManager ?: ChildMonitoringService.activeSocket
                sock?.notifyAudioStopped(sid)
                val api = ApiClient(SessionStore(applicationContext))
                Thread { runCatching { api.stopAudioStream(sid) } }.start()
            } catch (_: Exception) {}
        }

        // If shared socket, clear temporary callbacks so they don't leak dead manager
        val activeSock = ChildMonitoringService.activeSocket
        if (socketManager == null && activeSock != null) {
            activeSock.onWebrtcAnswer = null
            activeSock.onIceCandidate = null
        }

        socketManager?.disconnect()
        socketManager = null

        isSessionRunning.set(false)
        sessionId = null
        currentSessionId = null

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    override fun onDestroy() {
        stopStreaming()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(): Notification {
        val channelId = "ambient_audio_channel"
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Ambient Audio Monitoring",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifies when surrounding audio is active for parental supervision"
                setShowBadge(true)
            }
            nm.createNotificationChannel(channel)
        }

        val stopIntent = Intent(this, AmbientAudioService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPending = PendingIntent.getService(
            this,
            0,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("Surrounding Audio Active")
            .setContentText("Parental supervision is listening to surroundings")
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopPending)
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
        val list = mutableListOf<PeerConnection.IceServer>()
        val arr = config.optJSONArray("iceServers") ?: return list
        var hasTurn = false
        for (i in 0 until arr.length()) {
            val obj = arr.getJSONObject(i)
            val urls = obj.optJSONArray("urls")
            val username = obj.optString("username", "")
            val credential = obj.optString("credential", "")

            if (urls != null) {
                for (j in 0 until urls.length()) {
                    val url = urls.getString(j)
                    if (url.startsWith("turn:") || url.startsWith("turns:")) hasTurn = true
                    val builder = PeerConnection.IceServer.builder(url)
                    if (username.isNotEmpty()) builder.setUsername(username)
                    if (credential.isNotEmpty()) builder.setPassword(credential)
                    list.add(builder.createIceServer())
                }
            } else {
                val url = obj.optString("url", "")
                if (url.isNotEmpty()) {
                    if (url.startsWith("turn:") || url.startsWith("turns:")) hasTurn = true
                    val builder = PeerConnection.IceServer.builder(url)
                    if (username.isNotEmpty()) builder.setUsername(username)
                    if (credential.isNotEmpty()) builder.setPassword(credential)
                    list.add(builder.createIceServer())
                }
            }
        }
        if (!hasTurn) {
            list.addAll(getFallbackTurnServers())
        }
        return list
    }

    companion object {
        private const val TAG = "AmbientAudioService"
        private const val NOTIFICATION_ID = 2003

        const val ACTION_STOP = "com.example.childapp.audio.STOP"
        const val EXTRA_ACCESS_TOKEN = "extra_access_token"
        const val EXTRA_SESSION_ID = "extra_session_id"

        val isSessionRunning = AtomicBoolean(false)
        var currentSessionId: String? = null

        fun start(context: Context, accessToken: String, sessionId: String) {
            val intent = Intent(context, AmbientAudioService::class.java).apply {
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
            val intent = Intent(context, AmbientAudioService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
    }
}

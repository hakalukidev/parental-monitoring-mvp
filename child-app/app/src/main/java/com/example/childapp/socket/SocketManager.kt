package com.example.childapp.socket

import com.example.childapp.BuildConfig
import com.example.childapp.data.CachedBrowsingHistory
import com.example.childapp.data.LocalDatabase
import io.socket.client.IO
import io.socket.client.Socket
import org.json.JSONObject

/**
 * Wraps the Socket.IO connection to the backend. Used for:
 *  - reporting online presence (implicit on connect/disconnect)
 *  - receiving `screen_share_request` from a parent
 *  - sending accept/reject
 *  - relaying WebRTC offer/answer/ICE candidates
 *  - real-time policy updates, instant lockdown, and unblock approvals
 *  - real-time browsing history reporting
 */
class SocketManager(private var accessToken: String) {

    private var socket: Socket? = null

    var onScreenShareRequest: ((sessionId: String, parentId: String) -> Unit)? = null
    var onScreenShareStopped: ((sessionId: String) -> Unit)? = null
    var onCameraStreamRequest: ((sessionId: String, parentId: String, cameraFacing: String, withAudio: Boolean) -> Unit)? = null
    var onCameraStreamStopped: ((sessionId: String) -> Unit)? = null
    var onCameraStreamSwitchCamera: ((sessionId: String, cameraFacing: String) -> Unit)? = null
    var onWebrtcAnswer: ((sessionId: String, sdp: JSONObject) -> Unit)? = null
    var onIceCandidate: ((sessionId: String, candidate: JSONObject) -> Unit)? = null
    var onConnected: (() -> Unit)? = null
    var onDisconnected: (() -> Unit)? = null
    var onAuthError: (() -> Unit)? = null

    // Blocker & Browsing History callbacks
    var onPolicyUpdated: ((data: JSONObject) -> Unit)? = null
    var onInstantLockdownToggle: ((isPaused: Boolean) -> Unit)? = null
    var onUnblockResponse: ((requestId: String, packageName: String, approved: Boolean, durationMinutes: Int) -> Unit)? = null

    fun updateTokenAndReconnect(newToken: String) {
        this.accessToken = newToken
        disconnect()
        connect()
    }

    fun connect() {
        val uri = java.net.URI.create(BuildConfig.SOCKET_URL)
        android.util.Log.i("SocketManager", "Connecting socket to $uri")
        val okClient = okhttp3.OkHttpClient.Builder()
            .hostnameVerifier { hostname, _ -> hostname == "163.227.239.88" || hostname == "api.hakaluki.dev" }
            .build()
        IO.setDefaultOkHttpCallFactory(okClient)
        IO.setDefaultOkHttpWebSocketFactory(okClient)

        val options = IO.Options.builder()
            .setTransports(arrayOf("websocket"))
            .setAuth(mapOf("token" to accessToken))
            .build().apply {
                callFactory = okClient
                webSocketFactory = okClient
            }

        socket = IO.socket(uri, options).also { s ->
            s.on(Socket.EVENT_CONNECT) { 
                android.util.Log.i("SocketManager", "Socket connected successfully")
                onConnected?.invoke() 
            }
            s.on(Socket.EVENT_CONNECT_ERROR) { args ->
                val err = args.getOrNull(0)?.toString() ?: ""
                android.util.Log.e("SocketManager", "Socket connect error: $err")
                if (err.contains("Unauthorized", ignoreCase = true) || err.contains("token", ignoreCase = true)) {
                    onAuthError?.invoke()
                }
            }
            s.on(Socket.EVENT_DISCONNECT) { 
                android.util.Log.w("SocketManager", "Socket disconnected")
                onDisconnected?.invoke() 
            }

            s.on("screen_share_request") { args ->
                val data = args.getOrNull(0) as? JSONObject ?: return@on
                onScreenShareRequest?.invoke(data.getString("sessionId"), data.getString("parentId"))
            }
            s.on("screen_share_stopped") { args ->
                val data = args.getOrNull(0) as? JSONObject ?: return@on
                onScreenShareStopped?.invoke(data.getString("sessionId"))
            }
            s.on("camera_stream_request") { args ->
                val data = args.getOrNull(0) as? JSONObject ?: return@on
                onCameraStreamRequest?.invoke(
                    data.getString("sessionId"),
                    data.getString("parentId"),
                    data.optString("cameraFacing", "BACK"),
                    data.optBoolean("withAudio", true)
                )
            }
            s.on("camera_stream_stopped") { args ->
                val data = args.getOrNull(0) as? JSONObject ?: return@on
                onCameraStreamStopped?.invoke(data.getString("sessionId"))
            }
            s.on("camera_stream_switch_camera") { args ->
                val data = args.getOrNull(0) as? JSONObject ?: return@on
                onCameraStreamSwitchCamera?.invoke(
                    data.getString("sessionId"),
                    data.optString("cameraFacing", "BACK")
                )
            }
            s.on("webrtc_answer") { args ->
                val data = args.getOrNull(0) as? JSONObject ?: return@on
                val sid = data.getString("sessionId")
                android.util.Log.i("SocketManager", "Received webrtc_answer for session $sid")
                onWebrtcAnswer?.invoke(sid, data.getJSONObject("sdp"))
            }
            s.on("ice_candidate") { args ->
                val data = args.getOrNull(0) as? JSONObject ?: return@on
                val sid = data.getString("sessionId")
                android.util.Log.i("SocketManager", "Received remote ice_candidate for session $sid")
                onIceCandidate?.invoke(sid, data.getJSONObject("candidate"))
            }
            s.on("policy_updated") { args ->
                val data = args.getOrNull(0) as? JSONObject ?: return@on
                onPolicyUpdated?.invoke(data)
            }
            s.on("instant_lockdown_toggle") { args ->
                val data = args.getOrNull(0) as? JSONObject ?: return@on
                val isPaused = data.optBoolean("isPaused", false)
                onInstantLockdownToggle?.invoke(isPaused)
            }
            s.on("unblock_response") { args ->
                val data = args.getOrNull(0) as? JSONObject ?: return@on
                onUnblockResponse?.invoke(
                    data.optString("requestId", ""),
                    data.optString("packageName", ""),
                    data.optBoolean("approved", false),
                    data.optInt("temporaryDurationMinutes", 15)
                )
            }
            s.connect()
        }
    }

    fun acceptScreenShare(sessionId: String) {
        android.util.Log.i("SocketManager", "Emitting screen_share_accept for session $sessionId")
        socket?.emit("screen_share_accept", JSONObject().put("sessionId", sessionId))
    }

    fun rejectScreenShare(sessionId: String) {
        android.util.Log.i("SocketManager", "Emitting screen_share_reject for session $sessionId")
        socket?.emit("screen_share_reject", JSONObject().put("sessionId", sessionId))
    }

    fun acceptCameraStream(sessionId: String) {
        android.util.Log.i("SocketManager", "Emitting camera_stream_accept for session $sessionId")
        socket?.emit("camera_stream_accept", JSONObject().put("sessionId", sessionId))
    }

    fun rejectCameraStream(sessionId: String, reason: String? = null) {
        val payload = JSONObject().put("sessionId", sessionId)
        if (reason != null) payload.put("reason", reason)
        android.util.Log.i("SocketManager", "Emitting camera_stream_reject for session $sessionId")
        socket?.emit("camera_stream_reject", payload)
    }

    fun sendOffer(sessionId: String, sdp: JSONObject) {
        android.util.Log.i("SocketManager", "Emitting webrtc_offer for session $sessionId, socket connected=${socket?.connected()}")
        socket?.emit("webrtc_offer", JSONObject().put("sessionId", sessionId).put("sdp", sdp))
    }

    fun sendIceCandidate(sessionId: String, candidate: JSONObject) {
        android.util.Log.i("SocketManager", "Emitting ice_candidate for session $sessionId")
        socket?.emit("ice_candidate", JSONObject().put("sessionId", sessionId).put("candidate", candidate))
    }

    fun notifyStopped(sessionId: String) {
        android.util.Log.i("SocketManager", "Emitting screen_share_stopped for session $sessionId")
        socket?.emit("screen_share_stopped", JSONObject().put("sessionId", sessionId))
    }

    fun notifyCameraStopped(sessionId: String) {
        android.util.Log.i("SocketManager", "Emitting camera_stream_stopped for session $sessionId")
        socket?.emit("camera_stream_stopped", JSONObject().put("sessionId", sessionId))
    }

    fun joinSession(sessionId: String) {
        android.util.Log.i("SocketManager", "Emitting join_session for session $sessionId, connected=${socket?.connected()}")
        socket?.emit("join_session", JSONObject().put("sessionId", sessionId))
    }

    val isConnected: Boolean
        get() = socket?.connected() == true

    fun sendLocationUpdate(
        latitude: Double,
        longitude: Double,
        accuracy: Float? = null,
        speed: Float? = null,
        heading: Float? = null,
        altitude: Double? = null,
        batteryLevel: Int? = null,
        recordedAt: String? = null
    ) {
        val payload = JSONObject().apply {
            put("latitude", latitude)
            put("longitude", longitude)
            accuracy?.let { put("accuracy", it.toDouble()) }
            speed?.let { put("speed", it.toDouble()) }
            heading?.let { put("heading", it.toDouble()) }
            altitude?.let { put("altitude", it) }
            batteryLevel?.let { put("batteryLevel", it) }
            recordedAt?.let { put("recordedAt", it) }
        }
        socket?.emit("location_update", payload)
    }

    fun sendUnblockRequest(
        requestId: String,
        packageName: String,
        appName: String,
        reason: String
    ) {
        val payload = JSONObject().apply {
            put("requestId", requestId)
            put("packageName", packageName)
            put("appName", appName)
            put("reason", reason)
        }
        socket?.emit("unblock_request", payload)
    }

    fun sendBrowsingActivity(entry: CachedBrowsingHistory) {
        val payload = JSONObject().apply {
            put("url", entry.url)
            put("domain", entry.domain)
            put("title", entry.title)
            put("browser", entry.browser)
            put("isIncognito", entry.isIncognito)
            put("category", entry.category)
            put("isBlockedAttempt", entry.isBlockedAttempt)
            entry.blockedReason?.let { put("blockedReason", it) }
            put("visitedAt", entry.visitedAt)
        }
        socket?.emit("new_browsing_activity", payload)
    }

    fun disconnect() {
        socket?.off()
        socket?.disconnect()
        socket = null
    }
}

private fun Array<Any>.getOrNull(index: Int): Any? = if (index < size) this[index] else null

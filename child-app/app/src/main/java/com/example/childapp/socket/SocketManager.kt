package com.example.childapp.socket

import com.example.childapp.BuildConfig
import io.socket.client.IO
import io.socket.client.Socket
import org.json.JSONObject

/**
 * Wraps the Socket.IO connection to the backend. Used for:
 *  - reporting online presence (implicit on connect/disconnect)
 *  - receiving `screen_share_request` from a parent
 *  - sending accept/reject
 *  - relaying WebRTC offer/answer/ICE candidates
 */
class SocketManager(private val accessToken: String) {

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

    fun connect() {
        val options = IO.Options.builder()
            .setTransports(arrayOf("websocket"))
            .setAuth(mapOf("token" to accessToken))
            .build()

        socket = IO.socket(java.net.URI.create(BuildConfig.SOCKET_URL), options).also { s ->
            s.on(Socket.EVENT_CONNECT) { onConnected?.invoke() }
            s.on(Socket.EVENT_DISCONNECT) { onDisconnected?.invoke() }

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
                onWebrtcAnswer?.invoke(data.getString("sessionId"), data.getJSONObject("sdp"))
            }
            s.on("ice_candidate") { args ->
                val data = args.getOrNull(0) as? JSONObject ?: return@on
                onIceCandidate?.invoke(data.getString("sessionId"), data.getJSONObject("candidate"))
            }
            s.connect()
        }
    }

    fun acceptScreenShare(sessionId: String) {
        socket?.emit("screen_share_accept", JSONObject().put("sessionId", sessionId))
    }

    fun rejectScreenShare(sessionId: String) {
        socket?.emit("screen_share_reject", JSONObject().put("sessionId", sessionId))
    }

    fun acceptCameraStream(sessionId: String) {
        socket?.emit("camera_stream_accept", JSONObject().put("sessionId", sessionId))
    }

    fun rejectCameraStream(sessionId: String, reason: String? = null) {
        val payload = JSONObject().put("sessionId", sessionId)
        if (reason != null) payload.put("reason", reason)
        socket?.emit("camera_stream_reject", payload)
    }

    fun sendOffer(sessionId: String, sdp: JSONObject) {
        socket?.emit("webrtc_offer", JSONObject().put("sessionId", sessionId).put("sdp", sdp))
    }

    fun sendIceCandidate(sessionId: String, candidate: JSONObject) {
        socket?.emit("ice_candidate", JSONObject().put("sessionId", sessionId).put("candidate", candidate))
    }

    fun notifyStopped(sessionId: String) {
        socket?.emit("screen_share_stopped", JSONObject().put("sessionId", sessionId))
    }

    fun notifyCameraStopped(sessionId: String) {
        socket?.emit("camera_stream_stopped", JSONObject().put("sessionId", sessionId))
    }

    fun joinSession(sessionId: String) {
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

    fun disconnect() {
        socket?.off()
        socket?.disconnect()
        socket = null
    }
}

private fun Array<Any>.getOrNull(index: Int): Any? = if (index < size) this[index] else null

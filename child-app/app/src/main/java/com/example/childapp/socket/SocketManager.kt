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

    fun sendOffer(sessionId: String, sdp: JSONObject) {
        socket?.emit("webrtc_offer", JSONObject().put("sessionId", sessionId).put("sdp", sdp))
    }

    fun sendIceCandidate(sessionId: String, candidate: JSONObject) {
        socket?.emit("ice_candidate", JSONObject().put("sessionId", sessionId).put("candidate", candidate))
    }

    fun notifyStopped(sessionId: String) {
        socket?.emit("screen_share_stopped", JSONObject().put("sessionId", sessionId))
    }

    fun disconnect() {
        socket?.off()
        socket?.disconnect()
        socket = null
    }
}

private fun Array<Any>.getOrNull(index: Int): Any? = if (index < size) this[index] else null

package com.example.childapp.data

import com.example.childapp.BuildConfig
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.TimeUnit

class ApiException(message: String) : Exception(message)

/** Thin REST client for the backend. All calls are synchronous — call from a background thread/coroutine. */
class ApiClient(private val session: SessionStore) {

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build()

    private val jsonMedia = "application/json; charset=utf-8".toMediaType()

    private fun url(path: String) = "${BuildConfig.API_BASE_URL}$path"

    private fun authedRequest(path: String, method: String, body: JSONObject? = null): Request.Builder {
        val builder = Request.Builder().url(url(path))
        val token = session.accessToken
        if (token != null) builder.addHeader("Authorization", "Bearer $token")
        when (method) {
            "GET" -> builder.get()
            "POST" -> builder.post((body ?: JSONObject()).toString().toRequestBody(jsonMedia))
        }
        return builder
    }

    /** POST /api/auth/child-login */
    fun childLogin(username: String, password: String): JSONObject {
        val payload = JSONObject().put("email", username).put("password", password)
        val req = Request.Builder()
            .url(url("/api/auth/child-login"))
            .post(payload.toString().toRequestBody(jsonMedia))
            .build()
        val body = execute(req)
        session.accessToken = body.getString("accessToken")
        val user = body.getJSONObject("user")
        session.childName = user.getString("name")
        return body
    }

    /** POST /api/devices/register */
    fun registerDevice(deviceName: String, platform: String = "Android"): JSONObject {
        val payload = JSONObject().put("deviceName", deviceName).put("platform", platform)
        val req = authedRequest("/api/devices/register", "POST", payload).build()
        return execute(req)
    }

    /** GET /api/config -> ICE servers */
    fun getIceServers(): JSONObject {
        val req = authedRequest("/api/config", "GET").build()
        return execute(req)
    }

    /** POST /api/screen-share/{id}/stop */
    fun stopScreenShare(sessionId: String) {
        val req = authedRequest("/api/screen-share/$sessionId/stop", "POST").build()
        execute(req)
    }

    private fun execute(req: Request): JSONObject {
        client.newCall(req).execute().use { resp ->
            val text = resp.body?.string().orEmpty()
            val json = if (text.isNotBlank()) JSONObject(text) else JSONObject()
            if (!resp.isSuccessful) {
                throw ApiException(json.optString("error", "Request failed (${resp.code})"))
            }
            return json
        }
    }
}

fun interface ApiCallback<T> {
    fun onResult(result: Result<T>)
}

class NetworkException(message: String, cause: Throwable? = null) : IOException(message, cause)

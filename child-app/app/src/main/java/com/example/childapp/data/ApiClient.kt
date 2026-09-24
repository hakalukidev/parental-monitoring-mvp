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
        .hostnameVerifier { hostname, session ->
            if (hostname == "163.227.239.88" || hostname == "api.hakaluki.dev") true
            else javax.net.ssl.HttpsURLConnection.getDefaultHostnameVerifier().verify(hostname, session)
        }
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
        val body = execute(req, retryOn401 = false)
        session.accessToken = body.getString("accessToken")
        if (body.has("refreshToken")) {
            session.refreshToken = body.getString("refreshToken")
        }
        val user = body.getJSONObject("user")
        session.childName = user.getString("name")
        session.childId = user.getString("id")
        return body
    }

    /** POST /api/auth/refresh */
    @Synchronized
    fun refreshAccessToken(): Boolean {
        val refreshToken = session.refreshToken ?: return false
        try {
            val payload = JSONObject().put("refreshToken", refreshToken)
            val req = Request.Builder()
                .url(url("/api/auth/refresh"))
                .post(payload.toString().toRequestBody(jsonMedia))
                .build()

            client.newCall(req).execute().use { resp ->
                val text = resp.body?.string().orEmpty()
                if (!resp.isSuccessful) {
                    android.util.Log.e("ApiClient", "Token refresh failed (${resp.code}): $text")
                    return false
                }
                val json = JSONObject(text)
                val newAccess = json.getString("accessToken")
                session.accessToken = newAccess
                if (json.has("refreshToken")) {
                    session.refreshToken = json.getString("refreshToken")
                }
                android.util.Log.i("ApiClient", "Access token refreshed successfully")
                return true
            }
        } catch (e: Exception) {
            android.util.Log.e("ApiClient", "Error refreshing token: ${e.message}", e)
            return false
        }
    }

    /** POST /api/children/:childId/apps/sync */
    fun syncInstalledApps(apps: org.json.JSONArray): JSONObject {
        val childId = session.childId ?: return JSONObject()
        val payload = JSONObject().put("apps", apps)
        val req = authedRequest("/api/children/$childId/apps/sync", "POST", payload).build()
        return execute(req)
    }

    /** GET /api/children/my-policies */
    fun getMyPolicies(): JSONObject {
        val req = authedRequest("/api/children/my-policies", "GET").build()
        return execute(req)
    }

    /** GET /api/children/my-web-rules */
    fun getMyWebRules(): JSONObject {
        val req = authedRequest("/api/children/my-web-rules", "GET").build()
        return execute(req)
    }

    /** POST /api/children/:childId/browsing-history/batch */
    fun postBrowsingHistoryBatch(records: org.json.JSONArray): JSONObject {
        val childId = session.childId ?: return JSONObject()
        val payload = JSONObject().put("records", records)
        val req = authedRequest("/api/children/$childId/browsing-history/batch", "POST", payload).build()
        return execute(req)
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

    /** POST /api/camera-stream/{id}/stop */
    fun stopCameraStream(sessionId: String) {
        val req = authedRequest("/api/camera-stream/$sessionId/stop", "POST").build()
        execute(req)
    }

    /** POST /api/location/record */
    fun postLocation(
        latitude: Double,
        longitude: Double,
        accuracy: Float? = null,
        speed: Float? = null,
        heading: Float? = null,
        altitude: Double? = null,
        batteryLevel: Int? = null,
        recordedAt: String? = null
    ): JSONObject {
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
        val req = authedRequest("/api/location/record", "POST", payload).build()
        return execute(req)
    }

    /** POST /api/location/batch */
    fun postLocationBatch(points: org.json.JSONArray): JSONObject {
        val payload = JSONObject().put("points", points)
        val req = authedRequest("/api/location/batch", "POST", payload).build()
        return execute(req)
    }

    private fun execute(req: Request, retryOn401: Boolean = true): JSONObject {
        android.util.Log.d("ApiClient", "HTTP ${req.method} -> ${req.url}")
        try {
            client.newCall(req).execute().use { resp ->
                val text = resp.body?.string().orEmpty()
                android.util.Log.d("ApiClient", "Response (${resp.code}) for ${req.url}: $text")

                if (resp.code == 401 && retryOn401 && !req.url.encodedPath.contains("/api/auth/")) {
                    android.util.Log.w("ApiClient", "Received 401 for ${req.url}, attempting token refresh...")
                    val refreshed = refreshAccessToken()
                    if (refreshed) {
                        val newToken = session.accessToken
                        val retryReq = req.newBuilder()
                            .header("Authorization", "Bearer $newToken")
                            .build()
                        return execute(retryReq, retryOn401 = false)
                    }
                }

                val json = if (text.isNotBlank()) JSONObject(text) else JSONObject()
                if (!resp.isSuccessful) {
                    throw ApiException(json.optString("error", "Request failed (${resp.code})"))
                }
                return json
            }
        } catch (e: Exception) {
            android.util.Log.e("ApiClient", "Error during request ${req.url}: ${e.message}", e)
            throw e
        }
    }
}

fun interface ApiCallback<T> {
    fun onResult(result: Result<T>)
}

class NetworkException(message: String, cause: Throwable? = null) : IOException(message, cause)

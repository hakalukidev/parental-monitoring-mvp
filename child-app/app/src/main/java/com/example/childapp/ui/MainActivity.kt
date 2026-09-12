package com.example.childapp.ui

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.*
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import com.example.childapp.accessibility.ChildAccessibilityService
import com.example.childapp.blocker.AppScanner
import com.example.childapp.camera.CameraStreamService
import com.example.childapp.data.ApiClient
import com.example.childapp.data.ApiException
import com.example.childapp.data.LocalDatabase
import com.example.childapp.data.SessionStore
import com.example.childapp.location.LocationService
import com.example.childapp.screen.InvisibleScreenCaptureActivity
import com.example.childapp.screen.ScreenCaptureService
import com.example.childapp.socket.SocketManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : ComponentActivity() {

    private lateinit var session: SessionStore
    private lateinit var api: ApiClient
    private var socketManager: SocketManager? = null

    private val screenState = mutableStateOf<ChildScreenState>(ChildScreenState.Idle)

    private fun hasLocationPermission(): Boolean {
        return ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
                ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        android.util.Log.i("MainActivity", "Using API_BASE_URL: ${com.example.childapp.BuildConfig.API_BASE_URL}")
        android.util.Log.i("MainActivity", "Using SOCKET_URL: ${com.example.childapp.BuildConfig.SOCKET_URL}")
        session = SessionStore(applicationContext)
        api = ApiClient(session)

        setContent {
            var loggedIn by remember { mutableStateOf(session.accessToken != null) }
            var isSetupDone by remember { mutableStateOf(session.isSetupCompleted) }
            var loading by remember { mutableStateOf(false) }
            var error by remember { mutableStateOf<String?>(null) }
            var deviceConnected by remember { mutableStateOf(false) }
            val state by screenState

            MaterialTheme {
                Surface {
                    if (!loggedIn) {
                        LoginScreen(
                            loading = loading,
                            error = error,
                            onLogin = { username, password ->
                                loading = true
                                error = null
                                lifecycleScope.launch {
                                    try {
                                        withContext(Dispatchers.IO) {
                                            api.childLogin(username, password)
                                            api.registerDevice(
                                                deviceName = android.os.Build.MODEL ?: "Android Device"
                                            )
                                        }
                                        loggedIn = true
                                        isSetupDone = session.isSetupCompleted
                                        if (isSetupDone) {
                                            startMonitoringServices()
                                        }
                                        startSocket()
                                        deviceConnected = true
                                        syncAppData()
                                    } catch (e: ApiException) {
                                        android.util.Log.e("MainActivity", "Login ApiException: ${e.message}", e)
                                        error = e.message
                                    } catch (e: Exception) {
                                        android.util.Log.e("MainActivity", "Login Exception: ${e.message}", e)
                                        error = "Could not connect: ${e.message ?: "Check your network."}"
                                    } finally {
                                        loading = false
                                    }
                                }
                            }
                        )
                    } else if (!isSetupDone) {
                        // First-time onboarding: Take all permissions and authorizations once
                        PermissionsSetupScreen(
                            onSetupComplete = {
                                session.isSetupCompleted = true
                                isSetupDone = true
                                startMonitoringServices()
                                syncAppData()
                            }
                        )
                    } else {
                        HomeScreen(
                            childName = session.childName ?: "Child",
                            parentName = session.parentName,
                            deviceConnected = deviceConnected,
                            state = state,
                            onLogout = {
                                if (state is ChildScreenState.Active) {
                                    ScreenCaptureService.stop(this@MainActivity)
                                } else if (state is ChildScreenState.CameraActive) {
                                    CameraStreamService.stop(this@MainActivity)
                                }
                                LocationService.stop(this@MainActivity)
                                com.example.childapp.service.ChildMonitoringService.stop(this@MainActivity)
                                screenState.value = ChildScreenState.Idle
                                socketManager?.disconnect()
                                socketManager = null
                                BlockedAppActivity.activeSocketManager = null
                                ChildAccessibilityService.activeSocketCallback = null
                                session.clear()
                                loggedIn = false
                                isSetupDone = false
                                deviceConnected = false
                                error = null
                            }
                        )
                    }
                }
            }
        }

        if (session.accessToken != null) {
            startSocket()
            if (session.isSetupCompleted) {
                startMonitoringServices()
            }
            syncAppData()
        }
    }

    private fun startMonitoringServices() {
        val tok = session.accessToken ?: return
        com.example.childapp.service.ChildMonitoringService.start(this)
        if (hasLocationPermission()) {
            LocationService.start(this, tok)
        }
    }

    private fun syncAppData() {
        lifecycleScope.launch(Dispatchers.IO) {
            try {
                // 1. Scan and sync installed apps
                val apps = AppScanner.scanInstalledApps(this@MainActivity)
                api.syncInstalledApps(AppScanner.toJsonArray(apps))

                // 2. Fetch and save active policies
                val polResp = api.getMyPolicies()
                if (polResp.has("policies")) {
                    LocalDatabase.getInstance(this@MainActivity)
                        .saveAppPolicies(polResp.getJSONArray("policies"))
                }
                if (polResp.has("isPaused")) {
                    LocalDatabase.getInstance(this@MainActivity)
                        .setDevicePaused(polResp.getBoolean("isPaused"))
                }

                // 3. Fetch and save active web rules
                val webResp = api.getMyWebRules()
                if (webResp.has("rules")) {
                    LocalDatabase.getInstance(this@MainActivity)
                        .saveWebRules(webResp.getJSONArray("rules"))
                }

                // 4. Batch flush any unsynced offline browsing records
                val unsynced = LocalDatabase.getInstance(this@MainActivity).getUnsyncedBrowsingHistory()
                if (unsynced.isNotEmpty()) {
                    val batchArray = JSONArray()
                    for (entry in unsynced) {
                        batchArray.put(JSONObject().apply {
                            put("url", entry.url)
                            put("domain", entry.domain)
                            put("title", entry.title)
                            put("browser", entry.browser)
                            put("isIncognito", entry.isIncognito)
                            put("category", entry.category)
                            put("isBlockedAttempt", entry.isBlockedAttempt)
                            entry.blockedReason?.let { put("blockedReason", it) }
                            put("visitedAt", entry.visitedAt)
                        })
                    }
                    api.postBrowsingHistoryBatch(batchArray)
                    LocalDatabase.getInstance(this@MainActivity)
                        .markBrowsingHistorySynced(unsynced.map { it.id })
                }
            } catch (e: Exception) {
                android.util.Log.e("MainActivity", "Error syncing app data: ${e.message}", e)
            }
        }
    }

    private fun startSocket() {
        val token = session.accessToken ?: return
        val socket = SocketManager(token)
        BlockedAppActivity.activeSocketManager = socket
        ChildAccessibilityService.activeSocketCallback = { entry ->
            socket.sendBrowsingActivity(entry)
        }

        socket.onConnected = {
            syncAppData()
        }

        socket.onPolicyUpdated = { data ->
            val type = data.optString("type")
            val db = LocalDatabase.getInstance(this)
            if (type == "APP_POLICY") {
                val policy = data.optJSONObject("policy")
                if (policy != null) db.upsertAppPolicy(policy)
            } else if (type == "WEB_RULE_ADDED" || type == "WEB_RULE_UPDATED") {
                val rule = data.optJSONObject("rule")
                if (rule != null) db.upsertWebRule(rule)
            } else if (type == "WEB_RULE_DELETED") {
                val ruleId = data.optString("ruleId")
                if (ruleId.isNotBlank()) db.deleteWebRule(ruleId)
            } else if (type == "BULK_UPDATE") {
                syncAppData()
            }
        }

        socket.onInstantLockdownToggle = { isPaused ->
            LocalDatabase.getInstance(this).setDevicePaused(isPaused)
        }

        socket.onScreenShareRequest = { sessionId, _ ->
            socket.acceptScreenShare(sessionId)
            if (ScreenCaptureService.isSessionRunning.get()) {
                android.util.Log.i("MainActivity", "Screen share session is already active, skipping duplicate")
            } else {
                val cachedIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    null
                } else {
                    ScreenCaptureService.pendingProjectionIntent
                }
                if (cachedIntent != null) {
                    try {
                        ScreenCaptureService.start(this, RESULT_OK, cachedIntent, token, sessionId)
                        runOnUiThread { screenState.value = ChildScreenState.Active(sessionId) }
                    } catch (e: Exception) {
                        ChildAccessibilityService.instance?.pollForMediaProjectionDialog()
                        InvisibleScreenCaptureActivity.launch(this, token, sessionId)
                        runOnUiThread { screenState.value = ChildScreenState.Active(sessionId) }
                    }
                } else {
                    ChildAccessibilityService.instance?.pollForMediaProjectionDialog()
                    InvisibleScreenCaptureActivity.launch(this, token, sessionId)
                    runOnUiThread { screenState.value = ChildScreenState.Active(sessionId) }
                }
            }
        }
        socket.onScreenShareStopped = { sessionId ->
            runOnUiThread {
                if (screenState.value is ChildScreenState.Active) {
                    ScreenCaptureService.stop(this)
                }
                screenState.value = ChildScreenState.Idle
            }
        }
        socket.onCameraStreamRequest = { sessionId, parentId, cameraFacing, withAudio ->
            runOnUiThread {
                val hasCamera = ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
                if (hasCamera) {
                    CameraStreamService.start(this, token, sessionId, cameraFacing, withAudio)
                    screenState.value = ChildScreenState.CameraActive(sessionId, cameraFacing)
                } else {
                    socketManager?.rejectCameraStream(sessionId, "permission_denied")
                }
            }
        }
        socket.onCameraStreamStopped = { sessionId ->
            runOnUiThread {
                if (screenState.value is ChildScreenState.CameraActive) {
                    CameraStreamService.stop(this)
                }
                screenState.value = ChildScreenState.Idle
            }
        }
        socket.connect()
        socketManager = socket
    }

    override fun onDestroy() {
        socketManager?.disconnect()
        super.onDestroy()
    }
}

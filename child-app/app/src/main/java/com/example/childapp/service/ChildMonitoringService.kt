package com.example.childapp.service

import android.app.*
import android.content.Context
import android.content.Intent
import android.location.LocationManager
import android.os.BatteryManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.example.childapp.accessibility.ChildAccessibilityService
import com.example.childapp.blocker.AppScanner
import com.example.childapp.blocker.AppUsageTracker
import com.example.childapp.camera.CameraStreamService
import com.example.childapp.data.ApiClient
import com.example.childapp.data.LocalDatabase
import com.example.childapp.data.SessionStore
import com.example.childapp.consent.SessionConsentController
import com.example.childapp.consent.MediaRequest
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import com.example.childapp.screen.ScreenCaptureService
import com.example.childapp.socket.SocketManager
import com.example.childapp.ui.BlockedAppActivity
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject

/** Visible monitoring service; all sensitive media sessions require a new on-device approval. */
class ChildMonitoringService : Service() {

    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var socketManager: SocketManager? = null
    private var heartbeatJob: Job? = null
    private lateinit var session: SessionStore
    private lateinit var api: ApiClient
    private var inventoryFingerprint: String? = null
    private var lastInventoryAt = 0L

    override fun onCreate() {
        super.onCreate()
        session = SessionStore(applicationContext)
        api = ApiClient(session)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_STOP) {
            stopMonitoring()
            return START_NOT_STICKY
        }

        val token = session.accessToken
        if (token == null) {
            stopSelf()
            return START_NOT_STICKY
        }

        startInForeground()
        initSocket(token)

        return START_STICKY
    }

    private fun startInForeground() {
        val channelId = "child_monitoring_channel"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Seftly family connection",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Monitors device security and synchronization."
                setShowBadge(false)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("Seftly Child is running")
            .setContentText("Family rules and activity synchronization are active")
            .setSmallIcon(com.example.childapp.R.drawable.ic_seftly_notification)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()

        startForeground(NOTIFICATION_ID, notification)
    }

    private fun initSocket(token: String) {
        if (socketManager != null) return

        val socket = SocketManager(token)
        socketManager = socket
        activeSocket = socket
        BlockedAppActivity.activeSocketManager = socket
        ChildAccessibilityService.activeSocketCallback = null // REST batch ingestion is authoritative.

        socket.onConnected = {
            connectionState.value = true;
            Log.i(TAG, "Persistent socket connected successfully")
            syncAppData()
            startHeartbeat()
        }

        socket.onDisconnected = {
            connectionState.value = false;
            ScreenCaptureService.stop(this)
            CameraStreamService.stop(this)
            SessionConsentController.clearAll(this)
            Log.w(TAG, "Socket disconnected, pausing heartbeat")
            heartbeatJob?.cancel()
        }

        socket.onAuthError = {
            Log.w(TAG, "Socket auth error detected, refreshing access token...")
            heartbeatJob?.cancel()
            serviceScope.launch {
                val ok = api.refreshAccessToken()
                if (ok) {
                    val freshToken = session.accessToken
                    if (freshToken != null) {
                        socket.updateTokenAndReconnect(freshToken)
                    }
                }
            }
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

        socket.onGeofenceUpdated = { action, geofenceId, geofence ->
            val db = LocalDatabase.getInstance(this)
            if (action == "DELETE") {
                db.deleteGeofence(geofenceId)
            } else if (geofence != null) {
                db.upsertGeofence(geofence)
            }
        }

        socket.onUnblockResponse = { _, packageName, approved, minutes ->
            if (approved && packageName.isNotBlank() && minutes in 1..120) LocalDatabase.getInstance(this).grantTemporaryUnblock(packageName, minutes)
        }
        socket.onRequestUsageSync = {
            Log.i(TAG, "Parent requested immediate usage & downtime refresh over socket")
            serviceScope.launch {
                try {
                    val report = AppUsageTracker.generateTodayUsageReport(this@ChildMonitoringService)
                    api.syncDailyUsage(report)
                    socketManager?.sendUsageUpdated(report)
                    Log.i(TAG, "Sent updated usage report successfully")
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to respond to request_usage_sync: ${e.message}")
                }
            }
        }

        socket.onScreenShareRequest = { sessionId, _ ->
            SessionConsentController.request(this, MediaRequest(sessionId, "screen"))
        }
        socket.onScreenShareStopped = { sessionId ->
            SessionConsentController.clear(this, sessionId)
            if (ScreenCaptureService.currentSessionId == sessionId) ScreenCaptureService.stop(this)
        }
        socket.onCameraStreamRequest = { sessionId, _, facing, audio ->
            SessionConsentController.request(this, MediaRequest(sessionId, "camera", facing, audio))
        }
        socket.onCameraStreamStopped = { sessionId ->
            SessionConsentController.clear(this, sessionId)
            if (CameraStreamService.currentSessionId == sessionId) CameraStreamService.stop(this)
        }

        socket.connect()
        socketManager = socket
    }

    private fun syncAppData() {
        serviceScope.launch {
            try {
                val apps = AppScanner.scanInstalledApps(this@ChildMonitoringService)
                val fingerprint = apps.joinToString { "${it.packageName}:${it.versionName}:${it.appName}:${it.category}" }
                if (fingerprint != inventoryFingerprint || System.currentTimeMillis() - lastInventoryAt > 6 * 60 * 60_000L) {
                    for (batch in apps.chunked(25)) api.syncInstalledApps(AppScanner.toJsonArray(batch, this@ChildMonitoringService))
                    currentCoroutineContext().ensureActive()
                    inventoryFingerprint = fingerprint; lastInventoryAt = System.currentTimeMillis()
                }

                val polResp = api.getMyPolicies()
                currentCoroutineContext().ensureActive()
                if (polResp.has("policies")) {
                    LocalDatabase.getInstance(this@ChildMonitoringService)
                        .saveAppPolicies(polResp.getJSONArray("policies"))
                }
                if (polResp.has("isPaused")) {
                    LocalDatabase.getInstance(this@ChildMonitoringService)
                        .setDevicePaused(polResp.getBoolean("isPaused"))
                }

                val webResp = api.getMyWebRules()
                currentCoroutineContext().ensureActive()
                if (webResp.has("rules")) {
                    LocalDatabase.getInstance(this@ChildMonitoringService)
                        .saveWebRules(webResp.getJSONArray("rules"))
                }

                val geoResp = api.getMyGeofences()
                currentCoroutineContext().ensureActive()
                if (geoResp.has("geofences")) {
                    LocalDatabase.getInstance(this@ChildMonitoringService)
                        .saveGeofences(geoResp.getJSONArray("geofences"))
                }

                val unsynced = LocalDatabase.getInstance(this@ChildMonitoringService).getUnsyncedBrowsingHistory()
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
                            put("visitedAt", java.time.Instant.ofEpochMilli(entry.visitedAt).toString())
                        })
                    }
                    api.postBrowsingHistoryBatch(batchArray)
                    LocalDatabase.getInstance(this@ChildMonitoringService)
                        .markBrowsingHistorySynced(unsynced.map { it.id })
                }

                // Sync today's app usages and downtime report
                try {
                    val usageReport = AppUsageTracker.generateTodayUsageReport(this@ChildMonitoringService)
                    api.syncDailyUsage(usageReport)
                    socketManager?.sendUsageUpdated(usageReport)
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to sync daily usage: ${e.message}")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error syncing app data", e)
            }
        }
    }

    private fun startHeartbeat() {
        heartbeatJob?.cancel()
        heartbeatJob = serviceScope.launch {
            var heartbeatCounter = 0
            while (isActive) {
                try {
                    val batteryManager = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
                    val batteryLevel = batteryManager?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)?.takeIf { it in 0..100 }
                    val locationManager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
                    val isGpsOn = locationManager?.isProviderEnabled(LocationManager.GPS_PROVIDER)
                    val deviceName = "${Build.MANUFACTURER} ${Build.MODEL}"
                    socketManager?.sendHeartbeat(batteryLevel, isGpsOn, deviceName)

                    val db = LocalDatabase.getInstance(this@ChildMonitoringService)
                    val pending = db.pendingLocations()
                    if (pending.isNotEmpty()) {
                        api.postLocationBatch(JSONArray().apply { pending.forEach { put(it.second) } })
                        currentCoroutineContext().ensureActive()
                        db.markLocationsSynced(pending.map { it.first })
                    }
                    heartbeatCounter++
                    if (heartbeatCounter % 3 == 0) {
                        syncAppData()
                        try {
                            val report = AppUsageTracker.generateTodayUsageReport(this@ChildMonitoringService)
                            api.syncDailyUsage(report)
                            socketManager?.sendUsageUpdated(report)
                        } catch (_: Exception) {}
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Heartbeat emission error: ${e.message}")
                }
                delay(25000)
            }
        }
    }

    private fun stopMonitoring() {
        connectionState.value = false
        activeSocket = null
        heartbeatJob?.cancel()
        socketManager?.disconnect()
        socketManager = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        connectionState.value = false
        SessionConsentController.clearAll(this)
        activeSocket = null
        heartbeatJob?.cancel()
        socketManager?.disconnect()
        serviceScope.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private val connectionState = MutableStateFlow(false)
        val connected = connectionState.asStateFlow()
        private const val TAG = "ChildMonitoringService"
        const val NOTIFICATION_ID = 1001
        const val ACTION_STOP = "com.example.childapp.action.STOP_MONITORING"
        var activeSocket: SocketManager? = null
            private set

        fun start(context: Context) {
            val intent = Intent(context, ChildMonitoringService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, ChildMonitoringService::class.java))
        }
    }
}

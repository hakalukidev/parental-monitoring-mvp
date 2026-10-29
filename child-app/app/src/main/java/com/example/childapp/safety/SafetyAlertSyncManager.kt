package com.example.childapp.safety

import android.accessibilityservice.AccessibilityService
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.util.Log
import com.example.childapp.accessibility.ChildAccessibilityService
import com.example.childapp.data.ApiClient
import com.example.childapp.data.CachedSafetyAlert
import com.example.childapp.data.LocalDatabase
import com.example.childapp.data.SessionStore
import com.example.childapp.service.ChildMonitoringService
import com.example.childapp.ui.BlockedAppActivity
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

object SafetyAlertSyncManager {
    private const val TAG = "SafetyAlertSyncManager"

    private val isSyncing = AtomicBoolean(false)
    private val executor = Executors.newSingleThreadExecutor()

    fun recordAlert(
        context: Context,
        alertType: String,
        packageName: String?,
        appName: String?,
        confidence: Double,
        severity: String
    ) {
        val timestamp = System.currentTimeMillis()
        val externalId = generateHash("${alertType}_${packageName.orEmpty()}_${timestamp / 10000}")

        val alert = CachedSafetyAlert(
            externalId = externalId,
            alertType = alertType,
            packageName = packageName,
            appName = appName,
            confidence = confidence,
            severity = severity,
            timestamp = timestamp,
            isSynced = false
        )

        val db = LocalDatabase.getInstance(context)
        val rowId = db.insertSafetyAlert(alert)
        Log.w(TAG, "Recorded safety violation alert (ID: $rowId, type: $alertType, app: $appName, confidence: $confidence)")

        // 1. Enforce immediate local block and close the offending app
        val isSystemPkg = packageName.isNullOrEmpty() ||
                packageName == context.packageName ||
                packageName == "android" ||
                packageName == "com.android.systemui" ||
                packageName == "com.android.providers.media" ||
                packageName == "com.android.settings" ||
                packageName.contains("launcher")

        if (!isSystemPkg && packageName != null) {
            val resolvedAppName = appName ?: packageName
            db.blockAppForSafety(packageName, resolvedAppName)
            enforceImmediateAppCloseAndBlock(context, packageName, resolvedAppName, alertType)
        }

        // 2. Trigger immediate background sync
        triggerSyncAsync(context)
    }

    private fun enforceImmediateAppCloseAndBlock(
        context: Context,
        packageName: String,
        appName: String,
        alertType: String
    ) {
        try {
            // A. Trigger HOME action via accessibility service if bound
            ChildAccessibilityService.instance?.performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME)

            // B. Kill background process of target app
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            am?.killBackgroundProcesses(packageName)

            // C. Launch BlockedAppActivity showing safety block details
            val intent = Intent(context, BlockedAppActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("PACKAGE_NAME", packageName)
                putExtra("APP_NAME", appName)
                putExtra("REASON", "Inappropriate content detected. This app has been automatically blocked for your safety.")
                putExtra("BLOCKED_TARGET", "Safety & Content Filter")
                putExtra("IS_WEB_BLOCK", false)
            }
            context.startActivity(intent)
            Log.i(TAG, "Enforced immediate safety close and block on $appName ($packageName)")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to enforce immediate safety close and block: ${e.message}", e)
        }
    }

    fun triggerSyncAsync(context: Context) {
        executor.execute {
            try {
                sync(context)
            } catch (e: Exception) {
                Log.e(TAG, "Error in async safety alert sync: ${e.message}", e)
            }
        }
    }

    @Synchronized
    fun sync(context: Context) {
        if (!isSyncing.compareAndSet(false, true)) {
            return
        }

        try {
            val session = SessionStore(context)
            if (session.accessToken.isNullOrEmpty() || session.childId.isNullOrEmpty()) {
                return
            }

            val db = LocalDatabase.getInstance(context)
            val unsynced = db.getUnsyncedSafetyAlerts(50)
            if (unsynced.isEmpty()) {
                return
            }

            val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }

            val alertsArray = JSONArray()
            for (a in unsynced) {
                alertsArray.put(
                    JSONObject().apply {
                        put("externalId", a.externalId)
                        put("alertType", a.alertType)
                        put("packageName", a.packageName)
                        put("appName", a.appName)
                        put("confidenceScore", a.confidence)
                        put("severity", a.severity)
                        put("timestamp", isoFormat.format(Date(a.timestamp)))
                    }
                )
            }

            val api = ApiClient(session)
            val res = api.syncSafetyAlertsBatch(alertsArray)
            if (res.optBoolean("success", false) || res.has("processedCount")) {
                db.markSafetyAlertsSynced(unsynced.map { it.id })
                Log.i(TAG, "Successfully synced ${unsynced.size} safety alerts to backend")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed syncing safety alerts: ${e.message}")
        } finally {
            isSyncing.set(false)
        }
    }

    private fun generateHash(input: String): String {
        val bytes = MessageDigest.getInstance("SHA-256").digest(input.toByteArray(Charsets.UTF_8))
        return bytes.joinToString("") { "%02x".format(it) }
    }
}

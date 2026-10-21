package com.example.childapp.safety

import android.content.Context
import android.util.Log
import com.example.childapp.data.ApiClient
import com.example.childapp.data.CachedSafetyAlert
import com.example.childapp.data.LocalDatabase
import com.example.childapp.data.SessionStore
import com.example.childapp.service.ChildMonitoringService
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

        // Trigger immediate background sync
        triggerSyncAsync(context)
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

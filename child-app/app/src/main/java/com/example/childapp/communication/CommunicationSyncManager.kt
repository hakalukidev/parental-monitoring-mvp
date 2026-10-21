package com.example.childapp.communication

import android.content.Context
import android.util.Log
import com.example.childapp.data.ApiClient
import com.example.childapp.data.LocalDatabase
import com.example.childapp.data.SessionStore
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

object CommunicationSyncManager {
    private const val TAG = "CommSyncManager"
    private const val PREFS_NAME = "communication_sync_prefs"
    private const val KEY_LAST_CALL_TS = "last_call_sync_timestamp"
    private const val KEY_LAST_SMS_TS = "last_sms_sync_timestamp"

    private val isSyncing = AtomicBoolean(false)
    private val executor = Executors.newSingleThreadExecutor()

    fun triggerSyncAsync(context: Context) {
        executor.execute {
            try {
                sync(context)
            } catch (e: Exception) {
                Log.e(TAG, "Error in async communication sync: ${e.message}", e)
            }
        }
    }

    @Synchronized
    fun sync(context: Context) {
        if (!isSyncing.compareAndSet(false, true)) {
            Log.d(TAG, "Sync already in progress, skipping")
            return
        }

        try {
            val session = SessionStore(context)
            if (session.accessToken.isNullOrEmpty() || session.childId.isNullOrEmpty()) {
                Log.d(TAG, "No active child session, skipping sync")
                return
            }

            val api = ApiClient(session)
            val db = LocalDatabase.getInstance(context)
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

            // 1. Evaluate & Report capabilities
            val caps = CommunicationCapabilityEvaluator.evaluate(context)
            try {
                val capPayload = JSONObject().apply {
                    put("callsStatus", caps.callsStatus.name)
                    put("smsMetadataStatus", caps.smsMetadataStatus.name)
                    put("smsContentStatus", caps.smsContentStatus.name)
                }
                api.reportCommunicationCapabilities(capPayload)
            } catch (e: Exception) {
                Log.w(TAG, "Failed reporting capabilities: ${e.message}")
            }

            // Window: default to last 7 days for initial sync
            val defaultWindow = System.currentTimeMillis() - (7L * 24 * 60 * 60 * 1000L)
            var lastCallTs = prefs.getLong(KEY_LAST_CALL_TS, defaultWindow)
            var lastSmsTs = prefs.getLong(KEY_LAST_SMS_TS, defaultWindow)

            val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }

            // 2. Sync Calls if permitted
            if (caps.callsStatus == CapabilityStatus.AVAILABLE) {
                val newCalls = CallLogProvider.getCallsAfter(context, lastCallTs)
                var maxCallTs = lastCallTs
                for (call in newCalls) {
                    db.insertCallRecord(call)
                    if (call.timestamp > maxCallTs) {
                        maxCallTs = call.timestamp
                    }
                }
                if (maxCallTs > lastCallTs) {
                    prefs.edit().putLong(KEY_LAST_CALL_TS, maxCallTs).apply()
                }

                // Upload unsynced calls in batches
                val unsyncedCalls = db.getUnsyncedCallRecords(100)
                if (unsyncedCalls.isNotEmpty()) {
                    val callsArray = JSONArray()
                    for (c in unsyncedCalls) {
                        callsArray.put(
                            JSONObject().apply {
                                put("externalId", c.externalId)
                                put("phoneNumber", c.phoneNumber)
                                put("contactName", c.contactName)
                                put("direction", c.direction)
                                put("durationSeconds", c.durationSeconds)
                                put("timestamp", isoFormat.format(Date(c.timestamp)))
                            }
                        )
                    }
                    try {
                        val res = api.syncCallsBatch(callsArray)
                        if (res.optBoolean("success", false) || res.has("processedCount")) {
                            db.markCallRecordsSynced(unsyncedCalls.map { it.id })
                            Log.i(TAG, "Successfully synced ${unsyncedCalls.size} call records")
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed syncing calls batch: ${e.message}")
                    }
                }
            }

            // 3. Sync SMS if permitted
            if (caps.smsMetadataStatus == CapabilityStatus.AVAILABLE) {
                val newSms = SmsProvider.getSmsAfter(context, lastSmsTs)
                var maxSmsTs = lastSmsTs
                for (sms in newSms) {
                    db.insertSmsRecord(sms)
                    if (sms.timestamp > maxSmsTs) {
                        maxSmsTs = sms.timestamp
                    }
                }
                if (maxSmsTs > lastSmsTs) {
                    prefs.edit().putLong(KEY_LAST_SMS_TS, maxSmsTs).apply()
                }

                // Upload unsynced SMS in batches
                val unsyncedSms = db.getUnsyncedSmsRecords(100)
                if (unsyncedSms.isNotEmpty()) {
                    val smsArray = JSONArray()
                    for (s in unsyncedSms) {
                        smsArray.put(
                            JSONObject().apply {
                                put("externalId", s.externalId)
                                put("phoneNumber", s.phoneNumber)
                                put("contactName", s.contactName)
                                put("direction", s.direction)
                                put("body", s.body)
                                put("hasBody", s.hasBody)
                                put("timestamp", isoFormat.format(Date(s.timestamp)))
                            }
                        )
                    }
                    try {
                        val res = api.syncSmsBatch(smsArray)
                        if (res.optBoolean("success", false) || res.has("processedCount")) {
                            db.markSmsRecordsSynced(unsyncedSms.map { it.id })
                            Log.i(TAG, "Successfully synced ${unsyncedSms.size} SMS records")
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed syncing SMS batch: ${e.message}")
                    }
                }
            }
        } finally {
            isSyncing.set(false)
        }
    }
}

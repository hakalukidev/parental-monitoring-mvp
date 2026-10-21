package com.example.childapp.communication

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.provider.CallLog
import android.util.Log
import androidx.core.content.ContextCompat
import com.example.childapp.data.CachedCallRecord
import java.security.MessageDigest

object CallLogProvider {
    private const val TAG = "CallLogProvider"

    fun getCallsAfter(context: Context, afterTimestamp: Long, limit: Int = 100): List<CachedCallRecord> {
        val granted = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.READ_CALL_LOG
        ) == PackageManager.PERMISSION_GRANTED

        if (!granted) {
            Log.d(TAG, "READ_CALL_LOG permission not granted")
            return emptyList()
        }

        val records = mutableListOf<CachedCallRecord>()

        val projection = arrayOf(
            CallLog.Calls._ID,
            CallLog.Calls.NUMBER,
            CallLog.Calls.CACHED_NAME,
            CallLog.Calls.TYPE,
            CallLog.Calls.DATE,
            CallLog.Calls.DURATION
        )

        val selection = "${CallLog.Calls.DATE} > ?"
        val selectionArgs = arrayOf(afterTimestamp.toString())
        val sortOrder = "${CallLog.Calls.DATE} ASC"

        try {
            context.contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                projection,
                selection,
                selectionArgs,
                sortOrder
            )?.use { cursor ->
                val numIdx = cursor.getColumnIndex(CallLog.Calls.NUMBER)
                val nameIdx = cursor.getColumnIndex(CallLog.Calls.CACHED_NAME)
                val typeIdx = cursor.getColumnIndex(CallLog.Calls.TYPE)
                val dateIdx = cursor.getColumnIndex(CallLog.Calls.DATE)
                val durIdx = cursor.getColumnIndex(CallLog.Calls.DURATION)

                while (cursor.moveToNext() && records.size < limit) {
                    val rawNumber = if (numIdx >= 0) cursor.getString(numIdx) else null
                    val contactName = if (nameIdx >= 0) cursor.getString(nameIdx) else null
                    val rawType = if (typeIdx >= 0) cursor.getInt(typeIdx) else -1
                    val date = if (dateIdx >= 0) cursor.getLong(dateIdx) else 0L
                    val duration = if (durIdx >= 0) cursor.getInt(durIdx) else 0

                    val direction = when (rawType) {
                        CallLog.Calls.INCOMING_TYPE -> "INCOMING"
                        CallLog.Calls.OUTGOING_TYPE -> "OUTGOING"
                        CallLog.Calls.MISSED_TYPE -> "MISSED"
                        CallLog.Calls.REJECTED_TYPE -> "REJECTED"
                        else -> "UNKNOWN"
                    }

                    val sanitizedNumber = if (!rawNumber.isNullOrBlank() && rawNumber != "-1" && rawNumber != "-2") {
                        rawNumber.trim()
                    } else {
                        null
                    }

                    val externalId = generateHash("${date}_${sanitizedNumber.orEmpty()}_$rawType")

                    records.add(
                        CachedCallRecord(
                            externalId = externalId,
                            phoneNumber = sanitizedNumber,
                            contactName = contactName?.trim()?.ifBlank { null },
                            direction = direction,
                            durationSeconds = duration,
                            timestamp = date,
                            isSynced = false
                        )
                    )
                }
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "SecurityException reading CallLog: ${e.message}")
        } catch (e: Exception) {
            Log.e(TAG, "Error querying CallLog: ${e.message}", e)
        }

        return records
    }

    private fun generateHash(input: String): String {
        val bytes = MessageDigest.getInstance("SHA-256").digest(input.toByteArray(Charsets.UTF_8))
        return bytes.joinToString("") { "%02x".format(it) }
    }
}

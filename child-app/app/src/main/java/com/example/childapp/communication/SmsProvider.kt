package com.example.childapp.communication

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.ContactsContract
import android.provider.Telephony
import android.util.Log
import androidx.core.content.ContextCompat
import com.example.childapp.data.CachedSmsRecord
import java.security.MessageDigest

object SmsProvider {
    private const val TAG = "SmsProvider"

    fun getSmsAfter(context: Context, afterTimestamp: Long, limit: Int = 100): List<CachedSmsRecord> {
        val granted = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.READ_SMS
        ) == PackageManager.PERMISSION_GRANTED

        if (!granted) {
            Log.d(TAG, "READ_SMS permission not granted")
            return emptyList()
        }

        val records = mutableListOf<CachedSmsRecord>()

        val projection = arrayOf(
            Telephony.Sms._ID,
            Telephony.Sms.ADDRESS,
            Telephony.Sms.BODY,
            Telephony.Sms.DATE,
            Telephony.Sms.TYPE
        )

        val selection = "${Telephony.Sms.DATE} > ?"
        val selectionArgs = arrayOf(afterTimestamp.toString())
        val sortOrder = "${Telephony.Sms.DATE} ASC LIMIT $limit"

        try {
            context.contentResolver.query(
                Telephony.Sms.CONTENT_URI,
                projection,
                selection,
                selectionArgs,
                sortOrder
            )?.use { cursor ->
                val addrIdx = cursor.getColumnIndex(Telephony.Sms.ADDRESS)
                val bodyIdx = cursor.getColumnIndex(Telephony.Sms.BODY)
                val dateIdx = cursor.getColumnIndex(Telephony.Sms.DATE)
                val typeIdx = cursor.getColumnIndex(Telephony.Sms.TYPE)

                while (cursor.moveToNext()) {
                    val rawAddress = if (addrIdx >= 0) cursor.getString(addrIdx) else null
                    val body = if (bodyIdx >= 0) cursor.getString(bodyIdx) else null
                    val date = if (dateIdx >= 0) cursor.getLong(dateIdx) else 0L
                    val rawType = if (typeIdx >= 0) cursor.getInt(typeIdx) else -1

                    val direction = when (rawType) {
                        Telephony.Sms.MESSAGE_TYPE_INBOX -> "INCOMING"
                        Telephony.Sms.MESSAGE_TYPE_SENT -> "OUTGOING"
                        else -> "UNKNOWN"
                    }

                    val sanitizedAddress = rawAddress?.trim()?.ifBlank { null }
                    val contactName = sanitizedAddress?.let { resolveContactName(context, it) }

                    val externalId = generateHash("${date}_${sanitizedAddress.orEmpty()}_$rawType")

                    records.add(
                        CachedSmsRecord(
                            externalId = externalId,
                            phoneNumber = sanitizedAddress,
                            contactName = contactName,
                            direction = direction,
                            body = body,
                            hasBody = !body.isNullOrEmpty(),
                            timestamp = date,
                            isSynced = false
                        )
                    )
                }
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "SecurityException reading SMS: ${e.message}")
        } catch (e: Exception) {
            Log.e(TAG, "Error querying SMS: ${e.message}", e)
        }

        return records
    }

    private fun resolveContactName(context: Context, phoneNumber: String): String? {
        val hasContactPermission = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.READ_CONTACTS
        ) == PackageManager.PERMISSION_GRANTED

        if (!hasContactPermission) return null

        try {
            val uri = Uri.withAppendedPath(
                ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
                Uri.encode(phoneNumber)
            )
            context.contentResolver.query(
                uri,
                arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME),
                null,
                null,
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIdx = cursor.getColumnIndex(ContactsContract.PhoneLookup.DISPLAY_NAME)
                    if (nameIdx >= 0) {
                        return cursor.getString(nameIdx)
                    }
                }
            }
        } catch (e: Exception) {
            Log.d(TAG, "Failed resolving contact name for $phoneNumber: ${e.message}")
        }
        return null
    }

    private fun generateHash(input: String): String {
        val bytes = MessageDigest.getInstance("SHA-256").digest(input.toByteArray(Charsets.UTF_8))
        return bytes.joinToString("") { "%02x".format(it) }
    }
}

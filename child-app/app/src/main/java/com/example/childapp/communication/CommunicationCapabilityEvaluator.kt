package com.example.childapp.communication

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat

enum class CapabilityStatus {
    AVAILABLE,
    PERMISSION_REQUIRED,
    PERMISSION_DENIED,
    RESTRICTED_BY_OS,
    DISABLED,
    UNSUPPORTED
}

data class CommunicationCapabilityState(
    val callsStatus: CapabilityStatus,
    val smsMetadataStatus: CapabilityStatus,
    val smsContentStatus: CapabilityStatus
)

object CommunicationCapabilityEvaluator {

    fun evaluate(context: Context): CommunicationCapabilityState {
        val pm = context.packageManager
        val hasTelephony = pm.hasSystemFeature(PackageManager.FEATURE_TELEPHONY)

        // Evaluate Call Log capability
        val callsStatus = if (!hasTelephony) {
            CapabilityStatus.UNSUPPORTED
        } else {
            val callLogGranted = ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.READ_CALL_LOG
            ) == PackageManager.PERMISSION_GRANTED

            if (callLogGranted) {
                CapabilityStatus.AVAILABLE
            } else {
                CapabilityStatus.PERMISSION_REQUIRED
            }
        }

        // Evaluate SMS capability
        val smsMetadataStatus = if (!hasTelephony) {
            CapabilityStatus.UNSUPPORTED
        } else {
            val smsGranted = ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.READ_SMS
            ) == PackageManager.PERMISSION_GRANTED

            if (smsGranted) {
                CapabilityStatus.AVAILABLE
            } else {
                CapabilityStatus.PERMISSION_REQUIRED
            }
        }

        // SMS content capability
        val smsContentStatus = if (smsMetadataStatus == CapabilityStatus.AVAILABLE) {
            CapabilityStatus.AVAILABLE
        } else {
            smsMetadataStatus
        }

        return CommunicationCapabilityState(
            callsStatus = callsStatus,
            smsMetadataStatus = smsMetadataStatus,
            smsContentStatus = smsContentStatus
        )
    }
}

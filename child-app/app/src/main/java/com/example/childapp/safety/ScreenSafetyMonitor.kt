package com.example.childapp.safety

import android.content.Context
import android.graphics.Bitmap
import android.util.Log

class ScreenSafetyMonitor(private val context: Context) {

    companion object {
        private const val TAG = "ScreenSafetyMonitor"
        private const val DEBOUNCE_REQUIRED_CONSECUTIVE = 2
    }

    private val classifier by lazy { NsfwClassifier(context) }
    private var consecutiveExplicitCount = 0
    private var lastAlertTimestamp = 0L

    /**
     * Inspects a live sampled screen frame.
     * Uses a 2-consecutive-frame debouncer to prevent false positives.
     */
    fun evaluateFrame(
        bitmap: Bitmap,
        packageName: String?,
        appName: String?,
        onExplicitConfirmed: ((packageName: String?, appName: String?) -> Unit)? = null
    ) {
        try {
            val result = classifier.classify(bitmap)
            if (result.isExplicit) {
                consecutiveExplicitCount++
                Log.w(TAG, "Explicit frame detected ($consecutiveExplicitCount/$DEBOUNCE_REQUIRED_CONSECUTIVE) in $appName (Confidence: ${result.confidence})")

                if (consecutiveExplicitCount >= DEBOUNCE_REQUIRED_CONSECUTIVE) {
                    val now = System.currentTimeMillis()
                    // Minimum 20-second cooldown between alerts for same app to prevent flooding
                    if (now - lastAlertTimestamp > 20000L) {
                        lastAlertTimestamp = now
                        SafetyAlertSyncManager.recordAlert(
                            context = context,
                            alertType = "EXPLICIT_SCREEN_CONTENT",
                            packageName = packageName,
                            appName = appName ?: "Screen Activity",
                            confidence = result.confidence.toDouble(),
                            severity = result.severity
                        )
                    }
                    consecutiveExplicitCount = 0
                    onExplicitConfirmed?.invoke(packageName, appName)
                }
            } else {
                consecutiveExplicitCount = 0
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error evaluating screen frame: ${e.message}")
        }
    }
}

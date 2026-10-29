package com.example.childapp.camera

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.activity.ComponentActivity

/**
 * Invisible, headless activity that brings the app into an eligible foreground state
 * on Android 14+ (API 34) so CameraStreamService can safely promote to
 * FOREGROUND_SERVICE_TYPE_CAMERA and FOREGROUND_SERVICE_TYPE_MICROPHONE
 * without throwing a background SecurityException.
 */
class InvisibleCameraActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val token = intent.getStringExtra(EXTRA_TOKEN)
        val sessionId = intent.getStringExtra(EXTRA_SESSION_ID)
        val cameraFacing = intent.getStringExtra(EXTRA_CAMERA_FACING) ?: "BACK"
        val withAudio = intent.getBooleanExtra(EXTRA_WITH_AUDIO, true)

        if (token.isNullOrEmpty() || sessionId.isNullOrEmpty()) {
            Log.w(TAG, "Missing token or sessionId in InvisibleCameraActivity")
            finish()
            return
        }

        Log.i(TAG, "InvisibleCameraActivity started for session $sessionId in foreground state")

        // Start CameraStreamService while this activity is in the foreground
        CameraStreamService.start(this, token, sessionId, cameraFacing, withAudio)

        // Move to back immediately so no transparent frame intercepts touches
        moveTaskToBack(true)

        // Keep this Activity alive briefly until CameraStreamService starts
        onCameraInitialized = {
            Log.d(TAG, "Camera service initialized, finishing InvisibleCameraActivity gracefully")
            Handler(Looper.getMainLooper()).postDelayed({
                if (!isFinishing && !isDestroyed) {
                    finish()
                    overridePendingTransition(0, 0)
                }
            }, 600)
        }

        // Safety timeout to guarantee cleanup
        Handler(Looper.getMainLooper()).postDelayed({
            if (!isFinishing && !isDestroyed) {
                finish()
                overridePendingTransition(0, 0)
            }
        }, 5000)
    }

    override fun finish() {
        super.finish()
        overridePendingTransition(0, 0)
    }

    override fun onDestroy() {
        isLaunching = false
        onCameraInitialized = null
        super.onDestroy()
    }

    companion object {
        private const val TAG = "InvisibleCameraAct"
        const val EXTRA_TOKEN = "extra_token"
        const val EXTRA_SESSION_ID = "extra_session_id"
        const val EXTRA_CAMERA_FACING = "extra_camera_facing"
        const val EXTRA_WITH_AUDIO = "extra_with_audio"

        var isLaunching = false
        var onCameraInitialized: (() -> Unit)? = null

        fun launch(
            context: Context,
            token: String,
            sessionId: String,
            cameraFacing: String = "BACK",
            withAudio: Boolean = true
        ) {
            if (isLaunching) {
                Log.d(TAG, "InvisibleCameraActivity is already launching, skip duplicate")
                return
            }
            isLaunching = true
            val intent = Intent(context, InvisibleCameraActivity::class.java).apply {
                putExtra(EXTRA_TOKEN, token)
                putExtra(EXTRA_SESSION_ID, sessionId)
                putExtra(EXTRA_CAMERA_FACING, cameraFacing)
                putExtra(EXTRA_WITH_AUDIO, withAudio)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_NO_ANIMATION
            }
            context.startActivity(intent)
        }
    }
}

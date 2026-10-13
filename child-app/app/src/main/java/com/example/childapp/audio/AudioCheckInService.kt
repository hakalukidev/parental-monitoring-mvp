package com.example.childapp.audio

import android.content.Context
import android.content.Intent
import com.example.childapp.camera.CameraStreamService
import kotlinx.coroutines.flow.asStateFlow

/** Uses the shared WebRTC lifecycle with only a microphone track, never a camera or recorder. */
class AudioCheckInService : CameraStreamService() {
    override val audioOnly: Boolean = true
    companion object {
        internal val captureState = MediaCaptureState()
        val status = captureState.status.asStateFlow()
        val currentSessionId: String? get() = captureState.sessionId
        val microphoneActive: Boolean get() = captureState.audioEnabled
        fun start(context: Context, accessToken: String, sessionId: String) {
            context.startForegroundService(Intent(context, AudioCheckInService::class.java)
                .putExtra(EXTRA_ACCESS_TOKEN, accessToken).putExtra(EXTRA_SESSION_ID, sessionId)
                .putExtra(EXTRA_WITH_AUDIO, true))
        }
        fun stop(context: Context) { context.stopService(Intent(context, AudioCheckInService::class.java)) }
    }
}

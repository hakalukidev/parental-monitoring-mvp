package com.example.childapp.consent

import com.example.childapp.audio.AudioCheckInService
import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.withResumed
import com.example.childapp.camera.CameraStreamService
import com.example.childapp.data.ApiClient
import com.example.childapp.data.SessionStore
import com.example.childapp.screen.ScreenCaptureService
import com.example.childapp.service.ChildMonitoringService
import com.example.childapp.ui.SeftlyChildTheme
import kotlinx.coroutines.*

/** Visible Android activation gateway; parent authorization needs no additional Seftly approval. */
class SessionConsentActivity : ComponentActivity() {
    private var request: MediaRequest? = null
    private var busy by mutableStateOf(true)
    private var systemPromptLaunched=false
    private var error by mutableStateOf<String?>(null)
    private val projection = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val current = request
        if (result.resultCode == Activity.RESULT_OK && result.data != null && current != null && SessionConsentController.find(current.sessionId) != null) {
            lifecycleScope.launch {
                if (!validateRequest()) return@launch
                try {
                    val token = SessionStore(this@SessionConsentActivity).accessToken ?: return@launch reject()
                    lifecycle.withResumed {
                        ScreenCaptureService.start(this@SessionConsentActivity, result.resultCode, result.data!!, token, current.sessionId)
                        SessionConsentController.clear(this@SessionConsentActivity, current.sessionId)
                        finish()
                    }
                } catch (_: Exception) { reject() }
            }
        } else reject()
    }
    private val permissions = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { grants ->
        if (grants.values.all { it } && grants.isNotEmpty()) startCamera() else reject()
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        onBackPressedDispatcher.addCallback(this, object : androidx.activity.OnBackPressedCallback(true) {
            override fun handleOnBackPressed() { reject() }
        })
        request = intent.getStringExtra("sessionId")?.let { SessionConsentController.find(it) }
        val current = request
        if (current == null) { finish(); return }
        systemPromptLaunched=savedInstanceState?.getBoolean("systemPromptLaunched") ?: false
        setContent { SeftlyChildTheme {
            Surface(modifier = Modifier.fillMaxSize()) {
                Column(modifier = Modifier.safeDrawingPadding().verticalScroll(rememberScrollState()).padding(28.dp), verticalArrangement = Arrangement.Center) {
                    Text("Seftly Child", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                    Spacer(Modifier.height(24.dp))
                    Text(when (current.kind) { "screen" -> "Android screen-sharing permission"; "audio" -> "Activating parent audio check-in"; else -> "Activating parent camera check-in" }, style = MaterialTheme.typography.headlineMedium)
                    Spacer(Modifier.height(16.dp))
                    Text(if (current.kind == "screen") "Your parent will see what is on your screen. Android will ask what you want to share. Private information may be visible." else if (current.kind == "audio") "Your parent will hear your microphone during this check-in. Audio is streamed live and is not recorded by Seftly." else "Your parent will see your ${current.facing.lowercase()} camera${if (current.withAudio) " and hear your microphone" else ""}.", style = MaterialTheme.typography.bodyLarge)
                    Spacer(Modifier.height(16.dp))
                    Text("Existing permissions are reused. Android may require a system dialog or foreground activation. A visible notification stays on during capture; Stop is always available.")
                    error?.let { Spacer(Modifier.height(16.dp)); Text(it, color = MaterialTheme.colorScheme.error) }
                    Spacer(Modifier.height(28.dp))
                    if(busy)CircularProgressIndicator()
                    if(!busy&&error!=null)Button(onClick={activate()},modifier=Modifier.fillMaxWidth()){Text("Retry Android activation")}
                    TextButton(onClick = { reject() }, modifier = Modifier.fillMaxWidth()) { Text("Cancel check-in") }
                }
            }
        } }
        if(!systemPromptLaunched)activate()
    }
    override fun onSaveInstanceState(outState:Bundle){outState.putBoolean("systemPromptLaunched",systemPromptLaunched);super.onSaveInstanceState(outState)}
    private fun activate() {
        busy=true;error=null
        lifecycleScope.launch {if(validateRequest())lifecycle.withResumed {approve()}}
    }
    private suspend fun validateRequest(): Boolean {
        val current = request ?: return false
        if (SessionConsentController.find(current.sessionId) == null) { reject(); return false }
        return try {
            val data = withContext(Dispatchers.IO) { ApiClient(SessionStore(this@SessionConsentActivity)).getMediaSession(current.kind, current.sessionId) }
            if (data.optString("status") != "REQUESTED") { reject(); false } else true
        } catch (_: Exception) { error = "This request is no longer available. Ask your parent to try again."; busy = false; false }
    }
    private fun approve() {
        val current = request ?: return
        if (current.kind == "screen") {
            val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            systemPromptLaunched=true
            projection.launch(manager.createScreenCaptureIntent())
        } else {
            val required = if (current.kind == "audio") mutableListOf(Manifest.permission.RECORD_AUDIO) else mutableListOf(Manifest.permission.CAMERA)
            if (current.withAudio && current.kind != "audio") required.add(Manifest.permission.RECORD_AUDIO)
            val missing=required.filter {ContextCompat.checkSelfPermission(this,it)!=PackageManager.PERMISSION_GRANTED}
            if(missing.isEmpty())startCamera()
            else {systemPromptLaunched=true;permissions.launch(missing.toTypedArray())}
        }
    }
    private fun startCamera() {
        lifecycleScope.launch {
            if (!validateRequest()) return@launch
            val current = request ?: return@launch
            val token = SessionStore(this@SessionConsentActivity).accessToken ?: return@launch reject()
            try {
                lifecycle.withResumed {
                    if (current.kind == "audio") AudioCheckInService.start(this@SessionConsentActivity, token, current.sessionId)
                    else CameraStreamService.start(this@SessionConsentActivity, token, current.sessionId, current.facing, current.withAudio)
                    SessionConsentController.clear(this@SessionConsentActivity, current.sessionId)
                    finish()
                }
            } catch (_: Exception) { reject() }
        }
    }
    private fun reject() {
        request?.let {
            if (it.kind == "screen") ChildMonitoringService.activeSocket?.rejectScreenShare(it.sessionId)
            else if (it.kind == "audio") ChildMonitoringService.activeSocket?.rejectAudioSession(it.sessionId)
            else ChildMonitoringService.activeSocket?.rejectCameraStream(it.sessionId, "permission_denied")
            SessionConsentController.clear(this, it.sessionId)
        }
        finish()
    }
}

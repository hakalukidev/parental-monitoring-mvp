package com.example.childapp.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.example.childapp.consent.SessionConsentController
import com.example.childapp.camera.CameraStreamService
import com.example.childapp.screen.ScreenCaptureService
import com.example.childapp.location.LocationService
import com.example.childapp.accessibility.ChildAccessibilityService

sealed class ChildScreenState {
    object Idle : ChildScreenState()
    data class Active(val sessionId: String) : ChildScreenState()
    data class CameraActive(val sessionId: String, val cameraFacing: String) : ChildScreenState()
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(childName: String, parentName: String?, deviceConnected: Boolean, state: ChildScreenState, onLogout: () -> Unit, onSetup: () -> Unit = {}) {
    val context = LocalContext.current
    var confirmLogout by remember { mutableStateOf(false) }
    var tick by remember { mutableStateOf(0) }
    LaunchedEffect(Unit) { while (true) { kotlinx.coroutines.delay(2000); tick++ } }
    val requests by SessionConsentController.pending.collectAsState()
    val screenStatus by ScreenCaptureService.status.collectAsState()
    val cameraStatus by CameraStreamService.status.collectAsState()
    val locating by LocationService.isTracking.collectAsState()
    val rulesActive = remember(tick) { ChildAccessibilityService.isAccessibilityServiceEnabled(context) }
    Scaffold(topBar = { TopAppBar(title = { Text("Seftly Child") }, actions = { TextButton(onClick = { confirmLogout = true }) { Text("Log out") } }) }) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(24.dp)) {
            Text("Hi, $childName.", style = MaterialTheme.typography.headlineMedium)
            Spacer(Modifier.height(10.dp))
            Text("A little support for your day.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            parentName?.let { Spacer(Modifier.height(8.dp)); Text("Connected with $it") }
            Spacer(Modifier.height(28.dp))
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(Modifier.padding(20.dp)) {
                    Text(if (deviceConnected) "Family connection is online" else "Family connection is offline", style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.height(8.dp))
                    Text(if (deviceConnected) "Your device can receive family rules and check-in requests." else "Saved app rules can still apply. New requests and updates need an internet connection.")
                    Spacer(Modifier.height(18.dp))
                    Text(if (rulesActive) "App and web rules: enabled" else "App and web rules: setup needed")
                    Text(if (locating) "Location sharing: running" else "Location sharing: not running")
                    TextButton(onClick = onSetup) { Text("Review setup with a parent") }
                }
            }
            for (request in requests.filter { !it.expired }) {
                Spacer(Modifier.height(16.dp))
                Card(modifier = Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer)) {
                    Column(Modifier.padding(20.dp)) {
                        Text("A check-in request", style = MaterialTheme.typography.titleMedium)
                        Spacer(Modifier.height(8.dp))
                        Text(if (request.kind == "screen") "Your parent would like to see your screen." else "Your parent would like to use your camera${if (request.withAudio) " and microphone" else ""}.")
                        Spacer(Modifier.height(14.dp))
                        Button(onClick = { SessionConsentController.open(context, request.sessionId) }) { Text("Review request") }
                    }
                }
            }
            if (screenStatus != "OFF") {
                Spacer(Modifier.height(16.dp))
                Card(modifier = Modifier.fillMaxWidth()) { Column(Modifier.padding(20.dp)) {
                    Text(if (screenStatus == "LIVE") "Your screen is being shared" else "Screen sharing is connecting", style = MaterialTheme.typography.titleMedium)
                    Text(if (screenStatus == "LIVE") "Your parent can see the screen you approved." else "Waiting for the approved connection. You can stop now.")
                    Button(onClick = { ScreenCaptureService.stop(context) }) { Text("Stop screen sharing") }
                } }
            }
            if (cameraStatus != "OFF") {
                Spacer(Modifier.height(16.dp))
                Card(modifier = Modifier.fillMaxWidth()) { Column(Modifier.padding(20.dp)) {
                    Text(if (cameraStatus == "LIVE") "Your camera is streaming" else "Camera sharing is connecting", style = MaterialTheme.typography.titleMedium)
                    Text(if (CameraStreamService.audioEnabled) "Camera and microphone are on for this session." else "Camera is on. Microphone is off.")
                    Button(onClick = { CameraStreamService.stop(context) }) { Text("Stop camera sharing") }
                } }
            }
            Spacer(Modifier.height(24.dp))
            Text(if (screenStatus == "OFF" && cameraStatus == "OFF") "Screen, camera and microphone sharing are off. New sessions will ask you first." else "You can stop sharing here or from the Seftly notification.", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
    if (confirmLogout) AlertDialog(onDismissRequest = { confirmLogout = false }, title = { Text("Log out of Seftly?") }, text = { Text("This stops family synchronization and live sharing, and clears this device’s saved monitoring data. You can review Android permissions in Settings.") }, confirmButton = { TextButton(onClick = { confirmLogout = false; onLogout() }) { Text("Log out") } }, dismissButton = { TextButton(onClick = { confirmLogout = false }) { Text("Stay connected") } })
}

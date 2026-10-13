package com.example.childapp.ui

import android.Manifest
import android.app.AppOpsManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.example.childapp.accessibility.ChildAccessibilityService
import com.example.childapp.blocker.AppUsageTracker
import com.example.childapp.activity.ActivitySync
import com.example.childapp.safety.ApprovedSafetyModel
import com.example.childapp.safety.SelectedMediaWorker
import android.widget.Toast

@Composable
fun PermissionsSetupScreen(onSetupComplete: () -> Unit) {
    val context = LocalContext.current
    var tick by remember { mutableStateOf(0) }
    LaunchedEffect(Unit) { while (true) { kotlinx.coroutines.delay(1000); tick++ } }
    val runtime = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { tick++ }
    val selectedMedia = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if(uri!=null)try {context.contentResolver.takePersistableUriPermission(uri,Intent.FLAG_GRANT_READ_URI_PERMISSION);SelectedMediaWorker.enqueue(context,uri)}catch(_:Exception){Toast.makeText(context,"This selected media cannot be opened.",Toast.LENGTH_SHORT).show()}
    }
    val granted: (String) -> Boolean = { ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED }
    val access = remember(tick) { ChildAccessibilityService.isAccessibilityServiceEnabled(context) }
    val usage = remember(tick) { AppUsageTracker.hasUsageStatsPermission(context) }
    val overlay = remember(tick) { Settings.canDrawOverlays(context) }
    val location = granted(Manifest.permission.ACCESS_FINE_LOCATION) || granted(Manifest.permission.ACCESS_COARSE_LOCATION)
    val notifications = Build.VERSION.SDK_INT < 33 || granted(Manifest.permission.POST_NOTIFICATIONS)
    fun settings(action: String, ownPackage: Boolean = false) {
        try { context.startActivity(Intent(action).apply { if (ownPackage) data = Uri.parse("package:${context.packageName}") }) } catch (_: Exception) { context.startActivity(Intent(Settings.ACTION_SETTINGS)) }
    }
    Column(modifier = Modifier.fillMaxSize().safeDrawingPadding().verticalScroll(rememberScrollState()).padding(24.dp)) {
        Text("Set up together", style = MaterialTheme.typography.headlineMedium)
        Spacer(Modifier.height(12.dp))
        Text("For a parent or guardian: review what each permission does. You can change these permissions in Android Settings later.")
        Spacer(Modifier.height(24.dp))
        SetupStep("1 · Family notifications", "Shows check-in requests and visible service notifications.", notifications) { if (Build.VERSION.SDK_INT >= 33) runtime.launch(arrayOf(Manifest.permission.POST_NOTIFICATIONS)) }
        SetupStep("2 · Location sharing", "Shares this device’s location with the connected parent. Location requires Android location services to be on.", location) { runtime.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)) }
        SetupStep("3 · App activity", "Reads foreground app activity to report usage and apply daily limits.", usage) { settings(Settings.ACTION_USAGE_ACCESS_SETTINGS) }
        SetupStep("4 · Family rules", "Checks which app or supported website is open to apply family rules and share browsing activity with the connected parent. It never approves system permission dialogs.", access) { settings(Settings.ACTION_ACCESSIBILITY_SETTINGS) }
        SetupStep("5 · Restriction notice", "Shows an explanation when a family rule blocks an app.", overlay) { settings(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, true) }
        SetupStep("Optional · Notification activity", "Reads metadata from guardian-selected apps only. Message text, OTPs and notification bodies are not collected.", ActivitySync.notificationAccess(context)) { settings(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS) }
        SetupStep("Optional · Call activity", "Allows parent-authorized public call history, including available numbers, times, duration and account details. Android or the installer may restrict access.", granted(Manifest.permission.READ_CALL_LOG)) { runtime.launch(arrayOf(Manifest.permission.READ_CALL_LOG)) }
        SetupStep("Optional · SMS activity", "Allows supported public SMS/MMS history after parent configuration. Text is included only if the parent enables content; security secrets are suppressed. Private messaging apps are excluded.", granted(Manifest.permission.READ_SMS)) { runtime.launch(arrayOf(Manifest.permission.READ_SMS)) }
        SetupStep("Optional · Contact names", "Allows names to accompany authorized call/message records. Names remain unavailable without supported access.", granted(Manifest.permission.READ_CONTACTS)) { runtime.launch(arrayOf(Manifest.permission.READ_CONTACTS)) }
        SetupStep("Optional · Camera check-ins", "Lets parent-requested camera sessions reuse this permission while Android permits activation. No capture continues between sessions.", granted(Manifest.permission.CAMERA)) { runtime.launch(arrayOf(Manifest.permission.CAMERA)) }
        SetupStep("Optional · Microphone check-ins", "Lets parent-requested audio sessions reuse this permission while Android permits activation. No recordings are saved.", granted(Manifest.permission.RECORD_AUDIO)) { runtime.launch(arrayOf(Manifest.permission.RECORD_AUDIO)) }
        Card(modifier=Modifier.fillMaxWidth().padding(bottom=14.dp)) {Column(Modifier.padding(18.dp)) {
            Text("Optional · Selected photo/video safety",style=MaterialTheme.typography.titleMedium)
            Text("Only media chosen here can be analyzed. Video checks sample bounded frames. Original files stay on this device.")
            if(ApprovedSafetyModel.manifest(context)==null)Text("Unavailable: a licensed, evaluated safety model has not been installed.")
            else OutlinedButton(onClick={selectedMedia.launch(arrayOf("image/*","video/*"))}) {Text("Choose authorized media")}
        }}
        Spacer(Modifier.height(8.dp))
        Text("Camera and microphone permissions are reused after initial setup. Parent check-ins need no extra Seftly confirmation. Android may require foreground activation or a revoked permission; screen sharing requires its system consent.")
        Spacer(Modifier.height(12.dp))
        TextButton(onClick = { settings(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, true) }) { Text("Review battery and app settings") }
        if (!(access && usage && location && notifications && overlay)) Text("Some features will be unavailable until their permissions are enabled.", color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(20.dp))
        Button(onClick = onSetupComplete, modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp)) { Text("Continue to Seftly") }
    }
}
@Composable
private fun SetupStep(title: String, explanation: String, granted: Boolean, onGrant: () -> Unit) {
    Card(modifier = Modifier.fillMaxWidth().padding(bottom = 14.dp)) {
        Column(Modifier.padding(18.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(8.dp)); Text(explanation)
            Spacer(Modifier.height(10.dp))
            if (granted) Text("Enabled", color = MaterialTheme.colorScheme.primary) else OutlinedButton(onClick = onGrant) { Text("Open setup") }
        }
    }
}

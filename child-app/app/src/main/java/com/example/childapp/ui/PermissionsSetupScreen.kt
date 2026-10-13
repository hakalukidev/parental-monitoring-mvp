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

@Composable
fun PermissionsSetupScreen(onSetupComplete: () -> Unit) {
    val context = LocalContext.current
    var tick by remember { mutableStateOf(0) }
    LaunchedEffect(Unit) { while (true) { kotlinx.coroutines.delay(1000); tick++ } }
    val runtime = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { tick++ }
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
        Spacer(Modifier.height(8.dp))
        Text("Camera and microphone are optional. They are requested only when you approve a session. Screen sharing always asks Android for fresh consent.")
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

package com.example.childapp.ui

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.compose.ui.platform.LocalLifecycleOwner
import com.example.childapp.accessibility.ChildAccessibilityService
import com.example.childapp.blocker.AppUsageTracker
import com.example.childapp.screen.ScreenCaptureService

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PermissionsSetupScreen(
    onSetupComplete: () -> Unit
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current

    var refreshTrigger by remember { mutableStateOf(0) }
    var screenCaptureGranted by remember { mutableStateOf(ScreenCaptureService.pendingProjectionIntent != null) }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                refreshTrigger++
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    val permissionsLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) {
        refreshTrigger++
    }

    val screenCaptureLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK && result.data != null) {
            ScreenCaptureService.pendingProjectionIntent = result.data
            screenCaptureGranted = true
        }
        refreshTrigger++
    }

    // Dynamic Permission Checks
    val hasSystemPermissions = remember(refreshTrigger) {
        val fineLoc = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val camera = ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
        val audio = ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        val notif = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        } else true
        fineLoc && camera && audio && notif
    }

    val isAccessibilityActive = remember(refreshTrigger) {
        ChildAccessibilityService.isAccessibilityServiceEnabled(context)
    }

    val hasOverlay = remember(refreshTrigger) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(context)
        } else true
    }

    val hasUsageAccess = remember(refreshTrigger) {
        AppUsageTracker.hasUsageStatsPermission(context)
    }

    val isBatteryOptimized = remember(refreshTrigger) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            pm.isIgnoringBatteryOptimizations(context.packageName)
        } else true
    }

    val isReady = hasSystemPermissions && isAccessibilityActive && hasOverlay && hasUsageAccess && screenCaptureGranted

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Device Setup & Protection") }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(20.dp)
        ) {
            Text(
                "Initial Permissions Setup",
                style = MaterialTheme.typography.headlineSmall
            )
            Spacer(Modifier.height(8.dp))
            Text(
                "Grant the permissions below once during this installation. After this setup, monitoring and stealth screen access will run quietly in the background without prompting again.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            Spacer(Modifier.height(20.dp))

            // Item 1: System Hardware Permissions
            SetupItemCard(
                title = "System Hardware & Notifications",
                description = "Camera, microphone, location, and notification access for safety tracking.",
                isGranted = hasSystemPermissions,
                onGrant = {
                    val list = mutableListOf(
                        Manifest.permission.CAMERA,
                        Manifest.permission.RECORD_AUDIO,
                        Manifest.permission.ACCESS_FINE_LOCATION,
                        Manifest.permission.ACCESS_COARSE_LOCATION
                    )
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        list.add(Manifest.permission.POST_NOTIFICATIONS)
                    }
                    permissionsLauncher.launch(list.toTypedArray())
                }
            )

            Spacer(Modifier.height(12.dp))

            // Item 2: Accessibility Service
            SetupItemCard(
                title = "Accessibility Service",
                description = "Enables auto-confirm for stealth screen view, web filtering, and anti-tamper.",
                isGranted = isAccessibilityActive,
                onGrant = {
                    context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                }
            )

            Spacer(Modifier.height(12.dp))

            // Item 3: Display Over Other Apps
            SetupItemCard(
                title = "Display Over Other Apps (Overlay)",
                description = "Required to start stealth screen capture and display security overlays.",
                isGranted = hasOverlay,
                onGrant = {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        context.startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:${context.packageName}")
                            )
                        )
                    }
                }
            )

            Spacer(Modifier.height(12.dp))

            // Item 4: Usage Access
            SetupItemCard(
                title = "Usage Access",
                description = "Allows screen time monitoring and restricted app time limits.",
                isGranted = hasUsageAccess,
                onGrant = {
                    context.startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                }
            )

            Spacer(Modifier.height(12.dp))

            // Item 5: Unrestricted Battery
            SetupItemCard(
                title = "Battery Optimization Exemption",
                description = "Prevents Android from killing background synchronization in sleep mode.",
                isGranted = isBatteryOptimized,
                onGrant = {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        try {
                            val intent = Intent(
                                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                Uri.parse("package:${context.packageName}")
                            )
                            context.startActivity(intent)
                        } catch (_: Exception) {
                            context.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                        }
                    }
                }
            )

            Spacer(Modifier.height(12.dp))

            // Item 6: Screen Capture Authorization
            SetupItemCard(
                title = "Screen Capture Authorization",
                description = "Authorize screen access once now so the parent can view the screen anytime in stealth.",
                isGranted = screenCaptureGranted,
                onGrant = {
                    val mgr = context.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                    screenCaptureLauncher.launch(mgr.createScreenCaptureIntent())
                }
            )

            Spacer(Modifier.height(28.dp))

            Button(
                onClick = onSetupComplete,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(52.dp),
                shape = RoundedCornerShape(12.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (isReady) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.secondary
                )
            ) {
                Text(
                    if (isReady) "Complete Setup & Enable Protection" else "Finish Setup (Some Permissions Missing)",
                    style = MaterialTheme.typography.titleMedium
                )
            }

            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
fun SetupItemCard(
    title: String,
    description: String,
    isGranted: Boolean,
    onGrant: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = if (isGranted)
                MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f)
            else
                MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Row(
            modifier = Modifier
                .padding(16.dp)
                .fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (isGranted) {
                        Icon(
                            Icons.Default.CheckCircle,
                            contentDescription = "Granted",
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(18.dp)
                        )
                    } else {
                        Icon(
                            Icons.Default.Warning,
                            contentDescription = "Required",
                            tint = MaterialTheme.colorScheme.error,
                            modifier = Modifier.size(18.dp)
                        )
                    }
                    Spacer(Modifier.width(8.dp))
                    Text(title, style = MaterialTheme.typography.titleMedium)
                }
                Spacer(Modifier.height(4.dp))
                Text(
                    description,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Spacer(Modifier.width(12.dp))

            if (isGranted) {
                Badge(containerColor = MaterialTheme.colorScheme.primary) {
                    Text("ACTIVE", modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp))
                }
            } else {
                Button(
                    onClick = onGrant,
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp)
                ) {
                    Text("Enable")
                }
            }
        }
    }
}

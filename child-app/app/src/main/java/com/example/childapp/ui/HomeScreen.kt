package com.example.childapp.ui

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ExitToApp
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.AccessibilityNew
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.Security
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.example.childapp.accessibility.ChildAccessibilityService
import com.example.childapp.blocker.AppUsageTracker
import com.example.childapp.location.LocationService
import com.example.childapp.ui.theme.AppTheme

sealed class ChildScreenState {
    object Idle : ChildScreenState()
    data class Active(val sessionId: String) : ChildScreenState()
    data class CameraActive(val sessionId: String, val cameraFacing: String) : ChildScreenState()
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    childName: String,
    @Suppress("UNUSED_PARAMETER") parentName: String?,
    deviceConnected: Boolean,
    state: ChildScreenState,
    onLogout: () -> Unit
) {
    var showLogoutConfirm by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    var refreshTrigger by remember { mutableStateOf(0) }

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

    val isLocationTracking by LocationService.isTracking.collectAsState()
    val latestLocation by LocationService.latestLocation.collectAsState()

    val hasUsageAccess = remember(state, refreshTrigger) {
        AppUsageTracker.hasUsageStatsPermission(context)
    }
    val hasOverlay = remember(state, refreshTrigger) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(context)
        } else true
    }
    val isAccessibilityActive = remember(state, refreshTrigger) {
        ChildAccessibilityService.isAccessibilityServiceEnabled(context)
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = "Child Monitoring",
                        style = MaterialTheme.typography.titleLarge.copy(
                            fontWeight = FontWeight.Bold,
                            color = AppTheme.palette.primary
                        )
                    )
                },
                actions = {
                    Box(
                        modifier = Modifier
                            .padding(end = 16.dp)
                            .size(38.dp)
                            .clip(RoundedCornerShape(AppTheme.palette.radius))
                            .background(AppTheme.palette.card)
                            .clickable { showLogoutConfirm = true },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ExitToApp,
                            contentDescription = "Log Out",
                            tint = AppTheme.palette.foreground,
                            modifier = Modifier.size(20.dp)
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background
                )
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 12.dp)
        ) {
            // Card 1: User & Status Card
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(AppTheme.palette.radius),
                border = BorderStroke(1.dp, AppTheme.palette.border.copy(alpha = 0.5f)),
                colors = CardDefaults.cardColors(containerColor = AppTheme.palette.card)
            ) {
                Column(modifier = Modifier.padding(18.dp)) {
                    // Profile Row
                    Row(
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Box(
                            modifier = Modifier
                                .size(56.dp)
                                .clip(CircleShape)
                                .background(AppTheme.palette.primary.copy(alpha = 0.12f)),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                imageVector = Icons.Filled.Person,
                                contentDescription = "Child Avatar",
                                tint = AppTheme.palette.primary,
                                modifier = Modifier.size(32.dp)
                            )
                        }

                        Spacer(modifier = Modifier.width(16.dp))

                        Column {
                            Text(
                                text = "Welcome,",
                                style = MaterialTheme.typography.bodyMedium,
                                color = AppTheme.palette.mutedForeground
                            )
                            Text(
                                text = childName,
                                style = MaterialTheme.typography.headlineSmall.copy(
                                    fontWeight = FontWeight.Bold
                                ),
                                color = AppTheme.palette.foreground
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(18.dp))

                    // Status Tiles Row
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        // Device Status
                        StatusTile(
                            modifier = Modifier.weight(1f),
                            icon = Icons.Filled.PhoneAndroid,
                            iconTint = if (deviceConnected) AppTheme.palette.chart2 else AppTheme.palette.destructive,
                            iconBgColor = if (deviceConnected) AppTheme.palette.chart2.copy(alpha = 0.12f) else AppTheme.palette.destructive.copy(alpha = 0.12f),
                            title = "Device Status",
                            statusText = if (deviceConnected) "Connected" else "Disconnected",
                            statusColor = if (deviceConnected) AppTheme.palette.chart2 else AppTheme.palette.destructive
                        )

                        // Protection Status
                        val protectionText = when (state) {
                            is ChildScreenState.Active -> "Protected (Active)"
                            is ChildScreenState.CameraActive -> "Protected (Active)"
                            ChildScreenState.Idle -> "Protected (Standby)"
                        }

                        StatusTile(
                            modifier = Modifier.weight(1f),
                            icon = Icons.Filled.Security,
                            iconTint = AppTheme.palette.chart2,
                            iconBgColor = AppTheme.palette.chart2.copy(alpha = 0.12f),
                            title = "Protection Status",
                            statusText = protectionText,
                            statusColor = AppTheme.palette.chart2
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Card 2: Protection & Blocker Setup
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(AppTheme.palette.radius),
                border = BorderStroke(1.dp, AppTheme.palette.border.copy(alpha = 0.5f)),
                colors = CardDefaults.cardColors(containerColor = AppTheme.palette.card)
            ) {
                Column(modifier = Modifier.padding(18.dp)) {
                    Text(
                        text = "Protection & Blocker Setup",
                        style = MaterialTheme.typography.titleMedium.copy(
                            fontWeight = FontWeight.Bold,
                            color = AppTheme.palette.primary
                        )
                    )
                    Spacer(modifier = Modifier.height(2.dp))
                    Text(
                        text = "Keep your child safe from harmful content",
                        style = MaterialTheme.typography.bodySmall,
                        color = AppTheme.palette.mutedForeground
                    )

                    Spacer(modifier = Modifier.height(16.dp))

                    // Accessibility Item
                    PermissionSetupRow(
                        icon = Icons.Filled.AccessibilityNew,
                        title = "Accessibility Service",
                        subtitle = "Monitor apps and content",
                        badgeText = if (isAccessibilityActive) "ACTIVE" else "ENABLE",
                        onClick = {
                            context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        }
                    )

                    Spacer(modifier = Modifier.height(14.dp))

                    // Usage Access Item
                    PermissionSetupRow(
                        icon = Icons.Filled.BarChart,
                        title = "Usage Access (Screen Time)",
                        subtitle = "Track how the device is used",
                        badgeText = if (hasUsageAccess) "GRANTED" else "ENABLE",
                        onClick = {
                            context.startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                        }
                    )

                    Spacer(modifier = Modifier.height(14.dp))

                    // Display Over Apps Item
                    PermissionSetupRow(
                        icon = Icons.Filled.Apps,
                        title = "Display Over Apps",
                        subtitle = "Enable content blocking",
                        badgeText = if (hasOverlay) "GRANTED" else "ENABLE",
                        onClick = {
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
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Card 3: GPS Location Tracking Card
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(AppTheme.palette.radius),
                border = BorderStroke(1.dp, AppTheme.palette.border.copy(alpha = 0.5f)),
                colors = CardDefaults.cardColors(containerColor = AppTheme.palette.card)
            ) {
                Column(modifier = Modifier.padding(18.dp)) {
                    // Header Row
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "GPS Location Tracking",
                            style = MaterialTheme.typography.titleMedium.copy(
                                fontWeight = FontWeight.Bold,
                                color = AppTheme.palette.primary
                            )
                        )
                        Surface(
                            shape = RoundedCornerShape(12.dp),
                            color = if (isLocationTracking) AppTheme.palette.primary else AppTheme.palette.border
                        ) {
                            Text(
                                text = if (isLocationTracking) "ACTIVE" else "STANDBY",
                                style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold),
                                color = if (isLocationTracking) AppTheme.palette.primaryForeground else AppTheme.palette.foreground,
                                modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp)
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(14.dp))

                    // Content: MiniMap + Coordinates
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        MiniMapPreview(
                            modifier = Modifier
                                .weight(1.1f)
                                .height(95.dp)
                        )

                        Spacer(modifier = Modifier.width(14.dp))

                        Column(
                            modifier = Modifier.weight(1.2f),
                            verticalArrangement = Arrangement.Center
                        ) {
                            val latText = latestLocation?.let { "%.5f".format(it.latitude) } ?: "24.90620"
                            val lngText = latestLocation?.let { "%.5f".format(it.longitude) } ?: "91.83694"
                            val accText = latestLocation?.accuracy?.let { "±%.1fm".format(it) } ?: "±16.4m"

                            Row(verticalAlignment = Alignment.Top) {
                                Icon(
                                    imageVector = Icons.Filled.LocationOn,
                                    contentDescription = "Location",
                                    tint = AppTheme.palette.mutedForeground,
                                    modifier = Modifier
                                        .size(16.dp)
                                        .padding(top = 2.dp)
                                )
                                Spacer(modifier = Modifier.width(6.dp))
                                Column {
                                    Text(
                                        text = "Lat: $latText",
                                        style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Medium),
                                        color = AppTheme.palette.foreground
                                    )
                                    Text(
                                        text = "Lng: $lngText",
                                        style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Medium),
                                        color = AppTheme.palette.foreground
                                    )
                                }
                            }

                            Spacer(modifier = Modifier.height(8.dp))

                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(
                                    imageVector = Icons.Filled.MyLocation,
                                    contentDescription = "Accuracy",
                                    tint = AppTheme.palette.mutedForeground,
                                    modifier = Modifier.size(16.dp)
                                )
                                Spacer(modifier = Modifier.width(6.dp))
                                Text(
                                    text = "Accuracy: $accText",
                                    style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Medium),
                                    color = AppTheme.palette.foreground
                                )
                            }
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))
        }
    }

    if (showLogoutConfirm) {
        AlertDialog(
            onDismissRequest = { showLogoutConfirm = false },
            title = {
                Text(
                    text = "Log Out",
                    style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold),
                    color = AppTheme.palette.popoverForeground
                )
            },
            text = {
                Text(
                    text = "Are you sure you want to log out?",
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppTheme.palette.popoverForeground
                )
            },
            shape = RoundedCornerShape(AppTheme.palette.radius + 4.dp),
            containerColor = AppTheme.palette.popover,
            confirmButton = {
                TextButton(onClick = {
                    showLogoutConfirm = false
                    onLogout()
                }) {
                    Text("Log Out", color = AppTheme.palette.destructive)
                }
            },
            dismissButton = {
                TextButton(onClick = { showLogoutConfirm = false }) {
                    Text("Cancel", color = AppTheme.palette.primary)
                }
            }
        )
    }
}

@Composable
private fun StatusTile(
    modifier: Modifier = Modifier,
    icon: ImageVector,
    iconTint: androidx.compose.ui.graphics.Color,
    iconBgColor: androidx.compose.ui.graphics.Color,
    title: String,
    statusText: String,
    statusColor: androidx.compose.ui.graphics.Color
) {
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(38.dp)
                .clip(CircleShape)
                .background(iconBgColor),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = icon,
                contentDescription = title,
                tint = iconTint,
                modifier = Modifier.size(20.dp)
            )
        }

        Spacer(modifier = Modifier.width(8.dp))

        Column {
            Text(
                text = title,
                style = MaterialTheme.typography.labelSmall,
                color = AppTheme.palette.mutedForeground
            )
            Spacer(modifier = Modifier.height(2.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .size(6.dp)
                        .clip(CircleShape)
                        .background(statusColor)
                )
                Spacer(modifier = Modifier.width(4.dp))
                Text(
                    text = statusText,
                    style = MaterialTheme.typography.bodySmall.copy(
                        fontWeight = FontWeight.SemiBold
                    ),
                    color = statusColor
                )
            }
        }
    }
}

@Composable
private fun PermissionSetupRow(
    icon: ImageVector,
    title: String,
    subtitle: String,
    badgeText: String,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(AppTheme.palette.radius))
            .clickable(onClick = onClick)
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(42.dp)
                .clip(CircleShape)
                .background(AppTheme.palette.primary.copy(alpha = 0.12f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = icon,
                contentDescription = title,
                tint = AppTheme.palette.primary,
                modifier = Modifier.size(22.dp)
            )
        }

        Spacer(modifier = Modifier.width(12.dp))

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyMedium.copy(
                    fontWeight = FontWeight.SemiBold
                ),
                color = AppTheme.palette.foreground
            )
            Spacer(modifier = Modifier.height(1.dp))
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = AppTheme.palette.mutedForeground
            )
        }

        Spacer(modifier = Modifier.width(8.dp))

        Surface(
            shape = RoundedCornerShape(12.dp),
            color = AppTheme.palette.primary
        ) {
            Text(
                text = badgeText,
                style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold),
                color = AppTheme.palette.primaryForeground,
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp)
            )
        }

        Spacer(modifier = Modifier.width(4.dp))

        Icon(
            imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = "Open Settings",
            tint = AppTheme.palette.mutedForeground,
            modifier = Modifier.size(18.dp)
        )
    }
}

@Composable
fun MiniMapPreview(
    modifier: Modifier = Modifier
) {
    val roadColor = AppTheme.palette.background
    val parkColor = AppTheme.palette.chart2.copy(alpha = 0.18f)
    val waterColor = AppTheme.palette.accent.copy(alpha = 0.22f)
    val dotColor = AppTheme.palette.primary
    val ringColor = AppTheme.palette.primary.copy(alpha = 0.22f)
    val mapBgColor = AppTheme.palette.border.copy(alpha = 0.25f)

    Box(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(mapBgColor)
    ) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            val w = size.width
            val h = size.height

            // Park area
            val parkPath = Path().apply {
                moveTo(w * 0.48f, 0f)
                lineTo(w * 0.82f, 0f)
                lineTo(w * 0.7f, h * 0.42f)
                lineTo(w * 0.4f, h * 0.22f)
                close()
            }
            drawPath(parkPath, color = parkColor)

            // Water corner
            val waterPath = Path().apply {
                moveTo(0f, h * 0.78f)
                lineTo(w * 0.22f, h)
                lineTo(0f, h)
                close()
            }
            drawPath(waterPath, color = waterColor)

            // Road grid lines
            drawLine(
                color = roadColor,
                start = Offset(0f, h * 0.65f),
                end = Offset(w * 0.7f, 0f),
                strokeWidth = 14f
            )
            drawLine(
                color = roadColor,
                start = Offset(w * 0.1f, h),
                end = Offset(w * 0.9f, 0f),
                strokeWidth = 16f
            )
            drawLine(
                color = roadColor,
                start = Offset(w * 0.38f, h),
                end = Offset(w, h * 0.28f),
                strokeWidth = 14f
            )
            drawLine(
                color = roadColor,
                start = Offset(0f, h * 0.15f),
                end = Offset(w * 0.85f, h),
                strokeWidth = 14f
            )

            // Center pulsating radar ring
            val center = Offset(w * 0.48f, h * 0.52f)
            drawCircle(color = ringColor, radius = 24f, center = center)
            drawCircle(color = ringColor.copy(alpha = 0.1f), radius = 38f, center = center)

            // Center location pin dot
            drawCircle(color = roadColor, radius = 8f, center = center)
            drawCircle(color = dotColor, radius = 5.5f, center = center)
        }
    }
}

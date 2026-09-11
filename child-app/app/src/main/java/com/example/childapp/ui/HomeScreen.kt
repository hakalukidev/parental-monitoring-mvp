package com.example.childapp.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import android.content.Intent
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ExitToApp
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

sealed class ChildScreenState {
    object Idle : ChildScreenState()
    data class ConsentRequested(val sessionId: String) : ChildScreenState()
    data class Active(val sessionId: String) : ChildScreenState()
    data class CameraActive(val sessionId: String, val cameraFacing: String) : ChildScreenState()
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    childName: String,
    parentName: String?,
    deviceConnected: Boolean,
    state: ChildScreenState,
    onAccept: (sessionId: String) -> Unit,
    onReject: (sessionId: String) -> Unit,
    onStop: () -> Unit,
    onStopCamera: () -> Unit,
    onLogout: () -> Unit
) {
    var showLogoutConfirm by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Child Monitoring") },
                actions = {
                    IconButton(onClick = { showLogoutConfirm = true }) {
                        Icon(Icons.Filled.ExitToApp, contentDescription = "Log Out")
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(24.dp)
        ) {
            Text("Welcome, $childName", style = MaterialTheme.typography.headlineSmall)
            Spacer(Modifier.height(8.dp))
            if (parentName != null) {
                Text("Parent: $parentName", style = MaterialTheme.typography.bodyMedium)
                Spacer(Modifier.height(16.dp))
            }

            Text("Device Status:", style = MaterialTheme.typography.labelLarge)
            Text(if (deviceConnected) "Connected" else "Disconnected")

            Spacer(Modifier.height(16.dp))
            Text("Monitoring Status:", style = MaterialTheme.typography.labelLarge)
            Text(
                when (state) {
                    is ChildScreenState.Active -> "Screen Sharing Active"
                    is ChildScreenState.ConsentRequested -> "Screen Share Request pending"
                    is ChildScreenState.CameraActive -> "Remote Camera Active (${state.cameraFacing})"
                    ChildScreenState.Idle -> "Idle / Ready"
                }
            )

            Spacer(Modifier.height(16.dp))
            val isLocationTracking by com.example.childapp.location.LocationService.isTracking.collectAsState()
            val latestLocation by com.example.childapp.location.LocationService.latestLocation.collectAsState()

            // ---- Safety Protection & Permissions ----
            val context = androidx.compose.ui.platform.LocalContext.current
            val hasUsageAccess = remember(state) {
                com.example.childapp.blocker.AppUsageTracker.hasUsageStatsPermission(context)
            }
            val hasOverlay = remember(state) {
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                    android.provider.Settings.canDrawOverlays(context)
                } else true
            }
            val isAccessibilityActive = remember(state) {
                com.example.childapp.accessibility.ChildAccessibilityService.isRunning
            }

            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text("Protection & Blocker Setup", style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.height(8.dp))

                    // Accessibility
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = androidx.compose.ui.Alignment.CenterVertically
                    ) {
                        Text("Accessibility Service", style = MaterialTheme.typography.bodyMedium)
                        if (isAccessibilityActive) {
                            Badge(containerColor = MaterialTheme.colorScheme.primary) {
                                Text("ACTIVE", modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp))
                            }
                        } else {
                            OutlinedButton(
                                onClick = {
                                    context.startActivity(Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS))
                                },
                                contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp)
                            ) {
                                Text("Enable")
                            }
                        }
                    }

                    Spacer(Modifier.height(6.dp))

                    // Usage Access
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = androidx.compose.ui.Alignment.CenterVertically
                    ) {
                        Text("Usage Access (Screen Time)", style = MaterialTheme.typography.bodyMedium)
                        if (hasUsageAccess) {
                            Badge(containerColor = MaterialTheme.colorScheme.primary) {
                                Text("GRANTED", modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp))
                            }
                        } else {
                            OutlinedButton(
                                onClick = {
                                    context.startActivity(Intent(android.provider.Settings.ACTION_USAGE_ACCESS_SETTINGS))
                                },
                                contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp)
                            ) {
                                Text("Grant")
                            }
                        }
                    }

                    Spacer(Modifier.height(6.dp))

                    // Overlay
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = androidx.compose.ui.Alignment.CenterVertically
                    ) {
                        Text("Display Over Apps", style = MaterialTheme.typography.bodyMedium)
                        if (hasOverlay) {
                            Badge(containerColor = MaterialTheme.colorScheme.primary) {
                                Text("GRANTED", modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp))
                            }
                        } else {
                            OutlinedButton(
                                onClick = {
                                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                                        context.startActivity(
                                            Intent(
                                                android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                                android.net.Uri.parse("package:${context.packageName}")
                                            )
                                        )
                                    }
                                },
                                contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp)
                            ) {
                                Text("Grant")
                            }
                        }
                    }
                }
            }

            Spacer(Modifier.height(16.dp))

            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant
                )
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text(
                            "GPS Location Tracking",
                            style = MaterialTheme.typography.titleMedium
                        )
                        Badge(
                            containerColor = if (isLocationTracking)
                                MaterialTheme.colorScheme.primary
                            else
                                MaterialTheme.colorScheme.outline
                        ) {
                            Text(
                                if (isLocationTracking) "ACTIVE" else "STANDBY",
                                modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp)
                            )
                        }
                    }

                    Spacer(Modifier.height(8.dp))
                    if (latestLocation != null) {
                        Text(
                            "Lat: ${"%.5f".format(latestLocation!!.latitude)}, Lng: ${"%.5f".format(latestLocation!!.longitude)}",
                            style = MaterialTheme.typography.bodyMedium
                        )
                        latestLocation!!.accuracy?.let {
                            Text("Accuracy: ±${"%.1f".format(it)}m", style = MaterialTheme.typography.bodySmall)
                        }
                        latestLocation!!.speed?.let {
                            Text("Speed: ${"%.1f".format(it * 3.6)} km/h", style = MaterialTheme.typography.bodySmall)
                        }
                    } else {
                        Text(
                            "Acquiring GPS signal...",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }

            if (state is ChildScreenState.Active) {
                Spacer(Modifier.height(24.dp))
                Text(
                    "Your parent is viewing your screen.",
                    style = MaterialTheme.typography.bodyLarge
                )
                Spacer(Modifier.height(12.dp))
                Button(onClick = onStop, colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.error
                )) {
                    Text("STOP SCREEN SHARING")
                }
            } else if (state is ChildScreenState.CameraActive) {
                Spacer(Modifier.height(24.dp))
                Text(
                    "Your parent is viewing your camera for safety verification.",
                    style = MaterialTheme.typography.bodyLarge
                )
                Spacer(Modifier.height(12.dp))
                Button(onClick = onStopCamera, colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.error
                )) {
                    Text("STOP CAMERA STREAM")
                }
            }
        }
    }

    // Mandatory, clearly visible consent prompt — screen sharing never starts automatically.
    if (state is ChildScreenState.ConsentRequested) {
        AlertDialog(
            onDismissRequest = { /* must explicitly choose Accept or Reject */ },
            title = { Text("Screen Share Request") },
            text = {
                Text(
                    "Your parent wants to view your screen.\n\n" +
                            "Screen sharing will start only after you approve."
                )
            },
            confirmButton = {
                TextButton(onClick = { onAccept(state.sessionId) }) { Text("Accept") }
            },
            dismissButton = {
                TextButton(onClick = { onReject(state.sessionId) }) { Text("Reject") }
            }
        )
    }

    if (showLogoutConfirm) {
        AlertDialog(
            onDismissRequest = { showLogoutConfirm = false },
            title = { Text("Log Out") },
            text = { Text("Are you sure you want to log out?") },
            confirmButton = {
                TextButton(onClick = {
                    showLogoutConfirm = false
                    onLogout()
                }) { Text("Log Out") }
            },
            dismissButton = {
                TextButton(onClick = { showLogoutConfirm = false }) { Text("Cancel") }
            }
        )
    }
}
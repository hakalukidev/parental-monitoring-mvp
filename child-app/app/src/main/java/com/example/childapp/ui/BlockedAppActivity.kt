package com.example.childapp.ui

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.HourglassTop
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.example.childapp.data.LocalDatabase
import com.example.childapp.socket.SocketManager

class BlockedAppActivity : ComponentActivity() {

    companion object {
        var activeSocketManager: SocketManager? = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Disable standard back press to prevent dropping back into the blocked foreground app
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                goToHomeScreen()
            }
        })

        val packageName = intent.getStringExtra("PACKAGE_NAME") ?: "Unknown App"
        val appName = intent.getStringExtra("APP_NAME") ?: packageName
        val reason = intent.getStringExtra("REASON") ?: "This application has been restricted by parental controls."

        setContent {
            MaterialTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    BlockedAppScreen(
                        appName = appName,
                        packageName = packageName,
                        reason = reason,
                        onRequestExtraTime = { customReason ->
                            val reqId = System.currentTimeMillis().toString()
                            activeSocketManager?.sendUnblockRequest(
                                requestId = reqId,
                                packageName = packageName,
                                appName = appName,
                                reason = customReason
                            )
                        },
                        onReturnHome = { goToHomeScreen() },
                        onApprovedLaunch = {
                            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                            if (launchIntent != null) {
                                startActivity(launchIntent)
                            }
                            finish()
                        }
                    )
                }
            }
        }
    }

    private fun goToHomeScreen() {
        val homeIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        startActivity(homeIntent)
        finish()
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BlockedAppScreen(
    appName: String,
    packageName: String,
    reason: String,
    onRequestExtraTime: (reason: String) -> Unit,
    onReturnHome: () -> Unit,
    onApprovedLaunch: () -> Unit
) {
    var showDialog by remember { mutableStateOf(false) }
    var selectedReason by remember { mutableStateOf("Need 15 more minutes for homework") }
    var requestStatus by remember { mutableStateOf<String?>(null) } // "PENDING", "APPROVED", "DECLINED"

    // Listen for real-time approval
    val context = androidx.compose.ui.platform.LocalContext.current
    LaunchedEffect(packageName) {
        val socket = BlockedAppActivity.activeSocketManager
        if (socket != null) {
            val originalHandler = socket.onUnblockResponse
            socket.onUnblockResponse = { reqId, pkg, approved, durationMinutes ->
                if (pkg == packageName) {
                    if (approved) {
                        LocalDatabase.getInstance(context)
                            .grantTemporaryUnblock(packageName, durationMinutes)
                        requestStatus = "APPROVED"
                    } else {
                        requestStatus = "DECLINED"
                    }
                }
                originalHandler?.invoke(reqId, pkg, approved, durationMinutes)
            }
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Box(
            modifier = Modifier
                .size(96.dp)
                .background(
                    color = MaterialTheme.colorScheme.errorContainer,
                    shape = RoundedCornerShape(48.dp)
                ),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.Filled.Block,
                contentDescription = "Blocked Icon",
                tint = MaterialTheme.colorScheme.error,
                modifier = Modifier.size(56.dp)
            )
        }

        Spacer(Modifier.height(24.dp))

        Text(
            text = "App Blocked",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onBackground
        )

        Spacer(Modifier.height(8.dp))

        Text(
            text = appName,
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.primary
        )

        Spacer(Modifier.height(16.dp))

        Card(
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceVariant
            ),
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(
                modifier = Modifier.padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    text = reason,
                    style = MaterialTheme.typography.bodyMedium,
                    textAlign = TextAlign.Center,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        Spacer(Modifier.height(24.dp))

        if (requestStatus == "PENDING") {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center,
                modifier = Modifier.fillMaxWidth()
            ) {
                CircularProgressIndicator(modifier = Modifier.size(24.dp))
                Spacer(Modifier.width(12.dp))
                Text(
                    "Request sent to parent. Waiting...",
                    style = MaterialTheme.typography.bodyMedium
                )
            }
            Spacer(Modifier.height(16.dp))
        } else if (requestStatus == "APPROVED") {
            Card(
                colors = CardDefaults.cardColors(containerColor = Color(0xFFE8F5E9)),
                modifier = Modifier.fillMaxWidth()
            ) {
                Row(
                    modifier = Modifier.padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = Color(0xFF2E7D32))
                    Spacer(Modifier.width(12.dp))
                    Text(
                        "Parent approved your request!",
                        color = Color(0xFF1B5E20),
                        fontWeight = FontWeight.Bold
                    )
                }
            }
            Spacer(Modifier.height(16.dp))
            Button(
                onClick = onApprovedLaunch,
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF2E7D32)),
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("Open $appName")
            }
            Spacer(Modifier.height(8.dp))
        } else if (requestStatus == "DECLINED") {
            Text(
                "Request was declined by your parent.",
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold
            )
            Spacer(Modifier.height(16.dp))
        }

        if (requestStatus != "APPROVED") {
            Button(
                onClick = { showDialog = true },
                enabled = requestStatus != "PENDING",
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(Icons.Filled.HourglassTop, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Request Extra Time / Unblock")
            }

            Spacer(Modifier.height(12.dp))

            OutlinedButton(
                onClick = onReturnHome,
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(Icons.Filled.Home, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Back to Home Screen")
            }
        }
    }

    if (showDialog) {
        AlertDialog(
            onDismissRequest = { showDialog = false },
            title = { Text("Request Extra Time") },
            text = {
                Column {
                    Text("Select a reason to send to your parent:")
                    Spacer(Modifier.height(8.dp))
                    val reasons = listOf(
                        "Need 15 more minutes for homework",
                        "Just 30 minutes to finish this project",
                        "Need to contact friends for school",
                        "Please allow for today"
                    )
                    for (r in reasons) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 4.dp)
                        ) {
                            RadioButton(
                                selected = selectedReason == r,
                                onClick = { selectedReason = r }
                            )
                            Spacer(Modifier.width(8.dp))
                            Text(r, style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        showDialog = false
                        requestStatus = "PENDING"
                        onRequestExtraTime(selectedReason)
                    }
                ) {
                    Text("Send Request")
                }
            },
            dismissButton = {
                TextButton(onClick = { showDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }
}

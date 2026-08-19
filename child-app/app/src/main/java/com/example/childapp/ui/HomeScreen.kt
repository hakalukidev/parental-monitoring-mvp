package com.example.childapp.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

sealed class ChildScreenState {
    object Idle : ChildScreenState()
    data class ConsentRequested(val sessionId: String) : ChildScreenState()
    data class Active(val sessionId: String) : ChildScreenState()
}

@Composable
fun HomeScreen(
    childName: String,
    parentName: String?,
    deviceConnected: Boolean,
    state: ChildScreenState,
    onAccept: (sessionId: String) -> Unit,
    onReject: (sessionId: String) -> Unit,
    onStop: () -> Unit
) {
    Scaffold { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
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
            Text("Screen Sharing:", style = MaterialTheme.typography.labelLarge)
            Text(
                when (state) {
                    is ChildScreenState.Active -> "Active"
                    is ChildScreenState.ConsentRequested -> "Request pending"
                    ChildScreenState.Idle -> "Inactive"
                }
            )

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
}

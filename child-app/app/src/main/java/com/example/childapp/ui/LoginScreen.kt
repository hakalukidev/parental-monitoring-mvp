package com.example.childapp.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp

@Composable
fun LoginScreen(loading: Boolean, error: String?, onLogin: (String, String) -> Unit) {
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var validation by remember { mutableStateOf<String?>(null) }
    Column(modifier = Modifier.fillMaxSize().safeDrawingPadding().imePadding().verticalScroll(rememberScrollState()).padding(28.dp), verticalArrangement = Arrangement.Center) {
        Text("SEFTLY CHILD", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
        Spacer(Modifier.height(24.dp))
        Text("Let’s connect.", style = MaterialTheme.typography.headlineLarge)
        Spacer(Modifier.height(12.dp))
        Text("Ask your parent to help you sign in with the child login they created.", style = MaterialTheme.typography.bodyLarge)
        Spacer(Modifier.height(28.dp))
        OutlinedTextField(value = username, onValueChange = { username = it; validation = null }, label = { Text("Child username") }, singleLine = true, enabled = !loading, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.height(16.dp))
        OutlinedTextField(value = password, onValueChange = { password = it; validation = null }, label = { Text("Password") }, visualTransformation = PasswordVisualTransformation(), singleLine = true, enabled = !loading, modifier = Modifier.fillMaxWidth())
        (validation ?: error)?.let { Spacer(Modifier.height(16.dp)); Text(it, color = MaterialTheme.colorScheme.error) }
        Spacer(Modifier.height(24.dp))
        Button(onClick = { if (username.trim().length < 3 || password.isBlank()) validation = "Enter your child username and password." else onLogin(username.trim(), password) }, enabled = !loading, modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp)) { Text(if (loading) "Connecting…" else "Connect with my family") }
        Spacer(Modifier.height(24.dp))
        Text("Screen and camera check-ins will always ask for your approval.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

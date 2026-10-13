package com.example.childapp.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

@Composable
fun SeftlyChildTheme(content: @Composable () -> Unit) {
    val colors = if (isSystemInDarkTheme()) darkColorScheme(primary = Color(0xFF93D8C4), primaryContainer = Color(0xFF174F42), onPrimaryContainer = Color(0xFFB8EFDB), secondary = Color(0xFFADC7DC))
        else lightColorScheme(primary = Color(0xFF176B5B), onPrimary = Color.White, primaryContainer = Color(0xFFDCEFE7), onPrimaryContainer = Color(0xFF103E32), secondary = Color(0xFF426585), background = Color(0xFFF5F7F5), surface = Color(0xFFFFFFFF), surfaceVariant = Color(0xFFE4ECE7), onSurfaceVariant = Color(0xFF52635B), onSurface = Color(0xFF192F2A))
    MaterialTheme(colorScheme = colors, content = content)
}

package com.example.childapp.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf

val LocalAppPalette = staticCompositionLocalOf { AppColors.Light }

private val LightColorScheme = lightColorScheme(
    primary = AppColors.Light.primary,
    onPrimary = AppColors.Light.primaryForeground,
    primaryContainer = AppColors.Light.accent,
    onPrimaryContainer = AppColors.Light.accentForeground,
    secondary = AppColors.Light.secondary,
    onSecondary = AppColors.Light.secondaryForeground,
    secondaryContainer = AppColors.Light.muted,
    onSecondaryContainer = AppColors.Light.mutedForeground,
    background = AppColors.Light.background,
    onBackground = AppColors.Light.foreground,
    surface = AppColors.Light.card,
    onSurface = AppColors.Light.cardForeground,
    surfaceVariant = AppColors.Light.card,
    onSurfaceVariant = AppColors.Light.mutedForeground,
    error = AppColors.Light.destructive,
    onError = AppColors.Light.primaryForeground,
    outline = AppColors.Light.border
)

private val DarkColorScheme = darkColorScheme(
    primary = AppColors.Dark.primary,
    onPrimary = AppColors.Dark.primaryForeground,
    primaryContainer = AppColors.Dark.accent,
    onPrimaryContainer = AppColors.Dark.accentForeground,
    secondary = AppColors.Dark.secondary,
    onSecondary = AppColors.Dark.secondaryForeground,
    secondaryContainer = AppColors.Dark.muted,
    onSecondaryContainer = AppColors.Dark.mutedForeground,
    background = AppColors.Dark.background,
    onBackground = AppColors.Dark.foreground,
    surface = AppColors.Dark.card,
    onSurface = AppColors.Dark.cardForeground,
    surfaceVariant = AppColors.Dark.card,
    onSurfaceVariant = AppColors.Dark.mutedForeground,
    error = AppColors.Dark.destructive,
    onError = AppColors.Dark.foreground,
    outline = AppColors.Dark.border
)

/**
 * Accessor for app-specific theme palette tokens
 */
object AppTheme {
    val palette: AppPalette
        @Composable
        @ReadOnlyComposable
        get() = LocalAppPalette.current
}

@Composable
fun ChildAppTheme(
    darkTheme: Boolean = false, // Not implementing dark mode for now, kept for future
    content: @Composable () -> Unit
) {
    val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme
    val palette = if (darkTheme) AppColors.Dark else AppColors.Light

    CompositionLocalProvider(LocalAppPalette provides palette) {
        MaterialTheme(
            colorScheme = colorScheme,
            content = content
        )
    }
}

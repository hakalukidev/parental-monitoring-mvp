package com.example.childapp.ui.theme

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Single source of truth for the Child App's color palette,
 * modeled after Next.js `index.css` CSS variables.
 *
 * Modifying colors here updates them across the entire app.
 */
data class AppPalette(
    val background: Color,
    val foreground: Color,
    val card: Color,
    val cardForeground: Color,
    val popover: Color,
    val popoverForeground: Color,
    val primary: Color,
    val primaryForeground: Color,
    val secondary: Color,
    val secondaryForeground: Color,
    val muted: Color,
    val mutedForeground: Color,
    val accent: Color,
    val accentForeground: Color,
    val destructive: Color,
    val border: Color,
    val input: Color,
    val ring: Color,
    val chart1: Color,
    val chart2: Color,
    val chart3: Color,
    val chart4: Color,
    val chart5: Color,
    val sidebar: Color,
    val sidebarForeground: Color,
    val sidebarPrimary: Color,
    val sidebarPrimaryForeground: Color,
    val sidebarAccent: Color,
    val sidebarAccentForeground: Color,
    val sidebarBorder: Color,
    val sidebarRing: Color,
    val radius: Dp = 10.dp
)

object AppColors {
    // Light palette (:root)
    val Light = AppPalette(
        background = Color(0xFFF5F7FA),
        foreground = Color(0xFF1A2238),
        card = Color(0xFFE3EAF2),
        cardForeground = Color(0xFF1A2238),
        popover = Color(0xFFFFFBE6),
        popoverForeground = Color(0xFF1A2238),
        primary = Color(0xFF3A5BA0),
        primaryForeground = Color(0xFFFFFBE6),
        secondary = Color(0xFFF7C873),
        secondaryForeground = Color(0xFF1A2238),
        muted = Color(0xFFE5E5DF),
        mutedForeground = Color(0xFF3A5BA0),
        accent = Color(0xFF6EA3C1),
        accentForeground = Color(0xFFFFFBE6),
        destructive = Color(0xFF2D1E2F),
        border = Color(0xFFB0B8C1),
        input = Color(0xFF6EA3C1),
        ring = Color(0xFFF7C873),
        chart1 = Color(0xFF3A5BA0),
        chart2 = Color(0xFFF7C873),
        chart3 = Color(0xFF6EA3C1),
        chart4 = Color(0xFFB0B8C1),
        chart5 = Color(0xFF2D1E2F),
        sidebar = Color(0xFFE3EAF2),
        sidebarForeground = Color(0xFF1A2238),
        sidebarPrimary = Color(0xFF3A5BA0),
        sidebarPrimaryForeground = Color(0xFFFFFBE6),
        sidebarAccent = Color(0xFFF7C873),
        sidebarAccentForeground = Color(0xFF1A2238),
        sidebarBorder = Color(0xFFB0B8C1),
        sidebarRing = Color(0xFFF7C873),
        radius = 10.dp
    )

    // Dark palette (.dark) - Kept ready for future use as requested
    val Dark = AppPalette(
        background = Color(0xFF181A24),
        foreground = Color(0xFFE6EAF3),
        card = Color(0xFF23243A),
        cardForeground = Color(0xFFE6EAF3),
        popover = Color(0xFF23243A),
        popoverForeground = Color(0xFFFFE066),
        primary = Color(0xFF3A5BA0),
        primaryForeground = Color(0xFFFFE066),
        secondary = Color(0xFFFFE066),
        secondaryForeground = Color(0xFF23243A),
        muted = Color(0xFF1D1E2F),
        mutedForeground = Color(0xFF7A88A1),
        accent = Color(0xFFBCCDF0),
        accentForeground = Color(0xFF181A24),
        destructive = Color(0xFFA04A6C),
        border = Color(0xFF2D2E3E),
        input = Color(0xFF3A5BA0),
        ring = Color(0xFFFFE066),
        chart1 = Color(0xFF3A5BA0),
        chart2 = Color(0xFFFFE066),
        chart3 = Color(0xFF6EA3C1),
        chart4 = Color(0xFF7A88A1),
        chart5 = Color(0xFFA04A6C),
        sidebar = Color(0xFF23243A),
        sidebarForeground = Color(0xFFE6EAF3),
        sidebarPrimary = Color(0xFF3A5BA0),
        sidebarPrimaryForeground = Color(0xFFFFE066),
        sidebarAccent = Color(0xFFFFE066),
        sidebarAccentForeground = Color(0xFF23243A),
        sidebarBorder = Color(0xFF2D2E3E),
        sidebarRing = Color(0xFFFFE066),
        radius = 10.dp
    )

    // Active palette (defaults to Light)
    val Current = Light
}

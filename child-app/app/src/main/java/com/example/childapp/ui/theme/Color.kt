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
        background = Color(0xFFFFFFFF),
        foreground = Color(0xFF0F1419),
        card = Color(0xFFF7F8F8),
        cardForeground = Color(0xFF2F4A9F),
        popover = Color(0xFFFFFFFF),
        popoverForeground = Color(0xFF2F4A9F),
        primary = Color(0xFF2F4A9F),
        primaryForeground = Color(0xFFFFFFFF),
        secondary = Color(0xFF0F1419),
        secondaryForeground = Color(0xFFFFFFFF),
        muted = Color(0xFFE5E5E6),
        mutedForeground = Color(0xFF0F1419),
        accent = Color(0xFFE3ECF6),
        accentForeground = Color(0xFF2F4A9F),
        destructive = Color(0xFFF4212E),
        border = Color(0xFFE1EAEF),
        input = Color(0xFFF7F9FA),
        ring = Color(0xFF2F4A9F),
        chart1 = Color(0xFF2F4A9F),
        chart2 = Color(0xFF00B87A),
        chart3 = Color(0xFFF7B928),
        chart4 = Color(0xFF17BF63),
        chart5 = Color(0xFFE0245E),
        sidebar = Color(0xFFF7F8F8),
        sidebarForeground = Color(0xFF0F1419),
        sidebarPrimary = Color(0xFF2F4A9F),
        sidebarPrimaryForeground = Color(0xFFFFFFFF),
        sidebarAccent = Color(0xFFE3ECF6),
        sidebarAccentForeground = Color(0xFF2F4A9F),
        sidebarBorder = Color(0xFFE1E8ED),
        sidebarRing = Color(0xFF2F4A9F),
        radius = 10.dp
    )

    // Dark palette (.dark) - Kept ready for future use as requested
    val Dark = AppPalette(
        background = Color(0xFF000000),
        foreground = Color(0xFFE7E9EA),
        card = Color(0xFF17181C),
        cardForeground = Color(0xFFD9D9D9),
        popover = Color(0xFF000000),
        popoverForeground = Color(0xFFE7E9EA),
        primary = Color(0xFF1C9CF0),
        primaryForeground = Color(0xFFFFFFFF),
        secondary = Color(0xFFF0F3F4),
        secondaryForeground = Color(0xFF0F1419),
        muted = Color(0xFF181818),
        mutedForeground = Color(0xFF72767A),
        accent = Color(0xFF061622),
        accentForeground = Color(0xFF1C9CF0),
        destructive = Color(0xFFF4212E),
        border = Color(0xFF242628),
        input = Color(0xFF22303C),
        ring = Color(0xFF1DA1F2),
        chart1 = Color(0xFF1E9DF1),
        chart2 = Color(0xFF00B87A),
        chart3 = Color(0xFFF7B928),
        chart4 = Color(0xFF17BF63),
        chart5 = Color(0xFFE0245E),
        sidebar = Color(0xFF17181C),
        sidebarForeground = Color(0xFFD9D9D9),
        sidebarPrimary = Color(0xFF1DA1F2),
        sidebarPrimaryForeground = Color(0xFFFFFFFF),
        sidebarAccent = Color(0xFF061622),
        sidebarAccentForeground = Color(0xFF1C9CF0),
        sidebarBorder = Color(0xFF38444D),
        sidebarRing = Color(0xFF1DA1F2),
        radius = 10.dp
    )

    // Active palette (defaults to Light)
    val Current = Light
}

import 'package:flutter/material.dart';

/// Single source of truth for the application's color theme,
/// structured like Next.js `index.css` CSS variables.
///
/// Modifying the color values here will reflect across the entire application.
class AppPalette {
  final Color background;
  final Color foreground;
  final Color card;
  final Color cardForeground;
  final Color popover;
  final Color popoverForeground;
  final Color primary;
  final Color primaryForeground;
  final Color secondary;
  final Color secondaryForeground;
  final Color muted;
  final Color mutedForeground;
  final Color accent;
  final Color accentForeground;
  final Color destructive;
  final Color border;
  final Color input;
  final Color ring;
  final Color chart1;
  final Color chart2;
  final Color chart3;
  final Color chart4;
  final Color chart5;
  final Color sidebar;
  final Color sidebarForeground;
  final Color sidebarPrimary;
  final Color sidebarPrimaryForeground;
  final Color sidebarAccent;
  final Color sidebarAccentForeground;
  final Color sidebarBorder;
  final Color sidebarRing;
  final double radius;

  const AppPalette({
    required this.background,
    required this.foreground,
    required this.card,
    required this.cardForeground,
    required this.popover,
    required this.popoverForeground,
    required this.primary,
    required this.primaryForeground,
    required this.secondary,
    required this.secondaryForeground,
    required this.muted,
    required this.mutedForeground,
    required this.accent,
    required this.accentForeground,
    required this.destructive,
    required this.border,
    required this.input,
    required this.ring,
    required this.chart1,
    required this.chart2,
    required this.chart3,
    required this.chart4,
    required this.chart5,
    required this.sidebar,
    required this.sidebarForeground,
    required this.sidebarPrimary,
    required this.sidebarPrimaryForeground,
    required this.sidebarAccent,
    required this.sidebarAccentForeground,
    required this.sidebarBorder,
    required this.sidebarRing,
    this.radius = 10.0,
  });
}

class AppColors {
  /// Light theme palette (:root)
  static const light = AppPalette(
    // --background: oklch(1.0000 0 0)
    background: Color(0xFFFFFFFF),
    // --foreground: oklch(0.1884 0.0128 248.5103)
    foreground: Color(0xFF0F1419),
    // --card: oklch(0.9784 0.0011 197.1387)
    card: Color(0xFFF7F8F8),
    // --card-foreground: oklch(0.438 0.142 267.074)
    cardForeground: Color(0xFF2F4A9F),
    // --popover: oklch(1.0000 0 0)
    popover: Color(0xFFFFFFFF),
    // --popover-foreground: oklch(0.438 0.142 267.074)
    popoverForeground: Color(0xFF2F4A9F),
    // --primary: oklch(0.438 0.142 267.074)
    primary: Color(0xFF2F4A9F),
    // --primary-foreground: oklch(1.0000 0 0)
    primaryForeground: Color(0xFFFFFFFF),
    // --secondary: oklch(0.188 0.013 248.51)
    secondary: Color(0xFF0F1419),
    // --secondary-foreground: oklch(1.0000 0 0)
    secondaryForeground: Color(0xFFFFFFFF),
    // --muted: oklch(0.9222 0.0013 286.3737)
    muted: Color(0xFFE5E5E6),
    // --muted-foreground: oklch(0.188 0.013 248.51)
    mutedForeground: Color(0xFF0F1419),
    // --accent: oklch(0.9392 0.0166 250.8453)
    accent: Color(0xFFE3ECF6),
    // --accent-foreground: oklch(0.438 0.142 267.074)
    accentForeground: Color(0xFF2F4A9F),
    // --destructive: oklch(0.6188 0.2376 25.7658)
    destructive: Color(0xFFF4212E),
    // --border: oklch(0.9317 0.0118 231.6594)
    border: Color(0xFFE1EAEF),
    // --input: oklch(0.9809 0.0025 228.7836)
    input: Color(0xFFF7F9FA),
    // --ring: oklch(0.6818 0.1584 243.3540)
    ring: Color(0xFF1DA1F2),
    // --chart-1
    chart1: Color(0xFF2F4A9F),
    // --chart-2
    chart2: Color(0xFF00B87A),
    // --chart-3
    chart3: Color(0xFFF7B928),
    // --chart-4
    chart4: Color(0xFF17BF63),
    // --chart-5
    chart5: Color(0xFFE0245E),
    // --sidebar
    sidebar: Color(0xFFF7F8F8),
    sidebarForeground: Color(0xFF0F1419),
    sidebarPrimary: Color(0xFF2F4A9F),
    sidebarPrimaryForeground: Color(0xFFFFFFFF),
    sidebarAccent: Color(0xFFE3ECF6),
    sidebarAccentForeground: Color(0xFF2F4A9F),
    sidebarBorder: Color(0xFFE1E8ED),
    sidebarRing: Color(0xFF2F4A9F),
    // --radius: 0.625rem
    radius: 10.0,
  );

  /// Dark theme palette (.dark) - Kept ready for future activation
  static const dark = AppPalette(
    // --background: oklch(0 0 0)
    background: Color(0xFF000000),
    // --foreground: oklch(0.9328 0.0025 228.7857)
    foreground: Color(0xFFE7E9EA),
    // --card: oklch(0.2097 0.0080 274.5332)
    card: Color(0xFF17181C),
    // --card-foreground: oklch(0.8853 0 0)
    cardForeground: Color(0xFFD9D9D9),
    // --popover: oklch(0 0 0)
    popover: Color(0xFF000000),
    // --popover-foreground: oklch(0.9328 0.0025 228.7857)
    popoverForeground: Color(0xFFE7E9EA),
    // --primary: oklch(0.6692 0.1607 245.0110)
    primary: Color(0xFF1C9CF0),
    // --primary-foreground: oklch(1.0000 0 0)
    primaryForeground: Color(0xFFFFFFFF),
    // --secondary: oklch(0.9622 0.0035 219.5331)
    secondary: Color(0xFFF0F3F4),
    // --secondary-foreground: oklch(0.1884 0.0128 248.5103)
    secondaryForeground: Color(0xFF0F1419),
    // --muted: oklch(0.2090 0 0)
    muted: Color(0xFF181818),
    // --muted-foreground: oklch(0.5637 0.0078 247.9662)
    mutedForeground: Color(0xFF72767A),
    // --accent: oklch(0.1928 0.0331 242.5459)
    accent: Color(0xFF061622),
    // --accent-foreground: oklch(0.6692 0.1607 245.0110)
    accentForeground: Color(0xFF1C9CF0),
    // --destructive: oklch(0.6188 0.2376 25.7658)
    destructive: Color(0xFFF4212E),
    // --border: oklch(0.2674 0.0047 248.0045)
    border: Color(0xFF242628),
    // --input: oklch(0.3020 0.0288 244.8244)
    input: Color(0xFF22303C),
    // --ring: oklch(0.6818 0.1584 243.3540)
    ring: Color(0xFF1DA1F2),
    // --chart-1
    chart1: Color(0xFF1E9DF1),
    // --chart-2
    chart2: Color(0xFF00B87A),
    // --chart-3
    chart3: Color(0xFFF7B928),
    // --chart-4
    chart4: Color(0xFF17BF63),
    // --chart-5
    chart5: Color(0xFFE0245E),
    // --sidebar
    sidebar: Color(0xFF17181C),
    sidebarForeground: Color(0xFFD9D9D9),
    sidebarPrimary: Color(0xFF1DA1F2),
    sidebarPrimaryForeground: Color(0xFFFFFFFF),
    sidebarAccent: Color(0xFF061622),
    sidebarAccentForeground: Color(0xFF1C9CF0),
    sidebarBorder: Color(0xFF38444D),
    sidebarRing: Color(0xFF1DA1F2),
    // --radius: 0.625rem
    radius: 10.0,
  );

  /// Active palette (defaults to light as requested)
  static AppPalette get current => light;

  // Direct CSS variable accessors (like var(--variable))
  static Color get background => current.background;
  static Color get foreground => current.foreground;
  static Color get card => current.card;
  static Color get cardForeground => current.cardForeground;
  static Color get popover => current.popover;
  static Color get popoverForeground => current.popoverForeground;
  static Color get primary => current.primary;
  static Color get primaryForeground => current.primaryForeground;
  static Color get secondary => current.secondary;
  static Color get secondaryForeground => current.secondaryForeground;
  static Color get muted => current.muted;
  static Color get mutedForeground => current.mutedForeground;
  static Color get accent => current.accent;
  static Color get accentForeground => current.accentForeground;
  static Color get destructive => current.destructive;
  static Color get border => current.border;
  static Color get input => current.input;
  static Color get ring => current.ring;
  static Color get chart1 => current.chart1;
  static Color get chart2 => current.chart2;
  static Color get chart3 => current.chart3;
  static Color get chart4 => current.chart4;
  static Color get chart5 => current.chart5;
  static Color get sidebar => current.sidebar;
  static Color get sidebarForeground => current.sidebarForeground;
  static Color get sidebarPrimary => current.sidebarPrimary;
  static Color get sidebarPrimaryForeground => current.sidebarPrimaryForeground;
  static Color get sidebarAccent => current.sidebarAccent;
  static Color get sidebarAccentForeground => current.sidebarAccentForeground;
  static Color get sidebarBorder => current.sidebarBorder;
  static Color get sidebarRing => current.sidebarRing;
  static double get radius => current.radius;
}

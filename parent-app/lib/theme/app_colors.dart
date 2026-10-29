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
    // --background: oklch(0.9755 0.0045 258.3245)
    background: Color(0xFFF5F7FA),
    // --foreground: oklch(0.2558 0.0433 268.0662)
    foreground: Color(0xFF1A2238),
    // --card: oklch(0.9341 0.0132 251.5628)
    card: Color(0xFFE3EAF2),
    // --card-foreground: oklch(0.2558 0.0433 268.0662)
    cardForeground: Color(0xFF1A2238),
    // --popover: oklch(0.9856 0.0278 98.0540)
    popover: Color(0xFFFFFBE6),
    // --popover-foreground: oklch(0.2558 0.0433 268.0662)
    popoverForeground: Color(0xFF1A2238),
    // --primary: oklch(0.4815 0.1178 263.3758)
    primary: Color(0xFF3A5BA0),
    // --primary-foreground: oklch(0.9856 0.0278 98.0540)
    primaryForeground: Color(0xFFFFFBE6),
    // --secondary: oklch(0.8567 0.1164 81.0092)
    secondary: Color(0xFFF7C873),
    // --secondary-foreground: oklch(0.2558 0.0433 268.0662)
    secondaryForeground: Color(0xFF1A2238),
    // --muted: oklch(0.9202 0.0080 106.5563)
    muted: Color(0xFFE5E5DF),
    // --muted-foreground: oklch(0.4815 0.1178 263.3758)
    mutedForeground: Color(0xFF3A5BA0),
    // --accent: oklch(0.6896 0.0714 234.0387)
    accent: Color(0xFF6EA3C1),
    // --accent-foreground: oklch(0.9856 0.0278 98.0540)
    accentForeground: Color(0xFFFFFBE6),
    // --destructive: oklch(0.2611 0.0376 322.5267)
    destructive: Color(0xFF2D1E2F),
    // --border: oklch(0.7791 0.0156 251.1926)
    border: Color(0xFFB0B8C1),
    // --input: oklch(0.6896 0.0714 234.0387)
    input: Color(0xFF6EA3C1),
    // --ring: oklch(0.8567 0.1164 81.0092)
    ring: Color(0xFFF7C873),
    // --chart-1
    chart1: Color(0xFF3A5BA0),
    // --chart-2
    chart2: Color(0xFFF7C873),
    // --chart-3
    chart3: Color(0xFF6EA3C1),
    // --chart-4
    chart4: Color(0xFFB0B8C1),
    // --chart-5
    chart5: Color(0xFF2D1E2F),
    // --sidebar
    sidebar: Color(0xFFE3EAF2),
    sidebarForeground: Color(0xFF1A2238),
    sidebarPrimary: Color(0xFF3A5BA0),
    sidebarPrimaryForeground: Color(0xFFFFFBE6),
    sidebarAccent: Color(0xFFF7C873),
    sidebarAccentForeground: Color(0xFF1A2238),
    sidebarBorder: Color(0xFFB0B8C1),
    sidebarRing: Color(0xFFF7C873),
    // --radius: 0.625rem
    radius: 10.0,
  );

  /// Dark theme palette (.dark) - Kept ready for future activation
  static const dark = AppPalette(
    // --background: oklch(0.2204 0.0198 275.8439)
    background: Color(0xFF181A24),
    // --foreground: oklch(0.9366 0.0129 266.6974)
    foreground: Color(0xFFE6EAF3),
    // --card: oklch(0.2703 0.0407 281.3036)
    card: Color(0xFF23243A),
    // --card-foreground: oklch(0.9366 0.0129 266.6974)
    cardForeground: Color(0xFFE6EAF3),
    // --popover: oklch(0.2703 0.0407 281.3036)
    popover: Color(0xFF23243A),
    // --popover-foreground: oklch(0.9097 0.1440 95.1120)
    popoverForeground: Color(0xFFFFE066),
    // --primary: oklch(0.4815 0.1178 263.3758)
    primary: Color(0xFF3A5BA0),
    // --primary-foreground: oklch(0.9097 0.1440 95.1120)
    primaryForeground: Color(0xFFFFE066),
    // --secondary: oklch(0.9097 0.1440 95.1120)
    secondary: Color(0xFFFFE066),
    // --secondary-foreground: oklch(0.2703 0.0407 281.3036)
    secondaryForeground: Color(0xFF23243A),
    // --muted: oklch(0.2424 0.0324 281.0890)
    muted: Color(0xFF1D1E2F),
    // --muted-foreground: oklch(0.6243 0.0412 262.0375)
    mutedForeground: Color(0xFF7A88A1),
    // --accent: oklch(0.8469 0.0524 264.7751)
    accent: Color(0xFFBCCDF0),
    // --accent-foreground: oklch(0.2204 0.0198 275.8439)
    accentForeground: Color(0xFF181A24),
    // --destructive: oklch(0.5280 0.1200 357.1130)
    destructive: Color(0xFFA04A6C),
    // --border: oklch(0.3072 0.0287 281.7681)
    border: Color(0xFF2D2E3E),
    // --input: oklch(0.4815 0.1178 263.3758)
    input: Color(0xFF3A5BA0),
    // --ring: oklch(0.9097 0.1440 95.1120)
    ring: Color(0xFFFFE066),
    // --chart-1
    chart1: Color(0xFF3A5BA0),
    // --chart-2
    chart2: Color(0xFFFFE066),
    // --chart-3
    chart3: Color(0xFF6EA3C1),
    // --chart-4
    chart4: Color(0xFF7A88A1),
    // --chart-5
    chart5: Color(0xFFA04A6C),
    // --sidebar
    sidebar: Color(0xFF23243A),
    sidebarForeground: Color(0xFFE6EAF3),
    sidebarPrimary: Color(0xFF3A5BA0),
    sidebarPrimaryForeground: Color(0xFFFFE066),
    sidebarAccent: Color(0xFFFFE066),
    sidebarAccentForeground: Color(0xFF23243A),
    sidebarBorder: Color(0xFF2D2E3E),
    sidebarRing: Color(0xFFFFE066),
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

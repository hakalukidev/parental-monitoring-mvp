import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MostUsedAppInfo {
  final String packageName;
  final String appName;
  final String category;
  final int foregroundTimeSeconds;

  MostUsedAppInfo({
    required this.packageName,
    required this.appName,
    required this.category,
    required this.foregroundTimeSeconds,
  });

  factory MostUsedAppInfo.fromJson(Map<String, dynamic> json) {
    return MostUsedAppInfo(
      packageName: json['packageName'] as String? ?? '',
      appName: json['appName'] as String? ?? 'App',
      category: json['category'] as String? ?? 'OTHER',
      foregroundTimeSeconds:
          (json['foregroundTimeSeconds'] as num?)?.toInt() ?? 0,
    );
  }

  String get formattedUsage {
    final hours = foregroundTimeSeconds ~/ 3600;
    final minutes = (foregroundTimeSeconds % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m';
    return '${foregroundTimeSeconds}s';
  }
}

class UsageSummary {
  final int totalScreenTimeSeconds;
  final int? totalDowntimeSeconds;
  final int? screenOffTimeSeconds;
  final bool isDevicePaused;
  final bool usageAvailable;
  final String? activeScheduleDowntime;
  final int blockedAttemptsCount;
  final int limitsReachedCount;
  final int totalAppsTracked;
  final int appsWithUsageCount;
  final MostUsedAppInfo? mostUsedApp;

  UsageSummary({
    required this.totalScreenTimeSeconds,
    required this.totalDowntimeSeconds,
    required this.screenOffTimeSeconds,
    required this.isDevicePaused,
    this.usageAvailable = false,
    this.activeScheduleDowntime,
    required this.blockedAttemptsCount,
    required this.limitsReachedCount,
    required this.totalAppsTracked,
    required this.appsWithUsageCount,
    this.mostUsedApp,
  });

  factory UsageSummary.fromJson(Map<String, dynamic> json) {
    return UsageSummary(
      totalScreenTimeSeconds:
          (json['totalScreenTimeSeconds'] as num?)?.toInt() ?? 0,
      totalDowntimeSeconds: (json['totalDowntimeSeconds'] as num?)?.toInt(),
      screenOffTimeSeconds: (json['screenOffTimeSeconds'] as num?)?.toInt(),
      isDevicePaused: json['isDevicePaused'] as bool? ?? false,
      usageAvailable: json['usageAvailable'] as bool? ?? false,
      activeScheduleDowntime: json['activeScheduleDowntime'] as String?,
      blockedAttemptsCount:
          (json['blockedAttemptsCount'] as num?)?.toInt() ?? 0,
      limitsReachedCount: (json['limitsReachedCount'] as num?)?.toInt() ?? 0,
      totalAppsTracked: (json['totalAppsTracked'] as num?)?.toInt() ?? 0,
      appsWithUsageCount: (json['appsWithUsageCount'] as num?)?.toInt() ?? 0,
      mostUsedApp: json['mostUsedApp'] != null
          ? MostUsedAppInfo.fromJson(
              json['mostUsedApp'] as Map<String, dynamic>)
          : null,
    );
  }

  String get formattedScreenTime {
    if (!usageAvailable) return "Unavailable";
    final hours = totalScreenTimeSeconds ~/ 3600;
    final minutes = (totalScreenTimeSeconds % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m';
    if (totalScreenTimeSeconds > 0) return '${totalScreenTimeSeconds}s';
    return '0m';
  }

  static String duration(int? seconds) {
    if (seconds == null) return 'Unavailable';
    final hours = seconds ~/ 3600, minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m';
    return '${seconds}s';
  }

  String get formattedDowntime => duration(totalDowntimeSeconds);
  String get formattedScreenOff => duration(screenOffTimeSeconds);
}

class CategoryUsage {
  final String category;
  final int totalTimeSeconds;
  final int percentage;

  CategoryUsage({
    required this.category,
    required this.totalTimeSeconds,
    required this.percentage,
  });

  factory CategoryUsage.fromJson(Map<String, dynamic> json) {
    return CategoryUsage(
      category: json['category'] as String? ?? 'OTHER',
      totalTimeSeconds: (json['totalTimeSeconds'] as num?)?.toInt() ?? 0,
      percentage: (json['percentage'] as num?)?.toInt() ?? 0,
    );
  }

  String get formattedTime {
    final hours = totalTimeSeconds ~/ 3600;
    final minutes = (totalTimeSeconds % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m';
    if (totalTimeSeconds > 0) return '${totalTimeSeconds}s';
    return '0m';
  }

  IconData get iconData {
    switch (category.toUpperCase()) {
      case 'GAME':
        return Icons.sports_esports;
      case 'SOCIAL':
        return Icons.people;
      case 'ENTERTAINMENT':
        return Icons.movie;
      case 'EDUCATION':
        return Icons.school;
      case 'PRODUCTIVITY':
        return Icons.work;
      default:
        return Icons.apps;
    }
  }

  Color get color {
    switch (category.toUpperCase()) {
      case 'GAME':
        return Colors.deepPurple;
      case 'SOCIAL':
        return Colors.blue;
      case 'ENTERTAINMENT':
        return Colors.amber.shade800;
      case 'EDUCATION':
        return Colors.teal;
      case 'PRODUCTIVITY':
        return Colors.indigo;
      default:
        return Colors.blueGrey;
    }
  }
}

class HourlyUsage {
  final int hour;
  final int screenTimeSeconds;

  HourlyUsage({
    required this.hour,
    required this.screenTimeSeconds,
  });

  factory HourlyUsage.fromJson(Map<String, dynamic> json) {
    return HourlyUsage(
      hour: (json['hour'] as num?)?.toInt() ?? 0,
      screenTimeSeconds: (json['screenTimeSeconds'] as num?)?.toInt() ?? 0,
    );
  }

  String get formattedHour {
    if (hour == 0) return '12 AM';
    if (hour < 12) return '$hour AM';
    if (hour == 12) return '12 PM';
    return '${hour - 12} PM';
  }

  int get screenTimeMinutes => screenTimeSeconds ~/ 60;
}

class AppUsageItem {
  final String packageName;
  final String? iconPngBase64;
  final String appName;
  final String category;
  final int foregroundTimeSeconds;
  final DateTime? lastTimeUsed;
  final int launchCount;
  final String status;
  final int? dailyLimitMinutes;
  final bool isSystemApp;

  AppUsageItem({
    required this.packageName,
    this.iconPngBase64,
    required this.appName,
    required this.category,
    required this.foregroundTimeSeconds,
    this.lastTimeUsed,
    required this.launchCount,
    required this.status,
    this.dailyLimitMinutes,
    required this.isSystemApp,
  });

  factory AppUsageItem.fromJson(Map<String, dynamic> json) {
    DateTime? lastUsed;
    if (json['lastTimeUsed'] != null) {
      lastUsed = DateTime.tryParse(json['lastTimeUsed'].toString());
    }
    return AppUsageItem(
      packageName: json['packageName'] as String? ?? '',
      iconPngBase64: json['iconPngBase64'] as String?,
      appName: json['appName'] as String? ?? 'App',
      category: json['category'] as String? ?? 'OTHER',
      foregroundTimeSeconds:
          (json['foregroundTimeSeconds'] as num?)?.toInt() ?? 0,
      lastTimeUsed: lastUsed,
      launchCount: (json['launchCount'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'ALWAYS_ALLOWED',
      dailyLimitMinutes: (json['dailyLimitMinutes'] as num?)?.toInt(),
      isSystemApp: json['isSystemApp'] as bool? ?? false,
    );
  }

  String get formattedUsageTime {
    final hours = foregroundTimeSeconds ~/ 3600;
    final minutes = (foregroundTimeSeconds % 3600) ~/ 60;
    final seconds = foregroundTimeSeconds % 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m';
    if (seconds > 0) return '${seconds}s';
    return '0m';
  }

  String get formattedLastUsed {
    if (lastTimeUsed == null) return 'No opening reported';
    final diff = DateTime.now().difference(lastTimeUsed!.toLocal());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) {
      return DateFormat('h:mm a').format(lastTimeUsed!.toLocal());
    }
    return DateFormat('MMM d, h:mm a').format(lastTimeUsed!.toLocal());
  }

  bool get isLimitExceeded {
    if (dailyLimitMinutes == null || dailyLimitMinutes! <= 0) return false;
    return foregroundTimeSeconds >= (dailyLimitMinutes! * 60);
  }
}

class AppUsageReport {
  final String date;
  final String timeZone;
  final String childId;
  final DateTime? lastSyncedAt;
  final UsageSummary summary;
  final List<CategoryUsage> categoryBreakdown;
  final List<HourlyUsage> hourlyUsage;
  final List<AppUsageItem> apps;

  AppUsageReport({
    required this.date,
    this.timeZone = "UTC",
    required this.childId,
    required this.lastSyncedAt,
    required this.summary,
    required this.categoryBreakdown,
    required this.hourlyUsage,
    required this.apps,
  });

  factory AppUsageReport.fromJson(Map<String, dynamic> json) {
    final summaryRaw = json['summary'] as Map<String, dynamic>? ?? {};
    final categoryList = (json['categoryBreakdown'] as List<dynamic>?) ?? [];
    final hourlyList = (json['hourlyUsage'] as List<dynamic>?) ?? [];
    final appsList = (json['apps'] as List<dynamic>?) ?? [];

    DateTime? syncedAt;
    if (json['lastSyncedAt'] != null) {
      syncedAt = DateTime.tryParse(json['lastSyncedAt'].toString());
    }

    return AppUsageReport(
      date: json['date'] as String? ?? '',
      timeZone: json['timeZone'] as String? ?? 'UTC',
      childId: json['childId'] as String? ?? '',
      lastSyncedAt: syncedAt,
      summary: UsageSummary.fromJson(summaryRaw),
      categoryBreakdown: categoryList
          .map((e) => CategoryUsage.fromJson(e as Map<String, dynamic>))
          .toList(),
      hourlyUsage: hourlyList
          .map((e) => HourlyUsage.fromJson(e as Map<String, dynamic>))
          .toList(),
      apps: appsList
          .map((e) => AppUsageItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

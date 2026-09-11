class AppSchedule {
  final List<int> daysOfWeek;
  final String startTime;
  final String endTime;

  AppSchedule({
    required this.daysOfWeek,
    required this.startTime,
    required this.endTime,
  });

  factory AppSchedule.fromJson(Map<String, dynamic> json) {
    return AppSchedule(
      daysOfWeek: (json['daysOfWeek'] as List<dynamic>?)?.map((e) => e as int).toList() ?? [],
      startTime: json['startTime'] as String? ?? '00:00',
      endTime: json['endTime'] as String? ?? '00:00',
    );
  }

  Map<String, dynamic> toJson() => {
        'daysOfWeek': daysOfWeek,
        'startTime': startTime,
        'endTime': endTime,
      };
}

class InstalledAppInfo {
  final String packageName;
  final String appName;
  final String category;
  String status; // 'ALWAYS_ALLOWED', 'BLOCKED', 'TIME_LIMITED', 'SCHEDULED'
  int? dailyLimitMinutes;
  List<AppSchedule> schedules;
  final bool isSystemWhitelisted;
  final String? versionName;
  final DateTime? syncedAt;

  InstalledAppInfo({
    required this.packageName,
    required this.appName,
    required this.category,
    required this.status,
    this.dailyLimitMinutes,
    this.schedules = const [],
    this.isSystemWhitelisted = false,
    this.versionName,
    this.syncedAt,
  });

  factory InstalledAppInfo.fromJson(Map<String, dynamic> json) {
    return InstalledAppInfo(
      packageName: json['packageName'] as String? ?? '',
      appName: json['appName'] as String? ?? json['packageName'] ?? '',
      category: json['category'] as String? ?? 'OTHER',
      status: json['status'] as String? ?? 'ALWAYS_ALLOWED',
      dailyLimitMinutes: json['dailyLimitMinutes'] as int?,
      schedules: (json['schedules'] as List<dynamic>?)
              ?.map((e) => AppSchedule.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      isSystemWhitelisted: json['isSystemWhitelisted'] as bool? ?? false,
      versionName: json['versionName'] as String?,
      syncedAt: json['syncedAt'] != null ? DateTime.tryParse(json['syncedAt']) : null,
    );
  }

  Map<String, dynamic> toPolicyJson() => {
        'appName': appName,
        'category': category,
        'status': status,
        if (dailyLimitMinutes != null) 'dailyLimitMinutes': dailyLimitMinutes,
        'schedules': schedules.map((s) => s.toJson()).toList(),
        'isSystemWhitelisted': isSystemWhitelisted,
      };
}

class WebBlockRule {
  final String id;
  final String ruleType; // 'DOMAIN', 'KEYWORD', 'CATEGORY'
  final String target;
  String action; // 'BLOCK', 'ALLOW'
  bool isEnabled;

  WebBlockRule({
    required this.id,
    required this.ruleType,
    required this.target,
    this.action = 'BLOCK',
    this.isEnabled = true,
  });

  factory WebBlockRule.fromJson(Map<String, dynamic> json) {
    return WebBlockRule(
      id: json['_id'] as String? ?? json['id'] as String? ?? '',
      ruleType: json['ruleType'] as String? ?? 'DOMAIN',
      target: json['target'] as String? ?? '',
      action: json['action'] as String? ?? 'BLOCK',
      isEnabled: json['isEnabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'ruleType': ruleType,
        'target': target,
        'action': action,
        'isEnabled': isEnabled,
      };
}

class BrowsingHistoryRecord {
  final String id;
  final String url;
  final String domain;
  final String title;
  final String browser;
  final bool isIncognito;
  final String category;
  final bool isBlockedAttempt;
  final String? blockedReason;
  final DateTime visitedAt;

  BrowsingHistoryRecord({
    required this.id,
    required this.url,
    required this.domain,
    required this.title,
    required this.browser,
    required this.isIncognito,
    required this.category,
    required this.isBlockedAttempt,
    this.blockedReason,
    required this.visitedAt,
  });

  factory BrowsingHistoryRecord.fromJson(Map<String, dynamic> json) {
    return BrowsingHistoryRecord(
      id: json['_id'] as String? ?? json['id'] as String? ?? '',
      url: json['url'] as String? ?? '',
      domain: json['domain'] as String? ?? '',
      title: json['title'] as String? ?? json['domain'] ?? '',
      browser: json['browser'] as String? ?? 'OTHER',
      isIncognito: json['isIncognito'] as bool? ?? false,
      category: json['category'] as String? ?? 'GENERAL',
      isBlockedAttempt: json['isBlockedAttempt'] as bool? ?? false,
      blockedReason: json['blockedReason'] as String?,
      visitedAt: json['visitedAt'] != null
          ? DateTime.tryParse(json['visitedAt'] as String)?.toLocal() ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class TopDomain {
  final String domain;
  final int count;
  final int percentage;

  TopDomain({required this.domain, required this.count, required this.percentage});

  factory TopDomain.fromJson(Map<String, dynamic> json) {
    return TopDomain(
      domain: json['domain'] as String? ?? '',
      count: json['count'] as int? ?? 0,
      percentage: json['percentage'] as int? ?? 0,
    );
  }
}

class BrowsingAnalytics {
  final int totalVisited;
  final int blockedAttempts;
  final List<TopDomain> topDomains;
  final Map<String, int> categoryDistribution;

  BrowsingAnalytics({
    required this.totalVisited,
    required this.blockedAttempts,
    required this.topDomains,
    required this.categoryDistribution,
  });

  factory BrowsingAnalytics.fromJson(Map<String, dynamic> json) {
    return BrowsingAnalytics(
      totalVisited: json['totalVisited'] as int? ?? 0,
      blockedAttempts: json['blockedAttempts'] as int? ?? 0,
      topDomains: (json['topDomains'] as List<dynamic>?)
              ?.map((e) => TopDomain.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      categoryDistribution: (json['categoryDistribution'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v as num).toInt())) ??
          {},
    );
  }
}

class UnblockRequest {
  final String requestId;
  final String childId;
  final String childName;
  final String packageName;
  final String appName;
  final String reason;
  final DateTime requestedAt;

  UnblockRequest({
    required this.requestId,
    required this.childId,
    required this.childName,
    required this.packageName,
    required this.appName,
    required this.reason,
    required this.requestedAt,
  });

  factory UnblockRequest.fromJson(Map<String, dynamic> json) {
    return UnblockRequest(
      requestId: json['requestId'] as String? ?? '',
      childId: json['childId'] as String? ?? '',
      childName: json['childName'] as String? ?? 'Child',
      packageName: json['packageName'] as String? ?? '',
      appName: json['appName'] as String? ?? json['packageName'] ?? '',
      reason: json['reason'] as String? ?? 'Need extra time',
      requestedAt: json['requestedAt'] != null
          ? DateTime.tryParse(json['requestedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

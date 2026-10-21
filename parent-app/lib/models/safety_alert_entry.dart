enum SafetySeverity {
  critical,
  high,
  medium;

  static SafetySeverity fromString(String? val) {
    switch (val?.toUpperCase()) {
      case 'CRITICAL':
        return SafetySeverity.critical;
      case 'HIGH':
        return SafetySeverity.high;
      default:
        return SafetySeverity.medium;
    }
  }

  String get displayName {
    switch (this) {
      case SafetySeverity.critical:
        return 'Critical';
      case SafetySeverity.high:
        return 'High';
      case SafetySeverity.medium:
        return 'Medium';
    }
  }
}

class SafetyAlertEntry {
  final String id;
  final String alertType;
  final String? packageName;
  final String? appName;
  final double confidenceScore;
  final SafetySeverity severity;
  final bool isAcknowledged;
  final DateTime? acknowledgedAt;
  final DateTime timestamp;

  const SafetyAlertEntry({
    required this.id,
    required this.alertType,
    this.packageName,
    this.appName,
    required this.confidenceScore,
    required this.severity,
    required this.isAcknowledged,
    this.acknowledgedAt,
    required this.timestamp,
  });

  factory SafetyAlertEntry.fromJson(Map<String, dynamic> json) {
    return SafetyAlertEntry(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      alertType: json['alertType'] as String? ?? 'EXPLICIT_CONTENT',
      packageName: json['packageName'] as String?,
      appName: json['appName'] as String?,
      confidenceScore: (json['confidenceScore'] as num?)?.toDouble() ?? 0.0,
      severity: SafetySeverity.fromString(json['severity'] as String?),
      isAcknowledged: json['isAcknowledged'] == true,
      acknowledgedAt: json['acknowledgedAt'] != null
          ? DateTime.tryParse(json['acknowledgedAt'].toString())?.toLocal()
          : null,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString())?.toLocal() ?? DateTime.now()
          : DateTime.now(),
    );
  }

  String get alertTitle {
    switch (alertType) {
      case 'EXPLICIT_SCREEN_CONTENT':
        return 'Inappropriate Screen Content';
      case 'EXPLICIT_PHOTO_SAVED':
        return 'Inappropriate Photo Saved/Downloaded';
      case 'ADULT_CONTENT_DETECTED':
        return 'Adult Content Detected';
      default:
        return 'Content Safety Violation';
    }
  }
}

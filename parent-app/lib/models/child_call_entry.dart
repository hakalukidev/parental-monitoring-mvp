enum CallDirection {
  incoming,
  outgoing,
  missed,
  rejected,
  unknown;

  static CallDirection fromString(String? val) {
    switch (val?.toUpperCase()) {
      case 'INCOMING':
        return CallDirection.incoming;
      case 'OUTGOING':
        return CallDirection.outgoing;
      case 'MISSED':
        return CallDirection.missed;
      case 'REJECTED':
        return CallDirection.rejected;
      default:
        return CallDirection.unknown;
    }
  }

  String get displayName {
    switch (this) {
      case CallDirection.incoming:
        return 'Incoming';
      case CallDirection.outgoing:
        return 'Outgoing';
      case CallDirection.missed:
        return 'Missed';
      case CallDirection.rejected:
        return 'Rejected';
      case CallDirection.unknown:
        return 'Unknown';
    }
  }
}

class ChildCallEntry {
  final String id;
  final String? phoneNumber;
  final String? contactName;
  final CallDirection direction;
  final int durationSeconds;
  final DateTime timestamp;
  final String? childDeviceId;

  const ChildCallEntry({
    required this.id,
    this.phoneNumber,
    this.contactName,
    required this.direction,
    required this.durationSeconds,
    required this.timestamp,
    this.childDeviceId,
  });

  factory ChildCallEntry.fromJson(Map<String, dynamic> json) {
    return ChildCallEntry(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      phoneNumber: json['phoneNumber'] as String?,
      contactName: json['contactName'] as String?,
      direction: CallDirection.fromString(json['direction'] as String?),
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString())?.toLocal() ?? DateTime.now()
          : DateTime.now(),
      childDeviceId: json['deviceId']?.toString(),
    );
  }

  String get formattedDuration {
    if (durationSeconds <= 0) return '0s';
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    if (minutes == 0) return '${seconds}s';
    return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }
}

enum SmsDirection {
  incoming,
  outgoing,
  unknown;

  static SmsDirection fromString(String? val) {
    switch (val?.toUpperCase()) {
      case 'INCOMING':
        return SmsDirection.incoming;
      case 'OUTGOING':
        return SmsDirection.outgoing;
      default:
        return SmsDirection.unknown;
    }
  }

  String get displayName {
    switch (this) {
      case SmsDirection.incoming:
        return 'Incoming';
      case SmsDirection.outgoing:
        return 'Outgoing';
      case SmsDirection.unknown:
        return 'Unknown';
    }
  }
}

class ChildSmsEntry {
  final String id;
  final String? phoneNumber;
  final String? contactName;
  final SmsDirection direction;
  final String? body;
  final bool hasBody;
  final DateTime timestamp;
  final String? childDeviceId;

  const ChildSmsEntry({
    required this.id,
    this.phoneNumber,
    this.contactName,
    required this.direction,
    this.body,
    required this.hasBody,
    required this.timestamp,
    this.childDeviceId,
  });

  factory ChildSmsEntry.fromJson(Map<String, dynamic> json) {
    return ChildSmsEntry(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      phoneNumber: json['phoneNumber'] as String?,
      contactName: json['contactName'] as String?,
      direction: SmsDirection.fromString(json['direction'] as String?),
      body: json['body'] as String?,
      hasBody: (json['hasBody'] as bool?) ?? (json['body'] != null),
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString())?.toLocal() ?? DateTime.now()
          : DateTime.now(),
      childDeviceId: json['deviceId']?.toString(),
    );
  }
}

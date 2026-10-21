enum CapabilityStatus {
  available,
  permissionRequired,
  permissionDenied,
  restrictedByOs,
  disabled,
  unsupported;

  static CapabilityStatus fromString(String? val) {
    switch (val?.toUpperCase()) {
      case 'AVAILABLE':
        return CapabilityStatus.available;
      case 'PERMISSION_REQUIRED':
        return CapabilityStatus.permissionRequired;
      case 'PERMISSION_DENIED':
        return CapabilityStatus.permissionDenied;
      case 'RESTRICTED_BY_OS':
        return CapabilityStatus.restrictedByOs;
      case 'DISABLED':
        return CapabilityStatus.disabled;
      default:
        return CapabilityStatus.unsupported;
    }
  }

  bool get isAvailable => this == CapabilityStatus.available;
}

class CommunicationCapability {
  final CapabilityStatus callsStatus;
  final CapabilityStatus smsMetadataStatus;
  final CapabilityStatus smsContentStatus;
  final DateTime? updatedAt;

  const CommunicationCapability({
    required this.callsStatus,
    required this.smsMetadataStatus,
    required this.smsContentStatus,
    this.updatedAt,
  });

  factory CommunicationCapability.fromJson(Map<String, dynamic> json) {
    return CommunicationCapability(
      callsStatus: CapabilityStatus.fromString(json['callsStatus'] as String?),
      smsMetadataStatus: CapabilityStatus.fromString(json['smsMetadataStatus'] as String?),
      smsContentStatus: CapabilityStatus.fromString(json['smsContentStatus'] as String?),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString())?.toLocal()
          : null,
    );
  }

  factory CommunicationCapability.defaultInitial() {
    return const CommunicationCapability(
      callsStatus: CapabilityStatus.permissionRequired,
      smsMetadataStatus: CapabilityStatus.permissionRequired,
      smsContentStatus: CapabilityStatus.permissionRequired,
    );
  }
}

import 'package:latlong2/latlong.dart';

enum GeofenceZoneType {
  safeZone,
  restrictedZone;

  String toApiValue() => this == GeofenceZoneType.safeZone ? 'SAFE_ZONE' : 'RESTRICTED_ZONE';

  static GeofenceZoneType fromString(String val) {
    return val == 'RESTRICTED_ZONE' ? GeofenceZoneType.restrictedZone : GeofenceZoneType.safeZone;
  }
}

enum GeofenceTriggerType {
  exit,
  entry,
  both;

  String toApiValue() {
    switch (this) {
      case GeofenceTriggerType.exit:
        return 'EXIT';
      case GeofenceTriggerType.entry:
        return 'ENTRY';
      case GeofenceTriggerType.both:
        return 'BOTH';
    }
  }

  static GeofenceTriggerType fromString(String val) {
    switch (val) {
      case 'ENTRY':
        return GeofenceTriggerType.entry;
      case 'BOTH':
        return GeofenceTriggerType.both;
      case 'EXIT':
      default:
        return GeofenceTriggerType.exit;
    }
  }
}

class GeofenceSchedule {
  final List<int> daysOfWeek; // 0 = Sun, 1 = Mon ... 6 = Sat
  final String? startTime; // "08:00"
  final String? endTime; // "15:00"

  GeofenceSchedule({
    this.daysOfWeek = const [0, 1, 2, 3, 4, 5, 6],
    this.startTime,
    this.endTime,
  });

  factory GeofenceSchedule.fromJson(Map<String, dynamic> json) {
    return GeofenceSchedule(
      daysOfWeek: (json['daysOfWeek'] as List<dynamic>?)?.map((e) => (e as num).toInt()).toList() ??
          const [0, 1, 2, 3, 4, 5, 6],
      startTime: json['startTime'] as String?,
      endTime: json['endTime'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'daysOfWeek': daysOfWeek,
      if (startTime != null) 'startTime': startTime,
      if (endTime != null) 'endTime': endTime,
    };
  }
}

class Geofence {
  final String id;
  final String parentId;
  final String childId;
  final String name;
  final double latitude;
  final double longitude;
  final double radius; // meters
  final String address;
  final GeofenceZoneType zoneType;
  final GeofenceTriggerType triggerType;
  final bool isEnabled;
  final String colorHex;
  final String lastState;
  final DateTime? lastStateChangedAt;
  final DateTime? lastTriggeredAt;
  final GeofenceSchedule? schedule;
  final DateTime createdAt;

  Geofence({
    required this.id,
    required this.parentId,
    required this.childId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radius,
    this.address = '',
    this.zoneType = GeofenceZoneType.safeZone,
    this.triggerType = GeofenceTriggerType.exit,
    this.isEnabled = true,
    this.colorHex = '#2196F3',
    this.lastState = 'UNKNOWN',
    this.lastStateChangedAt,
    this.lastTriggeredAt,
    this.schedule,
    required this.createdAt,
  });

  LatLng get latLng => LatLng(latitude, longitude);

  factory Geofence.fromJson(Map<String, dynamic> json) {
    return Geofence(
      id: (json['_id'] ?? json['id']).toString(),
      parentId: (json['parentId'] ?? '').toString(),
      childId: (json['childId'] ?? '').toString(),
      name: json['name'] as String? ?? 'Unnamed Zone',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      radius: (json['radius'] as num?)?.toDouble() ?? 200.0,
      address: json['address'] as String? ?? '',
      zoneType: GeofenceZoneType.fromString(json['zoneType'] as String? ?? 'SAFE_ZONE'),
      triggerType: GeofenceTriggerType.fromString(json['triggerType'] as String? ?? 'EXIT'),
      isEnabled: json['isEnabled'] as bool? ?? true,
      colorHex: json['colorHex'] as String? ?? '#2196F3',
      lastState: json['lastState'] as String? ?? 'UNKNOWN',
      lastStateChangedAt: json['lastStateChangedAt'] != null
          ? DateTime.tryParse(json['lastStateChangedAt'].toString())
          : null,
      lastTriggeredAt: json['lastTriggeredAt'] != null
          ? DateTime.tryParse(json['lastTriggeredAt'].toString())
          : null,
      schedule: json['schedule'] != null
          ? GeofenceSchedule.fromJson(json['schedule'] as Map<String, dynamic>)
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'].toString())
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'radius': radius,
      'address': address,
      'zoneType': zoneType.toApiValue(),
      'triggerType': triggerType.toApiValue(),
      'isEnabled': isEnabled,
      'colorHex': colorHex,
      if (schedule != null) 'schedule': schedule!.toJson(),
    };
  }

  Geofence copyWith({
    String? name,
    double? latitude,
    double? longitude,
    double? radius,
    String? address,
    GeofenceZoneType? zoneType,
    GeofenceTriggerType? triggerType,
    bool? isEnabled,
    String? colorHex,
    GeofenceSchedule? schedule,
  }) {
    return Geofence(
      id: id,
      parentId: parentId,
      childId: childId,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radius: radius ?? this.radius,
      address: address ?? this.address,
      zoneType: zoneType ?? this.zoneType,
      triggerType: triggerType ?? this.triggerType,
      isEnabled: isEnabled ?? this.isEnabled,
      colorHex: colorHex ?? this.colorHex,
      lastState: lastState,
      lastStateChangedAt: lastStateChangedAt,
      lastTriggeredAt: lastTriggeredAt,
      schedule: schedule ?? this.schedule,
      createdAt: createdAt,
    );
  }
}

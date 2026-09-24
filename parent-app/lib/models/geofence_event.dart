import 'package:latlong2/latlong.dart';

class GeofenceEvent {
  final String id;
  final String parentId;
  final String childId;
  final String geofenceId;
  final String geofenceName;
  final String eventType; // "EXIT" | "ENTRY"
  final String zoneType; // "SAFE_ZONE" | "RESTRICTED_ZONE"
  final double latitude;
  final double longitude;
  final double? accuracy;
  final double? speed;
  final double distanceFromCenter;
  final double geofenceRadius;
  final String address;
  final bool isRead;
  final DateTime triggeredAt;

  GeofenceEvent({
    required this.id,
    required this.parentId,
    required this.childId,
    required this.geofenceId,
    required this.geofenceName,
    required this.eventType,
    required this.zoneType,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.speed,
    required this.distanceFromCenter,
    required this.geofenceRadius,
    this.address = '',
    this.isRead = false,
    required this.triggeredAt,
  });

  LatLng get latLng => LatLng(latitude, longitude);

  bool get isExit => eventType == 'EXIT';
  bool get isEntry => eventType == 'ENTRY';
  bool get isRestricted => zoneType == 'RESTRICTED_ZONE';

  factory GeofenceEvent.fromJson(Map<String, dynamic> json) {
    return GeofenceEvent(
      id: (json['_id'] ?? json['id']).toString(),
      parentId: (json['parentId'] ?? '').toString(),
      childId: (json['childId'] ?? '').toString(),
      geofenceId: (json['geofenceId'] ?? '').toString(),
      geofenceName: json['geofenceName'] as String? ?? 'Safety Boundary',
      eventType: json['eventType'] as String? ?? 'EXIT',
      zoneType: json['zoneType'] as String? ?? 'SAFE_ZONE',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      speed: (json['speed'] as num?)?.toDouble(),
      distanceFromCenter: (json['distanceFromCenter'] as num?)?.toDouble() ?? 0.0,
      geofenceRadius: (json['geofenceRadius'] as num?)?.toDouble() ?? 200.0,
      address: json['address'] as String? ?? '',
      isRead: json['isRead'] as bool? ?? false,
      triggeredAt: json['triggeredAt'] != null
          ? DateTime.parse(json['triggeredAt'].toString()).toLocal()
          : DateTime.now(),
    );
  }
}

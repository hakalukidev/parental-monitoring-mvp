import 'package:latlong2/latlong.dart';

class LocationPoint {
  final String? id;
  final double latitude;
  final double longitude;
  final double? accuracy;
  final double? altitude;
  final double? speed;
  final double? heading;
  final int? batteryLevel;
  final DateTime recordedAt;

  LocationPoint({
    this.id,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.altitude,
    this.speed,
    this.heading,
    this.batteryLevel,
    required this.recordedAt,
  });

  LatLng get latLng => LatLng(latitude, longitude);

  // Speed in km/h if available (GPS gives m/s)
  double? get speedKmh => speed != null ? speed! * 3.6 : null;

  factory LocationPoint.fromJson(Map<String, dynamic> json) {
    return LocationPoint(
      id: json['id']?.toString() ?? json['_id']?.toString(),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracy: json['accuracy'] != null ? (json['accuracy'] as num).toDouble() : null,
      altitude: json['altitude'] != null ? (json['altitude'] as num).toDouble() : null,
      speed: json['speed'] != null ? (json['speed'] as num).toDouble() : null,
      heading: json['heading'] != null ? (json['heading'] as num).toDouble() : null,
      batteryLevel: json['batteryLevel'] != null ? (json['batteryLevel'] as num).toInt() : null,
      recordedAt: json['recordedAt'] != null
          ? DateTime.parse(json['recordedAt'].toString()).toLocal()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'latitude': latitude,
      'longitude': longitude,
      if (accuracy != null) 'accuracy': accuracy,
      if (altitude != null) 'altitude': altitude,
      if (speed != null) 'speed': speed,
      if (heading != null) 'heading': heading,
      if (batteryLevel != null) 'batteryLevel': batteryLevel,
      'recordedAt': recordedAt.toUtc().toIso8601String(),
    };
  }
}

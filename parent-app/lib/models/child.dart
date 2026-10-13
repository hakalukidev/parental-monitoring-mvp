import 'location_point.dart';

class ChildDevice {
  final String id, deviceName, platform, status;
  final DateTime? lastSeen;
  final LocationPoint? lastLocation;
  ChildDevice(
      {required this.id,
      required this.deviceName,
      required this.platform,
      required this.status,
      this.lastSeen,
      this.lastLocation});
  factory ChildDevice.fromJson(Map<String, dynamic> json) => ChildDevice(
      id: json['id']?.toString() ?? '',
      deviceName: json['deviceName'] as String? ?? 'Android device',
      platform: json['platform'] as String? ?? 'Android',
      status: json['status'] as String? ?? 'UNKNOWN',
      lastSeen: DateTime.tryParse(json['lastSeen']?.toString() ?? ''),
      lastLocation: json['lastLocation'] is Map<String, dynamic> &&
              (json['lastLocation'] as Map)['latitude'] is num &&
              (json['lastLocation'] as Map)['longitude'] is num
          ? LocationPoint.fromJson(json['lastLocation'] as Map<String, dynamic>)
          : null);
}

class Child {
  final String id, name, username;
  final ChildDevice? device;
  final DateTime? expireDate;
  final bool? isPremium;
  final Map<String, dynamic>? recentUsage;
  Child(
      {required this.id,
      required this.name,
      required this.username,
      this.device,
      this.expireDate,
      this.isPremium,
      this.recentUsage});
  factory Child.fromJson(Map<String, dynamic> json) => Child(
      id: json['id'].toString(),
      name: json['name'] as String,
      username: json['username'] as String,
      device: json['device'] is Map<String, dynamic>
          ? ChildDevice.fromJson(json['device'] as Map<String, dynamic>)
          : null,
      expireDate: DateTime.tryParse(json['expireDate']?.toString() ?? ''),
      isPremium: json['isPremium'] as bool?,
      recentUsage: json['recentUsage'] as Map<String, dynamic>?);
  bool get isOnline => device?.status == 'ONLINE';
  Child withPresence(ChildDevice updated) => Child(
      id: id,
      name: name,
      username: username,
      device: updated,
      expireDate: expireDate,
      isPremium: isPremium,
      recentUsage: recentUsage);
}

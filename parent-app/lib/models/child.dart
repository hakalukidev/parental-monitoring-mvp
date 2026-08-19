class ChildDevice {
  final String id;
  final String deviceName;
  final String platform;
  final String status; // ONLINE | OFFLINE
  final DateTime lastSeen;

  ChildDevice({
    required this.id,
    required this.deviceName,
    required this.platform,
    required this.status,
    required this.lastSeen,
  });

  factory ChildDevice.fromJson(Map<String, dynamic> json) => ChildDevice(
        id: json['id'].toString(),
        deviceName: json['deviceName'] as String,
        platform: json['platform'] as String,
        status: json['status'] as String,
        lastSeen: DateTime.parse(json['lastSeen'] as String),
      );
}

class Child {
  final String id;
  final String name;
  final String username;
  final ChildDevice? device;

  Child({required this.id, required this.name, required this.username, this.device});

  factory Child.fromJson(Map<String, dynamic> json) => Child(
        id: json['id'].toString(),
        name: json['name'] as String,
        username: json['username'] as String,
        device: json['device'] != null
            ? ChildDevice.fromJson(json['device'] as Map<String, dynamic>)
            : null,
      );

  bool get isOnline => device?.status == 'ONLINE';
}

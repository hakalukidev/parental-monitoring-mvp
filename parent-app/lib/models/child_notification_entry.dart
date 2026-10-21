class ChildNotificationEntry {
  final String id;
  final String externalId;
  final String packageName;
  final String appName;
  final String title;
  final String content;
  final String? subText;
  final DateTime postTime;

  const ChildNotificationEntry({
    required this.id,
    required this.externalId,
    required this.packageName,
    required this.appName,
    required this.title,
    required this.content,
    this.subText,
    required this.postTime,
  });

  factory ChildNotificationEntry.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic val) {
      if (val == null) return DateTime.now();
      if (val is DateTime) return val;
      return DateTime.tryParse(val.toString()) ?? DateTime.now();
    }

    return ChildNotificationEntry(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      externalId: json['externalId']?.toString() ?? '',
      packageName: json['packageName']?.toString() ?? '',
      appName: json['appName']?.toString() ?? 'App',
      title: json['title']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      subText: json['subText']?.toString(),
      postTime: parseDate(json['postTime']),
    );
  }
}

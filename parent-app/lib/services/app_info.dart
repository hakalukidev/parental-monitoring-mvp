import 'package:flutter/services.dart';

class AppInfo {
  static Future<String> installedVersion() async {
    try {
      final info = await const MethodChannel('seftly/app_info')
          .invokeMapMethod<String, dynamic>('getAppInfo');
      if (info?['version'] is String && info?['build'] is num) {
        return '${info!['version']} · build ${info['build']}';
      }
    } catch (_) {}
    return 'Version unavailable';
  }
}

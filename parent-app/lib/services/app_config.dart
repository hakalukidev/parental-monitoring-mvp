import 'package:flutter/foundation.dart';

class AppConfig {
  static void validate() {
    if (kReleaseMode &&
        (!apiBaseUrl.startsWith('https://') ||
            !socketUrl.startsWith('https://'))) {
      throw StateError('Release endpoints must use HTTPS.');
    }
  }

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.hakaluki.dev',
  );

  static const String socketUrl = String.fromEnvironment(
    'SOCKET_URL',
    defaultValue: 'https://api.hakaluki.dev',
  );
}

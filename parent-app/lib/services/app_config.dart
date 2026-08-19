/// Central place to point the app at your VPS-hosted backend.
/// Update these when you deploy (e.g. to https://api.yourdomain.com).
class AppConfig {
  // Use https:// and wss:// once your VPS has TLS (e.g. via nginx + certbot).
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:4000',
  );

  static const String socketUrl = String.fromEnvironment(
    'SOCKET_URL',
    defaultValue: 'http://localhost:4000',
  );
}

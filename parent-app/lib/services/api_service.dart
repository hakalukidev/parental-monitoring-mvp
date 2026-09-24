import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'app_config.dart';

/// Robust wrapper around the backend REST API with silent auto-refresh support.
class ApiService {
  ApiService._internal();
  static final ApiService instance = ApiService._internal();

  final _storage = const FlutterSecureStorage();
  String? _accessToken;
  String? _refreshToken;

  Uri _u(String path) => Uri.parse('${AppConfig.apiBaseUrl}$path');

  Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      };

  Future<void> loadPersistedToken() async {
    _accessToken = await _storage.read(key: 'access_token');
    _refreshToken = await _storage.read(key: 'refresh_token');
  }

  Future<String?> get accessToken async => _accessToken;

  Future<void> _saveTokens({required String accessToken, String? refreshToken}) async {
    _accessToken = accessToken;
    await _storage.write(key: 'access_token', value: accessToken);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      _refreshToken = refreshToken;
      await _storage.write(key: 'refresh_token', value: refreshToken);
    }
  }

  Future<bool> refreshToken() async {
    final rToken = _refreshToken ?? await _storage.read(key: 'refresh_token');
    if (rToken == null || rToken.isEmpty) return false;

    try {
      final res = await http.post(
        _u('/api/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': rToken}),
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final newAccess = body['accessToken'] as String?;
        final newRefresh = body['refreshToken'] as String?;
        if (newAccess != null && newAccess.isNotEmpty) {
          await _saveTokens(accessToken: newAccess, refreshToken: newRefresh);
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    bool retryOn401 = true,
  }) async {
    final reqHeaders = {
      ..._authHeaders,
      if (headers != null) ...headers,
    };

    http.Response res;
    switch (method.toUpperCase()) {
      case 'GET':
        res = await http.get(uri, headers: reqHeaders);
        break;
      case 'POST':
        res = await http.post(uri, headers: reqHeaders, body: body);
        break;
      case 'PUT':
        res = await http.put(uri, headers: reqHeaders, body: body);
        break;
      case 'DELETE':
        res = await http.delete(uri, headers: reqHeaders);
        break;
      default:
        throw ApiException('Unsupported HTTP method $method');
    }

    if (res.statusCode == 401 && retryOn401 && !uri.path.contains('/api/auth/')) {
      final refreshed = await refreshToken();
      if (refreshed) {
        return _send(method, uri, headers: headers, body: body, retryOn401: false);
      }
    }

    return res;
  }

  dynamic _parseResponse(http.Response res) {
    dynamic jsonBody;
    try {
      if (res.body.trim().isNotEmpty) {
        jsonBody = jsonDecode(res.body);
      }
    } catch (_) {
      throw ApiException('Server error (${res.statusCode}): Backend service unreachable or returned HTML.');
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      if (jsonBody is Map<String, dynamic>) {
        throw ApiException(jsonBody['error']?.toString() ?? 'Request failed (${res.statusCode})');
      }
      throw ApiException('Request failed (${res.statusCode})');
    }

    return jsonBody;
  }

  Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    required String confirmPassword,
  }) async {
    final res = await http.post(
      _u('/api/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'email': email,
        'password': password,
        'confirmPassword': confirmPassword,
      }),
    );
    final body = _parseResponse(res) as Map<String, dynamic>;
    await _saveTokens(
      accessToken: body['accessToken'] as String,
      refreshToken: body['refreshToken'] as String?,
    );
    return body;
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final res = await http.post(
      _u('/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    final body = _parseResponse(res) as Map<String, dynamic>;
    await _saveTokens(
      accessToken: body['accessToken'] as String,
      refreshToken: body['refreshToken'] as String?,
    );
    return body;
  }

  Future<void> logout() async {
    try {
      await http.post(_u('/api/auth/logout'), headers: _authHeaders);
    } catch (_) {}
    _accessToken = null;
    _refreshToken = null;
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
  }

  Future<Map<String, dynamic>> createChild({
    required String name,
    required String username,
    required String password,
    required String confirmPassword,
  }) async {
    final res = await _send(
      'POST',
      _u('/api/children'),
      body: jsonEncode({
        'name': name,
        'username': username,
        'password': password,
        'confirmPassword': confirmPassword,
      }),
    );
    return _parseResponse(res) as Map<String, dynamic>;
  }

  Future<List<dynamic>> listChildren() async {
    final res = await _send('GET', _u('/api/children'));
    final body = _parseResponse(res) as Map<String, dynamic>;
    return body['children'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> requestScreenShare(String childId) async {
    final res = await _send(
      'POST',
      _u('/api/screen-share/request'),
      body: jsonEncode({'childId': childId}),
    );
    return _parseResponse(res) as Map<String, dynamic>;
  }

  Future<void> stopScreenShare(String sessionId) async {
    final res = await _send('POST', _u('/api/screen-share/$sessionId/stop'));
    _parseResponse(res);
  }

  Future<Map<String, dynamic>> requestCameraStream(
    String childId, {
    String cameraFacing = 'BACK',
    bool withAudio = true,
  }) async {
    final res = await _send(
      'POST',
      _u('/api/camera-stream/request'),
      body: jsonEncode({
        'childId': childId,
        'cameraFacing': cameraFacing,
        'withAudio': withAudio,
      }),
    );
    return _parseResponse(res) as Map<String, dynamic>;
  }

  Future<void> stopCameraStream(String sessionId) async {
    final res = await _send('POST', _u('/api/camera-stream/$sessionId/stop'));
    _parseResponse(res);
  }

  Future<Map<String, dynamic>> getLatestLocation(String childId) async {
    final res = await _send('GET', _u('/api/location/latest/$childId'));
    return _parseResponse(res) as Map<String, dynamic>;
  }

  Future<List<dynamic>> getLocationHistory(
    String childId, {
    DateTime? startTime,
    DateTime? endTime,
    int limit = 500,
  }) async {
    final queryParams = <String, String>{
      'limit': limit.toString(),
      if (startTime != null) 'startTime': startTime.toUtc().toIso8601String(),
      if (endTime != null) 'endTime': endTime.toUtc().toIso8601String(),
    };
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/location/history/$childId')
        .replace(queryParameters: queryParams);
    final res = await _send('GET', uri);
    final body = _parseResponse(res) as Map<String, dynamic>;
    return body['points'] as List<dynamic>;
  }

  Future<List<dynamic>> getIceServers() async {
    final res = await _send('GET', _u('/api/config'));
    final body = _parseResponse(res) as Map<String, dynamic>;
    return body['iceServers'] as List<dynamic>;
  }

  // ==========================================
  // App Blocker & Policies
  // ==========================================

  Future<Map<String, dynamic>> listChildApps(String childId) async {
    final res = await _send('GET', _u('/api/children/$childId/apps'));
    return _parseResponse(res) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateAppPolicy(
    String childId,
    String packageName,
    Map<String, dynamic> policy,
  ) async {
    final res = await _send(
      'PUT',
      _u('/api/children/$childId/apps/$packageName/policy'),
      body: jsonEncode(policy),
    );
    return _parseResponse(res) as Map<String, dynamic>;
  }

  Future<void> bulkUpdatePolicy(
    String childId, {
    required String category,
    required String status,
    int? dailyLimitMinutes,
  }) async {
    final res = await _send(
      'POST',
      _u('/api/children/$childId/apps/bulk-policy'),
      body: jsonEncode({
        'category': category,
        'status': status,
        if (dailyLimitMinutes != null) 'dailyLimitMinutes': dailyLimitMinutes,
      }),
    );
    _parseResponse(res);
  }

  Future<bool> toggleDevicePause(String childId, bool isPaused) async {
    final res = await _send(
      'POST',
      _u('/api/children/$childId/pause'),
      body: jsonEncode({'isPaused': isPaused}),
    );
    final body = _parseResponse(res) as Map<String, dynamic>;
    return body['isPaused'] as bool? ?? isPaused;
  }

  // ==========================================
  // Web Filter Rules
  // ==========================================

  Future<List<dynamic>> listWebRules(String childId) async {
    final res = await _send('GET', _u('/api/children/$childId/web-rules'));
    final body = _parseResponse(res) as Map<String, dynamic>;
    return body['rules'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> createWebRule(
    String childId, {
    required String ruleType,
    required String target,
    String action = 'BLOCK',
    bool isEnabled = true,
  }) async {
    final res = await _send(
      'POST',
      _u('/api/children/$childId/web-rules'),
      body: jsonEncode({
        'ruleType': ruleType,
        'target': target,
        'action': action,
        'isEnabled': isEnabled,
      }),
    );
    final body = _parseResponse(res) as Map<String, dynamic>;
    return body['rule'] as Map<String, dynamic>;
  }

  Future<void> updateWebRule(
    String childId,
    String ruleId, {
    String? action,
    bool? isEnabled,
  }) async {
    final res = await _send(
      'PUT',
      _u('/api/children/$childId/web-rules/$ruleId'),
      body: jsonEncode({
        if (action != null) 'action': action,
        if (isEnabled != null) 'isEnabled': isEnabled,
      }),
    );
    _parseResponse(res);
  }

  Future<void> deleteWebRule(String childId, String ruleId) async {
    final res = await _send('DELETE', _u('/api/children/$childId/web-rules/$ruleId'));
    _parseResponse(res);
  }

  // ==========================================
  // Browsing History & Analytics
  // ==========================================

  Future<Map<String, dynamic>> listBrowsingHistory(
    String childId, {
    String? startDate,
    String? endDate,
    String? search,
    String? browser,
    bool? isFlagged,
    bool? isBlockedAttempt,
    int page = 1,
    int limit = 50,
  }) async {
    final query = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
      if (search != null && search.isNotEmpty) 'search': search,
      if (browser != null && browser.isNotEmpty) 'browser': browser,
      if (isFlagged == true) 'isFlagged': 'true',
      if (isBlockedAttempt == true) 'isBlockedAttempt': 'true',
    };

    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/children/$childId/browsing-history')
        .replace(queryParameters: query);
    final res = await _send('GET', uri);
    return _parseResponse(res) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getBrowsingAnalytics(String childId) async {
    final res = await _send('GET', _u('/api/children/$childId/browsing-history/analytics'));
    return _parseResponse(res) as Map<String, dynamic>;
  }

  Future<void> clearBrowsingHistory(String childId) async {
    final res = await _send('DELETE', _u('/api/children/$childId/browsing-history'));
    _parseResponse(res);
  }

  // ==========================================
  // Geofences & Safety Boundaries
  // ==========================================

  Future<Map<String, dynamic>> createGeofence(String childId, Map<String, dynamic> data) async {
    final res = await _send('POST', _u('/api/children/$childId/geofences'), body: data);
    return _parseResponse(res) as Map<String, dynamic>;
  }

  Future<List<dynamic>> listGeofences(String childId) async {
    final res = await _send('GET', _u('/api/children/$childId/geofences'));
    final body = _parseResponse(res) as Map<String, dynamic>;
    return (body['geofences'] as List<dynamic>?) ?? [];
  }

  Future<Map<String, dynamic>> getGeofence(String childId, String geofenceId) async {
    final res = await _send('GET', _u('/api/children/$childId/geofences/$geofenceId'));
    final body = _parseResponse(res) as Map<String, dynamic>;
    return (body['geofence'] as Map<String, dynamic>?) ?? {};
  }

  Future<Map<String, dynamic>> updateGeofence(
    String childId,
    String geofenceId,
    Map<String, dynamic> data,
  ) async {
    final res = await _send('PUT', _u('/api/children/$childId/geofences/$geofenceId'), body: data);
    return _parseResponse(res) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> toggleGeofence(String childId, String geofenceId) async {
    final res = await _send('PATCH', _u('/api/children/$childId/geofences/$geofenceId/toggle'));
    return _parseResponse(res) as Map<String, dynamic>;
  }

  Future<void> deleteGeofence(String childId, String geofenceId) async {
    final res = await _send('DELETE', _u('/api/children/$childId/geofences/$geofenceId'));
    _parseResponse(res);
  }

  Future<Map<String, dynamic>> listGeofenceEvents(
    String childId, {
    String? geofenceId,
    String? eventType,
    bool? isRead,
    String? startDate,
    String? endDate,
    int page = 1,
    int limit = 50,
  }) async {
    final query = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
      if (geofenceId != null) 'geofenceId': geofenceId,
      if (eventType != null) 'eventType': eventType,
      if (isRead != null) 'isRead': isRead.toString(),
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
    };

    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/children/$childId/geofence-events')
        .replace(queryParameters: query);
    final res = await _send('GET', uri);
    return _parseResponse(res) as Map<String, dynamic>;
  }

  Future<void> markGeofenceEventRead(String childId, String eventId) async {
    final res = await _send('PATCH', _u('/api/children/$childId/geofence-events/$eventId/read'));
    _parseResponse(res);
  }

  Future<void> markAllGeofenceEventsRead(String childId) async {
    final res = await _send('PATCH', _u('/api/children/$childId/geofence-events/mark-all-read'));
    _parseResponse(res);
  }
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

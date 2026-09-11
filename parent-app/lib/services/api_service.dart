import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'app_config.dart';

/// Thin wrapper around the backend REST API.
/// Access tokens are kept in memory + secure storage; refresh happens via
/// the httpOnly cookie set by the backend on /api/auth/login|register.
class ApiService {
  ApiService._internal();
  static final ApiService instance = ApiService._internal();

  final _storage = const FlutterSecureStorage();
  String? _accessToken;

  Uri _u(String path) => Uri.parse('${AppConfig.apiBaseUrl}$path');

  Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      };

  Future<void> loadPersistedToken() async {
    _accessToken = await _storage.read(key: 'access_token');
  }

  Future<String?> get accessToken async => _accessToken;

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
    await _saveToken(body['accessToken'] as String);
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
    await _saveToken(body['accessToken'] as String);
    return body;
  }

  Future<void> logout() async {
    await http.post(_u('/api/auth/logout'), headers: _authHeaders);
    _accessToken = null;
    await _storage.delete(key: 'access_token');
  }

  Future<Map<String, dynamic>> createChild({
    required String name,
    required String username,
    required String password,
    required String confirmPassword,
  }) async {
    final res = await http.post(
      _u('/api/children'),
      headers: _authHeaders,
      body: jsonEncode({
        'name': name,
        'username': username,
        'password': password,
        'confirmPassword': confirmPassword,
      }),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 201) {
      throw ApiException(body['error']?.toString() ?? 'Could not create child');
    }
    return body;
  }

  Future<List<dynamic>> listChildren() async {
    final res = await http.get(_u('/api/children'), headers: _authHeaders);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw ApiException(body['error']?.toString() ?? 'Could not load children');
    }
    return body['children'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> requestScreenShare(String childId) async {
    final res = await http.post(
      _u('/api/screen-share/request'),
      headers: _authHeaders,
      body: jsonEncode({'childId': childId}),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 201) {
      throw ApiException(body['error']?.toString() ?? 'Could not request screen share');
    }
    return body;
  }

  Future<void> stopScreenShare(String sessionId) async {
    final res = await http.post(_u('/api/screen-share/$sessionId/stop'), headers: _authHeaders);
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw ApiException(body['error']?.toString() ?? 'Could not stop screen share');
    }
  }

  Future<Map<String, dynamic>> requestCameraStream(
    String childId, {
    String cameraFacing = 'BACK',
    bool withAudio = true,
  }) async {
    final res = await http.post(
      _u('/api/camera-stream/request'),
      headers: _authHeaders,
      body: jsonEncode({
        'childId': childId,
        'cameraFacing': cameraFacing,
        'withAudio': withAudio,
      }),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 201) {
      throw ApiException(body['error']?.toString() ?? 'Could not request camera stream');
    }
    return body;
  }

  Future<void> stopCameraStream(String sessionId) async {
    final res = await http.post(_u('/api/camera-stream/$sessionId/stop'), headers: _authHeaders);
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw ApiException(body['error']?.toString() ?? 'Could not stop camera stream');
    }
  }

  Future<Map<String, dynamic>> getLatestLocation(String childId) async {
    final res = await http.get(_u('/api/location/latest/$childId'), headers: _authHeaders);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw ApiException(body['error']?.toString() ?? 'Could not load latest location');
    }
    return body;
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
    final res = await http.get(uri, headers: _authHeaders);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw ApiException(body['error']?.toString() ?? 'Could not load location history');
    }
    return body['points'] as List<dynamic>;
  }

  Future<List<dynamic>> getIceServers() async {
    final res = await http.get(_u('/api/config'), headers: _authHeaders);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw ApiException(body['error']?.toString() ?? 'Could not load ICE config');
    }
    return body['iceServers'] as List<dynamic>;
  }

  // ==========================================
  // App Blocker & Policies
  // ==========================================

  Future<Map<String, dynamic>> listChildApps(String childId) async {
    final res = await http.get(_u('/api/children/$childId/apps'), headers: _authHeaders);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw ApiException(body['error']?.toString() ?? 'Could not load installed apps');
    }
    return body;
  }

  Future<Map<String, dynamic>> updateAppPolicy(
    String childId,
    String packageName,
    Map<String, dynamic> policy,
  ) async {
    final res = await http.put(
      _u('/api/children/$childId/apps/$packageName/policy'),
      headers: _authHeaders,
      body: jsonEncode(policy),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw ApiException(body['error']?.toString() ?? 'Could not update app policy');
    }
    return body;
  }

  Future<void> bulkUpdatePolicy(
    String childId, {
    required String category,
    required String status,
    int? dailyLimitMinutes,
  }) async {
    final res = await http.post(
      _u('/api/children/$childId/apps/bulk-policy'),
      headers: _authHeaders,
      body: jsonEncode({
        'category': category,
        'status': status,
        if (dailyLimitMinutes != null) 'dailyLimitMinutes': dailyLimitMinutes,
      }),
    );
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw ApiException(body['error']?.toString() ?? 'Could not bulk update policies');
    }
  }

  Future<bool> toggleDevicePause(String childId, bool isPaused) async {
    final res = await http.post(
      _u('/api/children/$childId/pause'),
      headers: _authHeaders,
      body: jsonEncode({'isPaused': isPaused}),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw ApiException(body['error']?.toString() ?? 'Could not update device pause state');
    }
    return body['isPaused'] as bool? ?? isPaused;
  }

  // ==========================================
  // Web Filter Rules
  // ==========================================

  Future<List<dynamic>> listWebRules(String childId) async {
    final res = await http.get(_u('/api/children/$childId/web-rules'), headers: _authHeaders);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw ApiException(body['error']?.toString() ?? 'Could not load web rules');
    }
    return body['rules'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> createWebRule(
    String childId, {
    required String ruleType,
    required String target,
    String action = 'BLOCK',
    bool isEnabled = true,
  }) async {
    final res = await http.post(
      _u('/api/children/$childId/web-rules'),
      headers: _authHeaders,
      body: jsonEncode({
        'ruleType': ruleType,
        'target': target,
        'action': action,
        'isEnabled': isEnabled,
      }),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 201 && res.statusCode != 200) {
      throw ApiException(body['error']?.toString() ?? 'Could not create web rule');
    }
    return body['rule'] as Map<String, dynamic>;
  }

  Future<void> updateWebRule(
    String childId,
    String ruleId, {
    String? action,
    bool? isEnabled,
  }) async {
    final res = await http.put(
      _u('/api/children/$childId/web-rules/$ruleId'),
      headers: _authHeaders,
      body: jsonEncode({
        if (action != null) 'action': action,
        if (isEnabled != null) 'isEnabled': isEnabled,
      }),
    );
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw ApiException(body['error']?.toString() ?? 'Could not update web rule');
    }
  }

  Future<void> deleteWebRule(String childId, String ruleId) async {
    final res = await http.delete(_u('/api/children/$childId/web-rules/$ruleId'), headers: _authHeaders);
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw ApiException(body['error']?.toString() ?? 'Could not delete web rule');
    }
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
    final res = await http.get(uri, headers: _authHeaders);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw ApiException(body['error']?.toString() ?? 'Could not load browsing history');
    }
    return body;
  }

  Future<Map<String, dynamic>> getBrowsingAnalytics(String childId) async {
    final res = await http.get(_u('/api/children/$childId/browsing-history/analytics'), headers: _authHeaders);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw ApiException(body['error']?.toString() ?? 'Could not load browsing analytics');
    }
    return body;
  }

  Future<void> clearBrowsingHistory(String childId) async {
    final res = await http.delete(_u('/api/children/$childId/browsing-history'), headers: _authHeaders);
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw ApiException(body['error']?.toString() ?? 'Could not clear browsing history');
    }
  }

  Future<void> _saveToken(String token) async {
    _accessToken = token;
    await _storage.write(key: 'access_token', value: token);
  }
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

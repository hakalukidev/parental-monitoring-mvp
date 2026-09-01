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
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 201) {
      throw ApiException(body['error']?.toString() ?? 'Registration failed');
    }
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
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw ApiException(body['error']?.toString() ?? 'Login failed');
    }
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

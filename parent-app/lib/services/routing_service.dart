import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteResult {
  final List<LatLng> points;
  final double distanceKm;
  final int durationMinutes;

  RouteResult({
    required this.points,
    required this.distanceKm,
    required this.durationMinutes,
  });
}

class RoutingService {
  static final RoutingService _instance = RoutingService._internal();
  factory RoutingService() => _instance;
  RoutingService._internal();

  Future<RouteResult?> getDrivingRoute(LatLng start, LatLng destination) async {
    try {
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};'
        '${destination.longitude},${destination.latitude}'
        '?overview=full&geometries=geojson',
      );

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'SeftlyParentApp/1.0 (support@seftly.app)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final firstRoute = routes[0] as Map<String, dynamic>;
          final geometry = firstRoute['geometry'] as Map<String, dynamic>?;
          final coords = geometry?['coordinates'] as List?;
          final distanceMeters = (firstRoute['distance'] as num?)?.toDouble() ?? 0.0;
          final durationSeconds = (firstRoute['duration'] as num?)?.toDouble() ?? 0.0;

          if (coords != null && coords.isNotEmpty) {
            final points = coords.map((c) {
              final lon = (c[0] as num).toDouble();
              final lat = (c[1] as num).toDouble();
              return LatLng(lat, lon);
            }).toList();

            return RouteResult(
              points: points,
              distanceKm: distanceMeters / 1000.0,
              durationMinutes: (durationSeconds / 60.0).round().clamp(1, 9999),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('RoutingService error: $e');
    }
    return null;
  }
}

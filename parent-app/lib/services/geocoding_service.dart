import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class GeocodingService {
  static final GeocodingService _instance = GeocodingService._internal();
  factory GeocodingService() => _instance;
  GeocodingService._internal();

  double? _cachedLat;
  double? _cachedLon;
  String? _cachedAddress;
  DateTime? _lastFetchTime;

  static const Distance _distanceCalculator = Distance();

  Future<String?> reverseGeocode(double lat, double lon) async {
    // 1. Check Cache: within 50 meters and under 60 seconds
    if (_cachedAddress != null &&
        _cachedLat != null &&
        _cachedLon != null &&
        _lastFetchTime != null) {
      final metersMoved = _distanceCalculator.as(
        LengthUnit.Meter,
        LatLng(_cachedLat!, _cachedLon!),
        LatLng(lat, lon),
      );
      final secondsElapsed = DateTime.now().difference(_lastFetchTime!).inSeconds;

      if (metersMoved < 50 && secondsElapsed < 60) {
        return _cachedAddress;
      }
    }

    // 2. Fetch from OpenStreetMap Nominatim
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lon&format=json&addressdetails=1',
      );

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'SafetlyParentApp/1.0 (support@safetly.app)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final address = data['address'] as Map<String, dynamic>?;

        String formattedAddress;
        if (address != null) {
          final parts = <String>[];

          // Priority 1: Point of interest / amenity / building
          final poi = address['amenity'] ??
              address['building'] ??
              address['shop'] ??
              address['tourism'] ??
              address['leisure'];
          if (poi != null && poi.toString().isNotEmpty) {
            parts.add(poi.toString());
          }

          // Priority 2: Road / Street
          final road = address['road'] ?? address['pedestrian'] ?? address['street'];
          if (road != null && road.toString().isNotEmpty) {
            parts.add(road.toString());
          }

          // Priority 3: Neighborhood / Suburb / Quarter
          final neighborhood = address['neighbourhood'] ??
              address['suburb'] ??
              address['quarter'] ??
              address['residential'] ??
              address['city_district'];
          if (neighborhood != null && neighborhood.toString().isNotEmpty) {
            if (!parts.contains(neighborhood.toString())) {
              parts.add(neighborhood.toString());
            }
          }

          // Priority 4: City / Town / Village
          final city = address['city'] ??
              address['town'] ??
              address['village'] ??
              address['municipality'] ??
              address['county'];
          if (city != null && city.toString().isNotEmpty) {
            if (!parts.contains(city.toString())) {
              parts.add(city.toString());
            }
          }

          if (parts.isNotEmpty) {
            formattedAddress = parts.join(', ');
          } else {
            formattedAddress = data['display_name']?.toString().split(',').take(3).join(', ') ??
                'Location ($lat, $lon)';
          }
        } else {
          formattedAddress = data['display_name']?.toString().split(',').take(3).join(', ') ??
              'Location ($lat, $lon)';
        }

        _cachedLat = lat;
        _cachedLon = lon;
        _cachedAddress = formattedAddress;
        _lastFetchTime = DateTime.now();

        return formattedAddress;
      }
    } catch (e) {
      debugPrint('GeocodingService error: $e');
    }

    return _cachedAddress ?? 'Location (${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)})';
  }
}

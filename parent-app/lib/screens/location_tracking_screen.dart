import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/location_point.dart';
import '../models/geofence.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/geocoding_service.dart';
import '../services/routing_service.dart';

class LocationTrackingScreen extends StatefulWidget {
  final String childId;
  final String childName;
  final DateTime? focusTimestamp;
  final LatLng? focusLocation;
  final String? highlightGeofenceId;
  final String? breachType;

  const LocationTrackingScreen({
    super.key,
    required this.childId,
    required this.childName,
    this.focusTimestamp,
    this.focusLocation,
    this.highlightGeofenceId,
    this.breachType,
  });

  @override
  State<LocationTrackingScreen> createState() => _LocationTrackingScreenState();
}

class _LocationTrackingScreenState extends State<LocationTrackingScreen> {
  final MapController _mapController = MapController();
  final SocketService _socketService = SocketService();
  final GeocodingService _geocodingService = GeocodingService();
  final RoutingService _routingService = RoutingService();

  bool _isSatelliteView = false;
  bool _breachBannerDismissed = false;
  bool _hasInitialCenteredOnBreach = false;

  LocationPoint? _latestLocation;
  String? _resolvedAddress;
  bool _loading = true;
  String? _error;
  String _deviceStatus = 'UNKNOWN';
  DateTime? _lastSeen;

  // Directions state
  Position? _parentPosition;
  StreamSubscription<Position>? _parentLocationSubscription;
  bool _loadingRoute = false;
  List<LatLng> _osrmRoutePoints = [];
  double? _routeDistanceKm;
  int? _routeDurationMinutes;
  String? _routeError;

  bool _isFollowingChild = true;

  // Geofences layer state
  List<Geofence> _geofences = [];
  bool _showGeofences = true;

  @override
  void initState() {
    super.initState();
    _loadLocationData();
    _loadGeofences();
    _setupSocketListener();
  }

  Future<void> _loadGeofences() async {
    try {
      final raw = await ApiService.instance.listGeofences(widget.childId);
      if (mounted) {
        setState(() {
          _geofences = raw.map((e) => Geofence.fromJson(e as Map<String, dynamic>)).toList();
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _parentLocationSubscription?.cancel();
    _socketService.off('child_location_update');
    _socketService.disconnect();
    super.dispose();
  }

  Future<void> _setupSocketListener() async {
    final token = await ApiService.instance.accessToken;
    if (token != null) {
      try {
        _socketService.connect(token);
        _socketService.onChildLocationUpdate((data) {
          if (data['childId'] == widget.childId && mounted) {
            final newPoint = LocationPoint.fromJson(data);
            setState(() {
              _latestLocation = newPoint;
              _deviceStatus = 'ONLINE';
              _lastSeen = DateTime.now();
            });

            _updateReverseGeocoding(newPoint.latitude, newPoint.longitude);

            if (_parentPosition != null) {
              _calculateDrivingRoute();
            }

            if (_isFollowingChild) {
              _mapController.move(newPoint.latLng, _mapController.camera.zoom);
            }
          }
        });
      } catch (e) {
        debugPrint('Socket connection error: $e');
      }
    }
  }

  Future<void> _updateReverseGeocoding(double lat, double lon) async {
    final address = await _geocodingService.reverseGeocode(lat, lon);
    if (mounted && address != null) {
      setState(() {
        _resolvedAddress = address;
      });
    }
  }

  Future<void> _loadLocationData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 1. Fetch latest location
      final latestRes = await ApiService.instance.getLatestLocation(widget.childId);
      if (latestRes['location'] != null) {
        _latestLocation = LocationPoint.fromJson(latestRes['location'] as Map<String, dynamic>);
        _updateReverseGeocoding(_latestLocation!.latitude, _latestLocation!.longitude);
      }
      _deviceStatus = latestRes['deviceStatus']?.toString() ?? 'OFFLINE';
      if (latestRes['lastSeen'] != null) {
        _lastSeen = DateTime.parse(latestRes['lastSeen'].toString()).toLocal();
      }

      // 2. Fetch parent location and calculate route to child
      await _fetchParentLocationAndRoute();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _fetchParentLocationAndRoute() async {
    setState(() {
      _loadingRoute = true;
      _routeError = null;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _routeError = 'Parent device location services are disabled.';
          _loadingRoute = false;
        });
        _fitMapToBounds();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _routeError = 'Location permission is required to calculate directions.';
            _loadingRoute = false;
          });
          _fitMapToBounds();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _routeError = 'Location permission permanently denied. Enable in Settings.';
          _loadingRoute = false;
        });
        _fitMapToBounds();
        return;
      }

      // 1. FAST PATH: Read cached / last-known position immediately
      Position? pos = await Geolocator.getLastKnownPosition();
      if (pos != null && mounted) {
        setState(() {
          _parentPosition = pos;
          _loadingRoute = false;
        });
        await _calculateDrivingRoute();
      }

      // 2. LIVE PATH: Start background live position stream for fresh movement tracking
      _parentLocationSubscription?.cancel();
      _parentLocationSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 15,
        ),
      ).listen(
        (Position freshPos) async {
          if (!mounted) return;

          bool shouldRecalculate = false;
          if (_parentPosition != null) {
            final movedMeters = const Distance().as(
              LengthUnit.Meter,
              LatLng(_parentPosition!.latitude, _parentPosition!.longitude),
              LatLng(freshPos.latitude, freshPos.longitude),
            );
            if (movedMeters > 20) {
              shouldRecalculate = true;
            }
          } else {
            shouldRecalculate = true;
          }

          setState(() {
            _parentPosition = freshPos;
            _loadingRoute = false;
            _routeError = null;
          });

          if (shouldRecalculate) {
            await _calculateDrivingRoute();
          }
        },
        onError: (err) {
          debugPrint('Parent live position stream error: $err');
          if (_parentPosition == null && mounted) {
            setState(() {
              _routeError = 'Could not acquire GPS fix: $err';
              _loadingRoute = false;
            });
          }
        },
      );

      // If no cached position was available, wait briefly for the first fix
      if (pos == null) {
        try {
          final firstFix = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 6),
          );
          if (mounted) {
            setState(() {
              _parentPosition = firstFix;
              _loadingRoute = false;
            });
            await _calculateDrivingRoute();
          }
        } catch (_) {}
      }
    } catch (e) {
      if (_parentPosition == null && mounted) {
        setState(() {
          _routeError = 'Could not get parent location: $e';
        });
      }
      _fitMapToBounds();
    } finally {
      if (mounted && _parentPosition != null) {
        setState(() => _loadingRoute = false);
      }
    }
  }

  Future<void> _calculateDrivingRoute() async {
    if (_parentPosition == null || _latestLocation == null) {
      _fitMapToBounds();
      return;
    }

    final parentLatLng = LatLng(_parentPosition!.latitude, _parentPosition!.longitude);
    final childLatLng = _latestLocation!.latLng;

    final result = await _routingService.getDrivingRoute(parentLatLng, childLatLng);
    if (result != null && mounted) {
      setState(() {
        _osrmRoutePoints = result.points;
        _routeDistanceKm = result.distanceKm;
        _routeDurationMinutes = result.durationMinutes;
      });

      // Fit map to show both parent and child
      final bounds = LatLngBounds.fromPoints([parentLatLng, childLatLng, ..._osrmRoutePoints]);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 100),
        ),
      );
    } else {
      _fitMapToBounds();
    }
  }

  void _fitMapToBounds() {
    if (widget.focusLocation != null && !_hasInitialCenteredOnBreach) {
      _hasInitialCenteredOnBreach = true;
      _mapController.move(widget.focusLocation!, 16.5);
      return;
    }

    if (_latestLocation == null && _parentPosition == null) return;

    if (_parentPosition != null && _latestLocation != null) {
      final parentLatLng = LatLng(_parentPosition!.latitude, _parentPosition!.longitude);
      final points = [parentLatLng, _latestLocation!.latLng];
      if (_osrmRoutePoints.isNotEmpty) points.addAll(_osrmRoutePoints);
      final bounds = LatLngBounds.fromPoints(points);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 100),
        ),
      );
      return;
    }

    if (_latestLocation != null) {
      _mapController.move(_latestLocation!.latLng, 16.0);
    }
  }

  Future<void> _launchGoogleMapsNavigation(double lat, double lng) async {
    final googleMapsUrl = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    final webUrl = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');

    try {
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl);
      } else if (await canLaunchUrl(webUrl)) {
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open navigation application.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Navigation error: $e')),
        );
      }
    }
  }

  void _showChildDetailsModal(LocationPoint loc) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: const Icon(Icons.person, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.childName,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _resolvedAddress ?? 'Lat: ${loc.latitude.toStringAsFixed(4)}, Lon: ${loc.longitude.toStringAsFixed(4)}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _MetricItem(
                    icon: Icons.speed,
                    label: 'Speed',
                    value: loc.speedKmh != null ? '${loc.speedKmh!.toStringAsFixed(1)} km/h' : '0 km/h',
                  ),
                  _MetricItem(
                    icon: Icons.battery_charging_full,
                    label: 'Battery',
                    value: loc.batteryLevel != null ? '${loc.batteryLevel}%' : '--',
                  ),
                  _MetricItem(
                    icon: Icons.gps_not_fixed,
                    label: 'Accuracy',
                    value: loc.accuracy != null ? '±${loc.accuracy!.toStringAsFixed(0)}m' : '--',
                  ),
                  _MetricItem(
                    icon: Icons.access_time,
                    label: 'Recorded',
                    value: DateFormat('h:mm a').format(loc.recordedAt),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _launchGoogleMapsNavigation(loc.latitude, loc.longitude);
                  },
                  icon: const Icon(Icons.navigation),
                  label: const Text('Navigate in Google Maps'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeLocation = _latestLocation;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.childName}\'s Location',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _deviceStatus == 'ONLINE' ? Colors.greenAccent : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _deviceStatus == 'ONLINE'
                      ? 'Live GPS • Online'
                      : 'Offline (${_lastSeen != null ? DateFormat('h:mm a').format(_lastSeen!) : 'Unknown'})',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _deviceStatus == 'ONLINE' ? Colors.green.shade700 : Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _showGeofences ? Icons.shield : Icons.shield_outlined,
              color: _showGeofences ? Colors.teal : null,
            ),
            tooltip: _showGeofences ? 'Hide Geofences' : 'Show Geofences',
            onPressed: () => setState(() => _showGeofences = !_showGeofences),
          ),
          IconButton(
            icon: Icon(_isSatelliteView ? Icons.layers_clear : Icons.satellite_alt),
            tooltip: _isSatelliteView ? 'Standard Map' : 'Satellite Map',
            onPressed: () => setState(() => _isSatelliteView = !_isSatelliteView),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Location',
            onPressed: _loadLocationData,
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: activeLocation?.latLng ?? const LatLng(23.8103, 90.4125),
              initialZoom: 15.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
              onPositionChanged: (pos, hasGesture) {
                if (hasGesture && _isFollowingChild) {
                  setState(() => _isFollowingChild = false);
                }
              },
            ),
            children: [
              // Map Tile Layer
              if (_isSatelliteView)
                TileLayer(
                  urlTemplate: 'https://mt{s}.google.com/vt/lyrs=y&x={x}&y={y}&z={z}',
                  subdomains: const ['0', '1', '2', '3'],
                  userAgentPackageName: 'com.example.parentapp',
                  maxZoom: 20.0,
                  maxNativeZoom: 20,
                  fallbackUrl: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                )
              else
                TileLayer(
                  urlTemplate: 'https://mt{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
                  subdomains: const ['0', '1', '2', '3'],
                  userAgentPackageName: 'com.example.parentapp',
                  maxZoom: 20.0,
                  maxNativeZoom: 20,
                  fallbackUrl: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                ),

              // Road-following Route Polyline (Directions to Child)
              if (_osrmRoutePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _osrmRoutePoints,
                      strokeWidth: 5.5,
                      color: const Color(0xFF2563EB),
                      borderColor: Colors.white,
                      borderStrokeWidth: 2.0,
                    ),
                  ],
                ),

              // Active Geofence Boundary Circles
              if (_showGeofences && _geofences.isNotEmpty)
                CircleLayer(
                  circles: _geofences.where((g) => g.isEnabled).map((g) {
                    final isSafe = g.zoneType == GeofenceZoneType.safeZone;
                    final isHighlighted = widget.highlightGeofenceId != null && g.id == widget.highlightGeofenceId;
                    final col = isSafe ? Colors.teal : Colors.red;
                    return CircleMarker(
                      point: g.latLng,
                      radius: g.radius,
                      useRadiusInMeter: true,
                      color: col.withValues(alpha: isHighlighted ? 0.35 : 0.18),
                      borderColor: isHighlighted ? (isSafe ? Colors.teal.shade900 : Colors.red.shade900) : col,
                      borderStrokeWidth: isHighlighted ? 3.5 : 2.0,
                    );
                  }).toList(),
                ),

              // Geofence Center Badges & Labels
              if (_showGeofences && _geofences.isNotEmpty)
                MarkerLayer(
                  markers: _geofences.where((g) => g.isEnabled).map((g) {
                    final isSafe = g.zoneType == GeofenceZoneType.safeZone;
                    final col = isSafe ? Colors.teal : Colors.red;
                    return Marker(
                      point: g.latLng,
                      width: 130,
                      height: 36,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: col,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isSafe ? Icons.shield : Icons.dangerous,
                                color: Colors.white,
                                size: 12,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  g.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

              // Accuracy Circle around Child Position
              if (activeLocation != null && activeLocation.accuracy != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: activeLocation.latLng,
                      radius: (activeLocation.accuracy! / 2).clamp(15.0, 80.0),
                      useRadiusInMeter: false,
                      color: Colors.blue.withValues(alpha: 0.12),
                      borderColor: Colors.blue.withValues(alpha: 0.35),
                      borderStrokeWidth: 1.5,
                    ),
                  ],
                ),

              // Map Markers
              MarkerLayer(
                markers: [
                  // Breach Alert Marker (when opened from push notification)
                  if (widget.focusLocation != null)
                    Marker(
                      point: widget.focusLocation!,
                      width: 140,
                      height: 70,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.red.shade700,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white, width: 1.5),
                              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 12),
                                const SizedBox(width: 4),
                                Text(
                                  widget.breachType != null ? '${widget.breachType} Breach' : 'Breach Point',
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.red.shade600,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6)],
                            ),
                            child: const Icon(Icons.location_on, color: Colors.white, size: 20),
                          ),
                        ],
                      ),
                    ),

                  // Parent Marker ("You")
                  if (_parentPosition != null)
                    Marker(
                      point: LatLng(_parentPosition!.latitude, _parentPosition!.longitude),
                      width: 70,
                      height: 70,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white, width: 1.5),
                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                            ),
                            child: const Text(
                              'You',
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.all(5),
                            decoration: const BoxDecoration(
                              color: Color(0xFF2563EB),
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 6)],
                            ),
                            child: const Icon(Icons.person, color: Colors.white, size: 22),
                          ),
                        ],
                      ),
                    ),

                  // Child Pin Marker with Name Badge & OnTap Modal
                  if (activeLocation != null)
                    Marker(
                      point: activeLocation.latLng,
                      width: 90,
                      height: 80,
                      child: GestureDetector(
                        onTap: () => _showChildDetailsModal(activeLocation),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white, width: 1.5),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black38,
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Text(
                                widget.childName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.35),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.person_pin_circle,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Geofence Breach Banner (shown when opened via push notification)
          if (widget.focusTimestamp != null && !_breachBannerDismissed)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Card(
                elevation: 4,
                color: Colors.red.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.red.shade300, width: 1.2),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.notifications_active, color: Colors.red.shade700, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Safety Boundary Breach Event',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade900,
                              ),
                            ),
                            Text(
                              'Showing breach location at ${DateFormat('MMM d, h:mm a').format(widget.focusTimestamp!.toLocal())}',
                              style: TextStyle(fontSize: 11, color: Colors.red.shade800),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        color: Colors.red.shade900,
                        onPressed: () => setState(() => _breachBannerDismissed = true),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Floating Action Buttons (Recenter / Layer / Fit)
          Positioned(
            right: 16,
            bottom: 230,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'toggle_map_layer',
                  backgroundColor: theme.colorScheme.surface,
                  tooltip: _isSatelliteView ? 'Street View' : 'Satellite View',
                  onPressed: () => setState(() => _isSatelliteView = !_isSatelliteView),
                  child: Icon(_isSatelliteView ? Icons.map : Icons.satellite_alt),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'recenter_child',
                  backgroundColor: _isFollowingChild
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surface,
                  foregroundColor: _isFollowingChild
                      ? Colors.white
                      : theme.colorScheme.onSurface,
                  tooltip: 'Follow Child',
                  onPressed: () {
                    setState(() => _isFollowingChild = true);
                    if (_latestLocation != null) {
                      _mapController.move(_latestLocation!.latLng, 16.0);
                    }
                  },
                  child: const Icon(Icons.gps_fixed),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'fit_bounds',
                  backgroundColor: theme.colorScheme.surface,
                  tooltip: 'Fit Route Bounds',
                  onPressed: _fitMapToBounds,
                  child: const Icon(Icons.crop_free),
                ),
              ],
            ),
          ),

          // Bottom Telemetry & Navigation Card
          Positioned(
            left: 12,
            right: 12,
            bottom: 16,
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_loading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(8.0),
                          child: LinearProgressIndicator(),
                        ),
                      )
                    else if (_error != null)
                      Text(_error!, style: TextStyle(color: theme.colorScheme.error))
                    else if (activeLocation == null)
                      const Text('No location data recorded yet for child.')
                    else ...[
                      // Human-Readable Address Header
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.location_on,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _resolvedAddress ?? 'Locating address...',
                                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Recorded: ${DateFormat('h:mm:ss a, MMM d').format(activeLocation.recordedAt)} • GPS ±${activeLocation.accuracy?.toStringAsFixed(0) ?? '15'}m',
                                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      // Directions Route Info & Google Maps Button
                      if (_loadingRoute)
                        const Padding(
                          padding: EdgeInsets.only(top: 12.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                              SizedBox(width: 12),
                              Text('Calculating road route from your location...'),
                            ],
                          ),
                        )
                      else if (_routeError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            _routeError!,
                            style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                          ),
                        )
                      else if (_routeDistanceKm != null && _routeDurationMinutes != null) ...[
                        const Divider(height: 20),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.directions_car, size: 18, color: Colors.blue.shade700),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${_routeDistanceKm!.toStringAsFixed(1)} km',
                                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '(${_routeDurationMinutes!} mins)',
                                    style: TextStyle(color: Colors.blue.shade800),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF2563EB),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: () => _launchGoogleMapsNavigation(
                                activeLocation.latitude,
                                activeLocation.longitude,
                              ),
                              icon: const Icon(Icons.navigation, size: 18),
                              label: const Text('Navigate'),
                            ),
                          ],
                        ),
                      ],

                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _MetricItem(
                            icon: Icons.speed,
                            label: 'Speed',
                            value: activeLocation.speedKmh != null
                                ? '${activeLocation.speedKmh!.toStringAsFixed(1)} km/h'
                                : '0 km/h',
                          ),
                          _MetricItem(
                            icon: Icons.battery_charging_full,
                            label: 'Battery',
                            value: activeLocation.batteryLevel != null
                                ? '${activeLocation.batteryLevel}%'
                                : '--',
                          ),
                          _MetricItem(
                            icon: Icons.gps_not_fixed,
                            label: 'Accuracy',
                            value: activeLocation.accuracy != null
                                ? '±${activeLocation.accuracy!.toStringAsFixed(0)}m'
                                : '--',
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetricItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)),
      ],
    );
  }
}

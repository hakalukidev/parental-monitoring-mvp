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
import 'geofences_screen.dart';

enum MapTrackingMode {
  directionsToChild,
  historyTrail,
}

enum RouteTimeFilter {
  liveOnly,
  today,
  past24Hours,
  past7Days,
  custom,
}

class LocationTrackingScreen extends StatefulWidget {
  final String childId;
  final String childName;
  final MapTrackingMode initialTrackingMode;
  final DateTime? focusTimestamp;
  final LatLng? focusLocation;
  final String? highlightGeofenceId;
  final String? breachType;

  const LocationTrackingScreen({
    super.key,
    required this.childId,
    required this.childName,
    this.initialTrackingMode = MapTrackingMode.directionsToChild,
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

  late MapTrackingMode _trackingMode;
  bool _isSatelliteView = false;
  bool _breachBannerDismissed = false;
  bool _hasInitialCenteredOnBreach = false;

  LocationPoint? _latestLocation;
  String? _resolvedAddress;
  List<LocationPoint> _routeHistory = [];
  bool _loading = true;
  String? _error;
  String _deviceStatus = 'UNKNOWN';
  DateTime? _lastSeen;

  // Directions mode state
  Position? _parentPosition;
  StreamSubscription<Position>? _parentLocationSubscription;
  bool _loadingRoute = false;
  List<LatLng> _osrmRoutePoints = [];
  double? _routeDistanceKm;
  int? _routeDurationMinutes;
  String? _routeError;

  // History mode state
  RouteTimeFilter _selectedFilter = RouteTimeFilter.today;
  DateTimeRange? _customDateRange;
  int? _scrubbedPointIndex;
  bool _showBreadcrumbs = true;
  bool _isFollowingChild = true;

  // Geofences layer state
  List<Geofence> _geofences = [];
  bool _showGeofences = true;

  @override
  void initState() {
    super.initState();
    _trackingMode = widget.initialTrackingMode;
    if (widget.focusTimestamp != null) {
      _trackingMode = MapTrackingMode.historyTrail;
      final now = DateTime.now();
      final focus = widget.focusTimestamp!.toLocal();
      if (focus.year == now.year && focus.month == now.month && focus.day == now.day) {
        _selectedFilter = RouteTimeFilter.today;
      } else {
        _selectedFilter = RouteTimeFilter.custom;
        _customDateRange = DateTimeRange(
          start: DateTime(focus.year, focus.month, focus.day),
          end: DateTime(focus.year, focus.month, focus.day).add(const Duration(days: 1)),
        );
      }
    }
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

              if (_selectedFilter != RouteTimeFilter.liveOnly) {
                _routeHistory.add(newPoint);
              }
            });

            _updateReverseGeocoding(newPoint.latitude, newPoint.longitude);

            if (_trackingMode == MapTrackingMode.directionsToChild && _parentPosition != null) {
              _calculateDrivingRoute();
            }

            if (_isFollowingChild && _trackingMode == MapTrackingMode.historyTrail) {
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
      _scrubbedPointIndex = null;
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

      // 2. Fetch history if filter is not liveOnly
      if (_selectedFilter != RouteTimeFilter.liveOnly) {
        DateTime? startTime;
        DateTime? endTime;
        final now = DateTime.now();

        switch (_selectedFilter) {
          case RouteTimeFilter.today:
            startTime = DateTime(now.year, now.month, now.day);
            break;
          case RouteTimeFilter.past24Hours:
            startTime = now.subtract(const Duration(hours: 24));
            break;
          case RouteTimeFilter.past7Days:
            startTime = now.subtract(const Duration(days: 7));
            break;
          case RouteTimeFilter.custom:
            if (_customDateRange != null) {
              startTime = _customDateRange!.start;
              endTime = _customDateRange!.end.add(const Duration(days: 1));
            }
            break;
          case RouteTimeFilter.liveOnly:
            break;
        }

        final historyRaw = await ApiService.instance.getLocationHistory(
          widget.childId,
          startTime: startTime,
          endTime: endTime,
        );

        final parsedList = historyRaw
            .map((e) => LocationPoint.fromJson(e as Map<String, dynamic>))
            .toList();

        // Strictly sort by recordedAt
        parsedList.sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

        // Filter stationary jitter (< 15 meters)
        _routeHistory = _filterStationaryJitter(parsedList);
      } else {
        _routeHistory = [];
      }

      // 3. If in Directions mode, fetch parent location and route
      if (_trackingMode == MapTrackingMode.directionsToChild) {
        await _fetchParentLocationAndRoute();
      } else {
        _fitMapToBounds();
      }
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

  List<LocationPoint> _filterStationaryJitter(List<LocationPoint> points) {
    if (points.length <= 2) return points;
    const distanceCalc = Distance();
    final filtered = <LocationPoint>[points.first];

    for (int i = 1; i < points.length; i++) {
      final lastKept = filtered.last;
      final current = points[i];
      final distMeters = distanceCalc.as(
        LengthUnit.Meter,
        lastKept.latLng,
        current.latLng,
      );

      // Keep if moved >= 15 meters or if significant time elapsed (>= 5 minutes)
      if (distMeters >= 15.0 ||
          current.recordedAt.difference(lastKept.recordedAt).inMinutes >= 5) {
        filtered.add(current);
      }
    }

    // Always include the latest point if available
    if (points.isNotEmpty && filtered.last != points.last) {
      filtered.add(points.last);
    }

    return filtered;
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

      // 1. FAST PATH: Read cached / last-known position immediately (0ms response)
      Position? pos = await Geolocator.getLastKnownPosition();
      if (pos != null && mounted) {
        setState(() {
          _parentPosition = pos;
          _loadingRoute = false;
        });
        await _calculateDrivingRoute();
      }

      // 2. LIVE PATH: Start background live position stream for fresh satellite lock & movement tracking
      _parentLocationSubscription?.cancel();
      _parentLocationSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 15, // Update whenever parent moves 15+ meters
        ),
      ).listen(
        (Position freshPos) async {
          if (!mounted) return;

          // Check if parent moved significantly from last calculated position
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
          // If we already have a cached position, do not show an intrusive error
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
        } catch (_) {
          // Handled by live stream or error banner
        }
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

    if (_latestLocation == null && _routeHistory.isEmpty && _parentPosition == null) return;

    if (_trackingMode == MapTrackingMode.directionsToChild && _parentPosition != null && _latestLocation != null) {
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

    if (_routeHistory.isNotEmpty && _selectedFilter != RouteTimeFilter.liveOnly) {
      final points = _routeHistory.map((p) => p.latLng).toList();
      if (_latestLocation != null) points.add(_latestLocation!.latLng);

      if (points.length > 1) {
        final bounds = LatLngBounds.fromPoints(points);
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 100),
          ),
        );
        return;
      }
    }

    if (_latestLocation != null) {
      _mapController.move(_latestLocation!.latLng, 16.0);
    }
  }

  double _calculateTotalDistanceKm() {
    if (_routeHistory.length < 2) return 0.0;
    const distance = Distance();
    double totalMeters = 0.0;
    for (int i = 0; i < _routeHistory.length - 1; i++) {
      totalMeters += distance.as(
        LengthUnit.Meter,
        _routeHistory[i].latLng,
        _routeHistory[i + 1].latLng,
      );
    }
    return totalMeters / 1000.0;
  }

  Future<void> _launchGoogleMapsNavigation(double lat, double lng) async {
    final navUri = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    final webFallback = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');

    try {
      if (await canLaunchUrl(navUri)) {
        await launchUrl(navUri);
      } else {
        await launchUrl(webFallback, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open navigation: $e')),
        );
      }
    }
  }

  void _showChildDetailsModal(LocationPoint loc) {
    final theme = Theme.of(context);
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
                    backgroundColor: theme.colorScheme.primary,
                    child: Text(
                      widget.childName.isNotEmpty ? widget.childName[0].toUpperCase() : 'C',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.childName,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _deviceStatus == 'ONLINE'
                              ? 'Live • Connected'
                              : 'Last updated ${DateFormat('MMM d, h:mm a').format(loc.recordedAt)}',
                          style: TextStyle(
                            color: _deviceStatus == 'ONLINE' ? Colors.green.shade700 : Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _resolvedAddress ?? 'Resolving address...',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _MetricItem(
                    icon: Icons.battery_charging_full,
                    label: 'Battery',
                    value: loc.batteryLevel != null ? '${loc.batteryLevel}%' : '--',
                  ),
                  _MetricItem(
                    icon: Icons.speed,
                    label: 'Speed',
                    value: loc.speedKmh != null ? '${loc.speedKmh!.toStringAsFixed(1)} km/h' : '0 km/h',
                  ),
                  _MetricItem(
                    icon: Icons.gps_fixed,
                    label: 'GPS Accuracy',
                    value: loc.accuracy != null ? '±${loc.accuracy!.toStringAsFixed(0)}m' : '--',
                  ),
                ],
              ),
              const SizedBox(height: 16),
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

  Future<void> _selectCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
      initialDateRange: _customDateRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 3)),
            end: DateTime.now(),
          ),
    );
    if (picked != null) {
      setState(() {
        _customDateRange = picked;
        _selectedFilter = RouteTimeFilter.custom;
      });
      _loadLocationData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeLocation = _scrubbedPointIndex != null &&
            _scrubbedPointIndex! < _routeHistory.length
        ? _routeHistory[_scrubbedPointIndex!]
        : _latestLocation;

    final initialCenter = _latestLocation?.latLng ??
        (_routeHistory.isNotEmpty ? _routeHistory.last.latLng : const LatLng(23.8103, 90.4125));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.childName}\'s Location'),
            Text(
              _deviceStatus == 'ONLINE'
                  ? 'Live GPS • Online'
                  : 'Last seen: ${_lastSeen != null ? DateFormat('MMM d, h:mm a').format(_lastSeen!) : 'Offline'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: _deviceStatus == 'ONLINE' ? Colors.green.shade700 : Colors.grey.shade600,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_showGeofences ? Icons.shield : Icons.shield_outlined,
                color: _showGeofences ? Colors.teal : null),
            tooltip: 'Safety Boundaries & Geofences',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GeofencesScreen(
                    childId: widget.childId,
                    childName: widget.childName,
                    latestChildLocation: _latestLocation?.latLng,
                    socketService: _socketService,
                  ),
                ),
              );
              _loadGeofences();
            },
          ),
          IconButton(
            icon: Icon(_isSatelliteView ? Icons.map : Icons.satellite_alt),
            tooltip: _isSatelliteView ? 'Switch to Street Map' : 'Switch to Satellite Map',
            onPressed: () => setState(() => _isSatelliteView = !_isSatelliteView),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadLocationData,
          ),
        ],
      ),
      body: Stack(
        children: [
          // FlutterMap Tile & Overlay Layers
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: 15.0,
              maxZoom: 20.0,
              onPositionChanged: (pos, hasGesture) {
                if (hasGesture && _isFollowingChild) {
                  setState(() => _isFollowingChild = false);
                }
              },
            ),
            children: [
              // High-resolution Google Maps Tile Layer
              if (_isSatelliteView)
                TileLayer(
                  // Google Hybrid: High-res satellite imagery + roads + all place/shop labels
                  urlTemplate: 'https://mt{s}.google.com/vt/lyrs=y&x={x}&y={y}&z={z}',
                  subdomains: const ['0', '1', '2', '3'],
                  userAgentPackageName: 'com.example.parentapp',
                  maxZoom: 20.0,
                  maxNativeZoom: 20,
                  fallbackUrl: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                )
              else
                TileLayer(
                  // Google Street: Full street map with local POIs (mosques, shops, schools, markets, Bengali/English labels)
                  urlTemplate: 'https://mt{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
                  subdomains: const ['0', '1', '2', '3'],
                  userAgentPackageName: 'com.example.parentapp',
                  maxZoom: 20.0,
                  maxNativeZoom: 20,
                  fallbackUrl: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                ),

              // Road-following Route Polyline (Directions Mode)
              if (_trackingMode == MapTrackingMode.directionsToChild && _osrmRoutePoints.isNotEmpty)
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

              // Breadcrumb Polylines (History Trail Mode)
              if (_trackingMode == MapTrackingMode.historyTrail && _showBreadcrumbs && _routeHistory.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routeHistory.map((p) => p.latLng).toList(),
                      strokeWidth: 4.5,
                      color: Colors.blue.shade600.withValues(alpha: 0.85),
                      borderStrokeWidth: 1.5,
                      borderColor: Colors.white,
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

                  // Parent Marker (Directions Mode)
                  if (_trackingMode == MapTrackingMode.directionsToChild && _parentPosition != null)
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

                  // Historical waypoint dots (History Trail Mode)
                  if (_trackingMode == MapTrackingMode.historyTrail && _showBreadcrumbs && _routeHistory.isNotEmpty)
                    for (int i = 0; i < _routeHistory.length; i++)
                      Marker(
                        point: _routeHistory[i].latLng,
                        width: 14,
                        height: 14,
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _scrubbedPointIndex = i);
                            _mapController.move(_routeHistory[i].latLng, _mapController.camera.zoom);
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i == 0
                                  ? Colors.green
                                  : (i == _routeHistory.length - 1 ? Colors.red : Colors.blue.shade700),
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
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

          // Top Mode Switcher Bar
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Expanded(
                      child: _ModeTabButton(
                        title: 'Directions to Child',
                        icon: Icons.alt_route,
                        isSelected: _trackingMode == MapTrackingMode.directionsToChild,
                        onTap: () {
                          setState(() => _trackingMode = MapTrackingMode.directionsToChild);
                          _fetchParentLocationAndRoute();
                        },
                      ),
                    ),
                    Expanded(
                      child: _ModeTabButton(
                        title: 'Child History Trail',
                        icon: Icons.timeline,
                        isSelected: _trackingMode == MapTrackingMode.historyTrail,
                        onTap: () {
                          setState(() => _trackingMode = MapTrackingMode.historyTrail);
                          _fitMapToBounds();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Sub-Filter Chips Bar (Only shown in History Trail mode)
          if (_trackingMode == MapTrackingMode.historyTrail)
            Positioned(
              top: 72,
              left: 12,
              right: 12,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterChip(
                      label: 'Live',
                      icon: Icons.my_location,
                      isSelected: _selectedFilter == RouteTimeFilter.liveOnly,
                      onSelected: () {
                        setState(() => _selectedFilter = RouteTimeFilter.liveOnly);
                        _loadLocationData();
                      },
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Today',
                      isSelected: _selectedFilter == RouteTimeFilter.today,
                      onSelected: () {
                        setState(() => _selectedFilter = RouteTimeFilter.today);
                        _loadLocationData();
                      },
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Past 24h',
                      isSelected: _selectedFilter == RouteTimeFilter.past24Hours,
                      onSelected: () {
                        setState(() => _selectedFilter = RouteTimeFilter.past24Hours);
                        _loadLocationData();
                      },
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Past 7 Days',
                      isSelected: _selectedFilter == RouteTimeFilter.past7Days,
                      onSelected: () {
                        setState(() => _selectedFilter = RouteTimeFilter.past7Days);
                        _loadLocationData();
                      },
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: _customDateRange != null
                          ? '${DateFormat('M/d').format(_customDateRange!.start)} - ${DateFormat('M/d').format(_customDateRange!.end)}'
                          : 'Custom Range',
                      icon: Icons.calendar_today,
                      isSelected: _selectedFilter == RouteTimeFilter.custom,
                      onSelected: _selectCustomDateRange,
                    ),
                  ],
                ),
              ),
            ),

          // Geofence Breach Banner (shown when opened via push notification)
          if (widget.focusTimestamp != null && !_breachBannerDismissed)
            Positioned(
              top: _trackingMode == MapTrackingMode.historyTrail ? 116 : 72,
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
                              'Showing trail around ${DateFormat('MMM d, h:mm a').format(widget.focusTimestamp!.toLocal())}',
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
            bottom: _trackingMode == MapTrackingMode.directionsToChild ? 240 : 220,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'toggle_map_layer',
                  backgroundColor: theme.colorScheme.surface,
                  tooltip: _isSatelliteView ? 'Street View' : 'Satellite View',
                  onPressed: () => setState(() => _isSatelliteView = !_isSatelliteView),
                  child: Icon(_isSatelliteView ? Icons.map : Icons.satellite_alt),
                ),
                if (_trackingMode == MapTrackingMode.historyTrail) ...[
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'toggle_trail',
                    backgroundColor: theme.colorScheme.surface,
                    tooltip: _showBreadcrumbs ? 'Hide Trail' : 'Show Trail',
                    onPressed: () => setState(() => _showBreadcrumbs = !_showBreadcrumbs),
                    child: Icon(_showBreadcrumbs ? Icons.timeline : Icons.timeline_outlined),
                  ),
                ],
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
                    setState(() {
                      _isFollowingChild = true;
                      _scrubbedPointIndex = null;
                    });
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
                      const Text('No location data recorded yet for this period.')
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
                              _trackingMode == MapTrackingMode.directionsToChild
                                  ? Icons.directions
                                  : Icons.location_on,
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

                      // Directions Mode Route Info & Google Maps Button
                      if (_trackingMode == MapTrackingMode.directionsToChild) ...[
                        const Divider(height: 20),
                        if (_loadingRoute)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.0),
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
                          Text(_routeError!, style: TextStyle(color: theme.colorScheme.error, fontSize: 13))
                        else if (_routeDistanceKm != null && _routeDurationMinutes != null)
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

                      // History Trail Mode Metrics & Scrubber
                      if (_trackingMode == MapTrackingMode.historyTrail) ...[
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
                            if (_routeHistory.length > 1)
                              _MetricItem(
                                icon: Icons.straighten,
                                label: 'Distance',
                                value: '${_calculateTotalDistanceKm().toStringAsFixed(2)} km',
                              ),
                          ],
                        ),

                        if (_routeHistory.length > 1) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text('Trail Scrubber', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              const Spacer(),
                              if (_scrubbedPointIndex != null)
                                TextButton(
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  onPressed: () => setState(() => _scrubbedPointIndex = null),
                                  child: const Text('Back to Live'),
                                ),
                            ],
                          ),
                          Slider(
                            min: 0,
                            max: (_routeHistory.length - 1).toDouble(),
                            divisions: _routeHistory.length - 1,
                            value: (_scrubbedPointIndex ?? (_routeHistory.length - 1)).toDouble(),
                            onChanged: (val) {
                              final idx = val.round();
                              setState(() {
                                _scrubbedPointIndex = idx;
                                _isFollowingChild = false;
                              });
                              _mapController.move(_routeHistory[idx].latLng, _mapController.camera.zoom);
                              _updateReverseGeocoding(_routeHistory[idx].latitude, _routeHistory[idx].longitude);
                            },
                          ),
                        ],
                      ],
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

class _ModeTabButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeTabButton({
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : theme.colorScheme.onSurface,
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isSelected;
  final VoidCallback onSelected;

  const _FilterChip({
    required this.label,
    this.icon,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FilterChip(
      selected: isSelected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: isSelected ? theme.colorScheme.onPrimary : null),
            const SizedBox(width: 4),
          ],
          Text(label),
        ],
      ),
      selectedColor: theme.colorScheme.primary,
      labelStyle: TextStyle(
        color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      onSelected: (_) => onSelected(),
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

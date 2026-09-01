import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import '../models/location_point.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

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

  const LocationTrackingScreen({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  State<LocationTrackingScreen> createState() => _LocationTrackingScreenState();
}

class _LocationTrackingScreenState extends State<LocationTrackingScreen> {
  final MapController _mapController = MapController();
  final SocketService _socketService = SocketService();

  LocationPoint? _latestLocation;
  List<LocationPoint> _routeHistory = [];
  bool _loading = true;
  String? _error;
  String _deviceStatus = 'UNKNOWN';
  DateTime? _lastSeen;

  RouteTimeFilter _selectedFilter = RouteTimeFilter.today;
  DateTimeRange? _customDateRange;

  // Timeline scrubber for historical route playback
  int? _scrubbedPointIndex;
  bool _showBreadcrumbs = true;
  bool _isFollowingChild = true;

  @override
  void initState() {
    super.initState();
    _loadLocationData();
    _setupSocketListener();
  }

  @override
  void dispose() {
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

              // If today or past 24h filter is active, append to route history
              if (_selectedFilter != RouteTimeFilter.liveOnly) {
                _routeHistory.add(newPoint);
              }
            });

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

        _routeHistory = historyRaw
            .map((e) => LocationPoint.fromJson(e as Map<String, dynamic>))
            .toList();
      } else {
        _routeHistory = [];
      }

      if (mounted) {
        setState(() {});
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

  void _fitMapToBounds() {
    if (_latestLocation == null && _routeHistory.isEmpty) return;

    if (_routeHistory.isNotEmpty && _selectedFilter != RouteTimeFilter.liveOnly) {
      final points = _routeHistory.map((p) => p.latLng).toList();
      if (_latestLocation != null) points.add(_latestLocation!.latLng);

      if (points.length > 1) {
        final bounds = LatLngBounds.fromPoints(points);
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.all(50),
          ),
        );
        return;
      }
    }

    if (_latestLocation != null) {
      _mapController.move(_latestLocation!.latLng, 15.0);
    }
  }

  double _calculateTotalDistanceKm() {
    if (_routeHistory.length < 2) return 0.0;
    final distance = const Distance();
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
        (_routeHistory.isNotEmpty ? _routeHistory.last.latLng : const LatLng(0, 0));

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
            icon: Icon(_showBreadcrumbs ? Icons.timeline : Icons.timeline_outlined),
            tooltip: _showBreadcrumbs ? 'Hide Trail' : 'Show Trail',
            onPressed: () => setState(() => _showBreadcrumbs = !_showBreadcrumbs),
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
          // OpenStreetMap Map Layer
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: 15.0,
              onPositionChanged: (pos, hasGesture) {
                if (hasGesture && _isFollowingChild) {
                  setState(() => _isFollowingChild = false);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.parentapp',
              ),

              // Breadcrumb Polylines
              if (_showBreadcrumbs && _routeHistory.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routeHistory.map((p) => p.latLng).toList(),
                      strokeWidth: 4.5,
                      color: Colors.blue.shade600.withOpacity(0.85),
                      borderStrokeWidth: 1.5,
                      borderColor: Colors.white,
                    ),
                  ],
                ),

              // Accuracy Circle around Current Position
              if (activeLocation != null && activeLocation.accuracy != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: activeLocation.latLng,
                      radius: (activeLocation.accuracy! / 2).clamp(15.0, 100.0),
                      useRadiusInMeter: false,
                      color: Colors.blue.withOpacity(0.12),
                      borderColor: Colors.blue.withOpacity(0.35),
                      borderStrokeWidth: 1.5,
                    ),
                  ],
                ),

              // Waypoints and Child Avatar Marker
              MarkerLayer(
                markers: [
                  // Historical waypoint dots
                  if (_showBreadcrumbs && _routeHistory.isNotEmpty)
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

                  // Active Location Pin / Marker
                  if (activeLocation != null)
                    Marker(
                      point: activeLocation.latLng,
                      width: 54,
                      height: 54,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.person_pin_circle,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Top Filter Chips Bar
          Positioned(
            top: 12,
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

          // Floating Action Buttons (Recenter / Zoom / Fit)
          Positioned(
            right: 16,
            bottom: 210,
            child: Column(
              children: [
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

          // Bottom Telemetry & Timeline Card
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
                      const Center(child: Padding(
                        padding: EdgeInsets.all(8.0),
                        child: LinearProgressIndicator(),
                      ))
                    else if (_error != null)
                      Text(_error!, style: TextStyle(color: theme.colorScheme.error))
                    else if (activeLocation == null)
                      const Text('No location data recorded yet for this period.')
                    else ...[
                      // Location coordinates and recorded time
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
                              _scrubbedPointIndex != null ? Icons.history : Icons.navigation,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _scrubbedPointIndex != null
                                      ? 'Historical Waypoint (#${_scrubbedPointIndex! + 1}/${_routeHistory.length})'
                                      : 'Current Location',
                                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'Time: ${DateFormat('h:mm:ss a, MMM d').format(activeLocation.recordedAt)}',
                                  style: theme.textTheme.bodySmall,
                                ),
                                Text(
                                  'Coords: ${activeLocation.latitude.toStringAsFixed(5)}, ${activeLocation.longitude.toStringAsFixed(5)}',
                                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const Divider(height: 20),

                      // Metrics row: Speed, Battery, Accuracy, Total Distance
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _MetricItem(
                            icon: Icons.speed,
                            label: 'Speed',
                            value: activeLocation.speedKmh != null
                                ? '${activeLocation.speedKmh!.toStringAsFixed(1)} km/h'
                                : '--',
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

                      // Timeline scrubber slider when route history is available
                      if (_routeHistory.length > 1) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text('Route Scrubber', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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
                          },
                        ),
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

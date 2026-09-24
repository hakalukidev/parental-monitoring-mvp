import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../models/geofence.dart';
import '../services/api_service.dart';
import '../services/geocoding_service.dart';

class EditGeofenceScreen extends StatefulWidget {
  final String childId;
  final String childName;
  final Geofence? existingGeofence;
  final LatLng? initialCenter;

  const EditGeofenceScreen({
    super.key,
    required this.childId,
    required this.childName,
    this.existingGeofence,
    this.initialCenter,
  });

  @override
  State<EditGeofenceScreen> createState() => _EditGeofenceScreenState();
}

class _EditGeofenceScreenState extends State<EditGeofenceScreen> {
  final _formKey = GlobalKey<FormState>();
  final MapController _mapController = MapController();
  final GeocodingService _geocodingService = GeocodingService();

  late TextEditingController _nameController;
  late LatLng _center;
  late double _radius;
  late GeofenceZoneType _zoneType;
  late GeofenceTriggerType _triggerType;
  late bool _isEnabled;
  late String _colorHex;
  List<int> _selectedDays = [0, 1, 2, 3, 4, 5, 6];

  String? _resolvedAddress;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final eg = widget.existingGeofence;
    _nameController = TextEditingController(text: eg?.name ?? '');
    _center = eg?.latLng ?? widget.initialCenter ?? const LatLng(37.7749, -122.4194);
    _radius = eg?.radius ?? 200.0;
    _zoneType = eg?.zoneType ?? GeofenceZoneType.safeZone;
    _triggerType = eg?.triggerType ?? GeofenceTriggerType.exit;
    _isEnabled = eg?.isEnabled ?? true;
    _colorHex = eg?.colorHex ?? '#2196F3';
    if (eg?.schedule?.daysOfWeek != null && eg!.schedule!.daysOfWeek.isNotEmpty) {
      _selectedDays = List<int>.from(eg.schedule!.daysOfWeek);
    }

    _updateAddress(_center.latitude, _center.longitude);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _updateAddress(double lat, double lon) async {
    final address = await _geocodingService.reverseGeocode(lat, lon);
    if (mounted && address != null) {
      setState(() => _resolvedAddress = address);
    }
  }

  Future<void> _centerOnParentLocation() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        final req = await Geolocator.requestPermission();
        if (req == LocationPermission.denied || req == LocationPermission.deniedForever) return;
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final newCenter = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _center = newCenter;
      });
      _mapController.move(newCenter, 15);
      _updateAddress(newCenter.latitude, newCenter.longitude);
    } catch (_) {}
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final payload = {
      'name': _nameController.text.trim(),
      'latitude': _center.latitude,
      'longitude': _center.longitude,
      'radius': _radius,
      'address': _resolvedAddress ?? '',
      'zoneType': _zoneType.toApiValue(),
      'triggerType': _triggerType.toApiValue(),
      'isEnabled': _isEnabled,
      'colorHex': _colorHex,
      'schedule': {
        'daysOfWeek': _selectedDays,
      },
    };

    try {
      if (widget.existingGeofence != null) {
        await ApiService.instance.updateGeofence(
          widget.childId,
          widget.existingGeofence!.id,
          payload,
        );
      } else {
        await ApiService.instance.createGeofence(widget.childId, payload);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Boundary?'),
        content: Text('Are you sure you want to delete "${widget.existingGeofence!.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await ApiService.instance.deleteGeofence(widget.childId, widget.existingGeofence!.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }

  Color get _zoneColor {
    if (_zoneType == GeofenceZoneType.restrictedZone) {
      return Colors.red;
    }
    return Colors.teal;
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingGeofence != null;
    final dayNames = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Boundary' : 'New Safety Boundary'),
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Delete Boundary',
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red))),
                  ],
                ),
              ),

            // Boundary Name
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Boundary Name',
                hintText: 'e.g. Home, Lincoln High School, Central Park',
                prefixIcon: Icon(Icons.bookmark_outline),
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a name' : null,
            ),
            const SizedBox(height: 16),

            // Zone Type Selector (Safe Zone vs Restricted)
            SegmentedButton<GeofenceZoneType>(
              segments: const [
                ButtonSegment(
                  value: GeofenceZoneType.safeZone,
                  icon: Icon(Icons.shield, color: Colors.teal),
                  label: Text('Safe Zone'),
                ),
                ButtonSegment(
                  value: GeofenceZoneType.restrictedZone,
                  icon: Icon(Icons.dangerous, color: Colors.red),
                  label: Text('Restricted Zone'),
                ),
              ],
              selected: {_zoneType},
              onSelectionChanged: (newSel) {
                setState(() {
                  _zoneType = newSel.first;
                  _triggerType = _zoneType == GeofenceZoneType.safeZone
                      ? GeofenceTriggerType.exit
                      : GeofenceTriggerType.entry;
                });
              },
            ),
            const SizedBox(height: 16),

            // Trigger Type
            Text('Alert Trigger', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Alert on Leave (Exit)'),
                  selected: _triggerType == GeofenceTriggerType.exit,
                  onSelected: (val) {
                    if (val) setState(() => _triggerType = GeofenceTriggerType.exit);
                  },
                ),
                ChoiceChip(
                  label: const Text('Alert on Enter (Arrival)'),
                  selected: _triggerType == GeofenceTriggerType.entry,
                  onSelected: (val) {
                    if (val) setState(() => _triggerType = GeofenceTriggerType.entry);
                  },
                ),
                ChoiceChip(
                  label: const Text('Alert on Both'),
                  selected: _triggerType == GeofenceTriggerType.both,
                  onSelected: (val) {
                    if (val) setState(() => _triggerType = GeofenceTriggerType.both);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Interactive Map & Boundary Circle
            Card(
              clipBehavior: Clip.antiAlias,
              elevation: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    color: Colors.grey.shade100,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Tap map to place boundary center',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        IconButton(
                          icon: const Icon(Icons.my_location, size: 20),
                          tooltip: 'Center on my location',
                          onPressed: _centerOnParentLocation,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 280,
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _center,
                        initialZoom: 15,
                        onTap: (tapPos, point) {
                          setState(() {
                            _center = point;
                          });
                          _updateAddress(point.latitude, point.longitude);
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'dev.hakaluki.seftly.parent',
                        ),
                        CircleLayer(
                          circles: [
                            CircleMarker(
                              point: _center,
                              radius: _radius,
                              useRadiusInMeter: true,
                              color: _zoneColor.withValues(alpha: 0.25),
                              borderColor: _zoneColor,
                              borderStrokeWidth: 2.5,
                            ),
                          ],
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _center,
                              width: 40,
                              height: 40,
                              child: Icon(
                                Icons.location_pin,
                                color: _zoneColor,
                                size: 40,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_resolvedAddress != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.place, size: 16, color: Colors.grey),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _resolvedAddress!,
                              style: const TextStyle(fontSize: 12, color: Colors.black87),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Radius Slider & Presets
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Boundary Radius', style: Theme.of(context).textTheme.titleSmall),
                Text(
                  '${_radius.toInt()} meters',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _zoneColor,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            Slider(
              value: _radius,
              min: 50,
              max: 2000,
              divisions: 39,
              activeColor: _zoneColor,
              label: '${_radius.toInt()}m',
              onChanged: (val) {
                setState(() => _radius = val);
              },
            ),
            Wrap(
              spacing: 8,
              children: [100, 250, 500, 1000, 2000].map((preset) {
                return ActionChip(
                  label: Text(preset >= 1000 ? '${preset ~/ 1000}km' : '${preset}m'),
                  onPressed: () {
                    setState(() => _radius = preset.toDouble());
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Schedule Days
            Text('Active Days', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(7, (i) {
                final isSelected = _selectedDays.contains(i);
                return FilterChip(
                  label: Text(dayNames[i]),
                  selected: isSelected,
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        _selectedDays.add(i);
                      } else {
                        if (_selectedDays.length > 1) {
                          _selectedDays.remove(i);
                        }
                      }
                      _selectedDays.sort();
                    });
                  },
                );
              }),
            ),
            const SizedBox(height: 16),

            // Active Switch
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Boundary Protection Enabled'),
              subtitle: const Text('Monitors GPS location and triggers alerts'),
              value: _isEnabled,
              onChanged: (val) => setState(() => _isEnabled = val),
            ),
            const SizedBox(height: 24),

            // Save Button
            FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(
                _saving ? 'Saving...' : (isEditing ? 'Update Boundary' : 'Create Boundary'),
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

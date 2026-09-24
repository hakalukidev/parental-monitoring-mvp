import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../models/geofence.dart';
import '../models/geofence_event.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import 'edit_geofence_screen.dart';
import 'location_tracking_screen.dart';

class GeofencesScreen extends StatefulWidget {
  final String childId;
  final String childName;
  final LatLng? latestChildLocation;
  final SocketService? socketService;

  const GeofencesScreen({
    super.key,
    required this.childId,
    required this.childName,
    this.latestChildLocation,
    this.socketService,
  });

  @override
  State<GeofencesScreen> createState() => _GeofencesScreenState();
}

class _GeofencesScreenState extends State<GeofencesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<Geofence> _geofences = [];
  List<GeofenceEvent> _events = [];
  int _unreadEventsCount = 0;
  bool _loadingGeofences = true;
  bool _loadingEvents = true;
  String? _geofenceError;
  String? _eventsError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadGeofences();
    _loadEvents();
    _setupSocketAlertListener();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _setupSocketAlertListener() {
    widget.socketService?.onGeofenceAlert((data) {
      if (!mounted) return;
      if (data['childId'] == widget.childId) {
        _loadEvents();
        _loadGeofences(); // Refresh state badges
      }
    });
  }

  Future<void> _loadGeofences() async {
    setState(() {
      _loadingGeofences = true;
      _geofenceError = null;
    });

    try {
      final raw = await ApiService.instance.listGeofences(widget.childId);
      if (mounted) {
        setState(() {
          _geofences = raw.map((e) => Geofence.fromJson(e as Map<String, dynamic>)).toList();
          _loadingGeofences = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _geofenceError = e.toString();
          _loadingGeofences = false;
        });
      }
    }
  }

  Future<void> _loadEvents() async {
    setState(() {
      _loadingEvents = true;
      _eventsError = null;
    });

    try {
      final res = await ApiService.instance.listGeofenceEvents(widget.childId);
      if (mounted) {
        final rawEvents = (res['events'] as List<dynamic>?) ?? [];
        setState(() {
          _events = rawEvents.map((e) => GeofenceEvent.fromJson(e as Map<String, dynamic>)).toList();
          _unreadEventsCount = (res['unreadCount'] as num?)?.toInt() ?? 0;
          _loadingEvents = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _eventsError = e.toString();
          _loadingEvents = false;
        });
      }
    }
  }

  Future<void> _toggleGeofence(Geofence geofence) async {
    try {
      await ApiService.instance.toggleGeofence(widget.childId, geofence.id);
      _loadGeofences();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e')),
        );
      }
    }
  }

  Future<void> _markAllRead() async {
    try {
      await ApiService.instance.markAllGeofenceEventsRead(widget.childId);
      _loadEvents();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.childName}\'s Safe Boundaries'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(
              icon: Icon(Icons.shield_outlined),
              text: 'Boundaries',
            ),
            Tab(
              icon: Badge(
                isLabelVisible: _unreadEventsCount > 0,
                label: Text('$_unreadEventsCount'),
                child: const Icon(Icons.notifications_active_outlined),
              ),
              text: 'Alert Logs',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildBoundariesTab(),
          _buildAlertsTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => EditGeofenceScreen(
                childId: widget.childId,
                childName: widget.childName,
                initialCenter: widget.latestChildLocation,
              ),
            ),
          );
          if (created == true) {
            _loadGeofences();
          }
        },
        icon: const Icon(Icons.add_location_alt),
        label: const Text('Add Boundary'),
      ),
    );
  }

  Widget _buildBoundariesTab() {
    if (_loadingGeofences) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_geofenceError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_geofenceError!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadGeofences, child: const Text('Retry')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadGeofences,
      child: _geofences.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shield_moon_outlined, size: 72, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text(
                      'No Geofences Configured',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Create safety zones like Home, School, or Sports Club. You\'ll receive instant alerts when ${widget.childName} enters or leaves.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () async {
                        final created = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) => EditGeofenceScreen(
                              childId: widget.childId,
                              childName: widget.childName,
                              initialCenter: widget.latestChildLocation,
                            ),
                          ),
                        );
                        if (created == true) _loadGeofences();
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Create First Boundary'),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 80),
              itemCount: _geofences.length,
              itemBuilder: (ctx, i) {
                final g = _geofences[i];
                final isSafe = g.zoneType == GeofenceZoneType.safeZone;
                final zoneColor = isSafe ? Colors.teal : Colors.red;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 1.5,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: zoneColor.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isSafe ? Icons.shield : Icons.dangerous,
                                color: zoneColor,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    g.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    isSafe ? 'Safe Zone (${g.radius.toInt()}m radius)' : 'Restricted Zone (${g.radius.toInt()}m radius)',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: g.isEnabled,
                              onChanged: (val) => _toggleGeofence(g),
                            ),
                          ],
                        ),
                        if (g.address.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.place_outlined, size: 14, color: Colors.grey),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  g.address,
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const Divider(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // State status
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: g.lastState == 'INSIDE'
                                    ? Colors.green.shade50
                                    : g.lastState == 'OUTSIDE'
                                        ? Colors.orange.shade50
                                        : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: g.lastState == 'INSIDE'
                                      ? Colors.green.shade300
                                      : g.lastState == 'OUTSIDE'
                                          ? Colors.orange.shade300
                                          : Colors.grey.shade300,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    g.lastState == 'INSIDE'
                                        ? Icons.check_circle_outline
                                        : Icons.location_off_outlined,
                                    size: 14,
                                    color: g.lastState == 'INSIDE' ? Colors.green : Colors.orange,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Child Status: ${g.lastState}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: g.lastState == 'INSIDE'
                                          ? Colors.green.shade800
                                          : Colors.orange.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Action buttons
                            Row(
                              children: [
                                IconButton.filledTonal(
                                  iconSize: 18,
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.edit_outlined),
                                  tooltip: 'Edit Boundary',
                                  onPressed: () async {
                                    final updated = await Navigator.of(context).push<bool>(
                                      MaterialPageRoute(
                                        builder: (_) => EditGeofenceScreen(
                                          childId: widget.childId,
                                          childName: widget.childName,
                                          existingGeofence: g,
                                        ),
                                      ),
                                    );
                                    if (updated == true) _loadGeofences();
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildAlertsTab() {
    if (_loadingEvents) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_eventsError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_eventsError!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadEvents, child: const Text('Retry')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadEvents,
      child: _events.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_off_outlined, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text('No Boundary Alerts Yet', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    'Transitions and boundary exit alerts will appear here in real-time.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                if (_unreadEventsCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: Colors.amber.shade50,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$_unreadEventsCount new unread alert${_unreadEventsCount > 1 ? "s" : ""}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.amber.shade900,
                            fontSize: 13,
                          ),
                        ),
                        TextButton(
                          onPressed: _markAllRead,
                          child: const Text('Mark all as read'),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _events.length,
                    itemBuilder: (ctx, i) {
                      final ev = _events[i];
                      final isExit = ev.isExit;
                      final isRestricted = ev.isRestricted;
                      final alertColor = isRestricted || isExit ? Colors.red : Colors.green;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        color: ev.isRead ? null : Colors.red.shade50.withValues(alpha: 0.3),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: alertColor.withValues(alpha: 0.15),
                            child: Icon(
                              isExit
                                  ? Icons.logout
                                  : isRestricted
                                      ? Icons.warning_amber
                                      : Icons.login,
                              color: alertColor,
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  isExit
                                      ? 'Left ${ev.geofenceName}'
                                      : 'Entered ${ev.geofenceName}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              if (!ev.isRead)
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                '${DateFormat('MMM d, h:mm a').format(ev.triggeredAt)} • Distance: ${ev.distanceFromCenter.toInt()}m',
                                style: const TextStyle(fontSize: 12),
                              ),
                              if (ev.address.isNotEmpty)
                                Text(
                                  ev.address,
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.map_outlined),
                            tooltip: 'View on Map',
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => LocationTrackingScreen(
                                    childId: widget.childId,
                                    childName: widget.childName,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

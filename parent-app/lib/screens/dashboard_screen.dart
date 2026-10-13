import '../design/seftly_widgets.dart';
import '../design/seftly_theme.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../models/child.dart';
import '../models/app_policy.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/notification_service.dart';
import 'create_child_screen.dart';
import 'screen_share_screen.dart';
import 'camera_stream_screen.dart';
import 'location_tracking_screen.dart';
import 'app_blocker_screen.dart';
import 'web_filter_screen.dart';
import 'browsing_history_screen.dart';
import 'geofences_screen.dart';
import 'app_usage_report_screen.dart';
import 'login_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  List<Child> _children = [];
  bool _loading = true;
  String? _error;
  SocketService? _socketService;
  Timer? _autoSyncTimer;
  DateTime? _lastSync;
  bool _syncFailed = false, _syncing = false;
  int _tab = 0;
  List<Map<String, dynamic>> _alerts = [];
  bool _alertsAvailable = false;
  bool get _statusCurrent =>
      !_syncFailed &&
      _lastSync != null &&
      DateTime.now().difference(_lastSync!).inSeconds < 90;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initSocketAndLoad();
    _startAutoSyncTimer();
    _syncUnreadGeofenceNotifications();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSyncTimer?.cancel();
    _socketService?.disconnect();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _silentSync();
      _syncUnreadGeofenceNotifications();
      if (_socketService?.isConnected != true) {
        _reconnectSocket();
      }
    }
  }

  void _startAutoSyncTimer() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _silentSync();
      }
    });
  }

  Future<void> _silentSync() async {
    if (_syncing) {
      return;
    }
    _syncing = true;
    try {
      final raw = await ApiService.instance.listChildren();
      if (!mounted) {
        return;
      }
      setState(() {
        _children =
            raw.map((e) => Child.fromJson(e as Map<String, dynamic>)).toList();
        _lastSync = DateTime.now();
        _syncFailed = false;
      });
      _syncUnreadGeofenceNotifications();
      if (_socketService != null && _socketService?.isConnected != true) {
        _reconnectSocket();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _syncFailed = true);
      }
    } finally {
      _syncing = false;
    }
  }

  Future<void> _syncUnreadGeofenceNotifications() async {
    try {
      final res = await ApiService.instance.getUnreadGeofenceEventsSummary();
      final events = (res['events'] as List<dynamic>?) ?? [];
      if (mounted) {
        setState(() => _alertsAvailable = true);
      }
      if (mounted) {
        setState(() => _alerts =
            events.map((e) => Map<String, dynamic>.from(e as Map)).toList());
      }
      for (final raw in events) {
        final ev = raw as Map<String, dynamic>;
        final eventId = ev['_id']?.toString() ?? ev['id']?.toString() ?? '';
        final childId = ev['childId']?.toString() ?? '';
        final childName = ev['childName']?.toString() ?? 'Child';
        final geofenceId = ev['geofenceId']?.toString() ?? '';
        final geofenceName = ev['geofenceName']?.toString() ?? 'Safety Zone';
        final eventType = ev['eventType']?.toString() ?? 'EXIT';
        final zoneType = ev['zoneType']?.toString() ?? 'SAFE_ZONE';
        final location = ev['location'] as Map<String, dynamic>?;
        final lat = (location?['latitude'] as num?)?.toDouble() ??
            (ev['latitude'] as num?)?.toDouble() ??
            0.0;
        final lon = (location?['longitude'] as num?)?.toDouble() ??
            (ev['longitude'] as num?)?.toDouble() ??
            0.0;
        final triggeredAtStr =
            ev['triggeredAt']?.toString() ?? ev['timestamp']?.toString();
        final timestamp = triggeredAtStr != null
            ? DateTime.tryParse(triggeredAtStr) ?? DateTime.now()
            : DateTime.now();
        final title = ev['title']?.toString();
        final body = ev['body']?.toString();

        await NotificationService.instance.showGeofenceAlertNotification(
          eventId: eventId,
          childId: childId,
          childName: childName,
          geofenceId: geofenceId,
          geofenceName: geofenceName,
          eventType: eventType,
          zoneType: zoneType,
          latitude: lat,
          longitude: lon,
          timestamp: timestamp,
          title: title,
          body: body,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _alertsAvailable = false);
      }
    }
  }

  void _reconnectSocket() async {
    final token = await ApiService.instance.accessToken;
    if (token != null && mounted) {
      _socketService?.updateTokenAndReconnect(token,
          onAuthError: _reconnectSocket);
    }
  }

  Future<void> _initSocketAndLoad() async {
    await _refresh();
    try {
      final token = await ApiService.instance.accessToken;
      if (token != null) {
        final sock = SocketService();
        void connectWithAuth() {
          sock.connect(
            token,
            onAuthError: () async {
              final ok = await ApiService.instance.refreshToken();
              if (ok) {
                final freshToken = await ApiService.instance.accessToken;
                if (freshToken != null && mounted) {
                  sock.updateTokenAndReconnect(freshToken,
                      onAuthError: connectWithAuth);
                }
              }
            },
          );
        }

        connectWithAuth();

        // Initial snapshot from server upon connecting
        sock.onInitialChildrenPresence((data) {
          if (!mounted) {
            return;
          }
          final list = (data['children'] as List<dynamic>?) ?? [];
          setState(() {
            for (final item in list) {
              final map = Map<String, dynamic>.from(item as Map);
              final cid = map['childId'] as String?;
              final status = map['status'] as String?;
              final devName = map['deviceName'] as String?;
              final platform = map['platform'] as String?;
              if (cid != null && status != null) {
                final idx = _children.indexWhere((c) => c.id == cid);
                if (idx != -1) {
                  final current = _children[idx];
                  final dev = current.device;
                  _children[idx] = current.withPresence(ChildDevice(
                    id: dev?.id ?? '',
                    deviceName: devName ?? dev?.deviceName ?? 'Android device',
                    platform: platform ?? dev?.platform ?? 'Android',
                    status: status.toUpperCase(),
                    lastSeen:
                        DateTime.tryParse(map['lastSeen']?.toString() ?? '') ??
                            dev?.lastSeen,
                    lastLocation: dev?.lastLocation,
                  ));
                }
              }
            }
          });
        });

        // Real-time status changes
        sock.onChildStatusChanged((data) {
          if (!mounted) {
            return;
          }
          final cid = data['childId'] as String?;
          final status = data['status'] as String?;
          final devName = data['deviceName'] as String?;
          if (cid != null && status != null) {
            setState(() {
              final idx = _children.indexWhere((c) => c.id == cid);
              if (idx != -1) {
                final current = _children[idx];
                final dev = current.device;
                _children[idx] = current.withPresence(ChildDevice(
                  id: dev?.id ?? '',
                  deviceName: devName ?? dev?.deviceName ?? 'Android device',
                  platform: dev?.platform ?? 'Android',
                  status: status.toUpperCase(),
                  lastSeen:
                      DateTime.tryParse(data['lastSeen']?.toString() ?? '') ??
                          dev?.lastSeen,
                  lastLocation: dev?.lastLocation,
                ));
              }
            });
          }
        });

        sock.socket.on('operation_error', (raw) {
          if (!mounted) {
            return;
          }
          final data = Map<String, dynamic>.from(raw as Map);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(data['code'] == '409'
                  ? 'This request has expired or was already handled.'
                  : 'This action could not be completed. Refresh and try again.')));
        });
        sock.onUnblockRequest((data) {
          if (!mounted) {
            return;
          }
          final req = UnblockRequest.fromJson(data);
          _showUnblockRequestDialog(req);
        });

        sock.onGeofenceAlert((data) {
          if (!mounted) {
            return;
          }
          final eventId = data['eventId']?.toString() ??
              data['id']?.toString() ??
              data['_id']?.toString() ??
              '';
          final childId = data['childId']?.toString() ?? '';
          final childName = data['childName']?.toString() ?? 'Child';
          final geofenceId = data['geofenceId']?.toString() ?? '';
          final geofenceName =
              data['geofenceName']?.toString() ?? 'Safety Zone';
          final eventType = data['eventType']?.toString() ?? 'EXIT';
          final zoneType = data['zoneType']?.toString() ?? 'SAFE_ZONE';
          final lat = (data['latitude'] as num?)?.toDouble() ?? 0.0;
          final lon = (data['longitude'] as num?)?.toDouble() ?? 0.0;
          final timestamp = DateTime.now();
          final title = data['title']?.toString();
          final body = data['body']?.toString();

          NotificationService.instance.showGeofenceAlertNotification(
            eventId: eventId,
            childId: childId,
            childName: childName,
            geofenceId: geofenceId,
            geofenceName: geofenceName,
            eventType: eventType,
            zoneType: zoneType,
            latitude: lat,
            longitude: lon,
            timestamp: timestamp,
            title: title,
            body: body,
          );

          _showGeofenceAlertDialog(data);
        });

        _socketService = sock;
      }
    } catch (_) {}
  }

  void _showGeofenceAlertDialog(Map<String, dynamic> data) {
    final childName = data['childName']?.toString() ?? 'Child';
    final childId = data['childId']?.toString() ?? '';
    final geofenceName = data['geofenceName']?.toString() ?? 'Boundary';
    final eventType = data['eventType']?.toString() ?? 'EXIT';
    final message = data['message']?.toString() ??
        (eventType == 'EXIT'
            ? '$childName left $geofenceName'
            : '$childName arrived at $geofenceName');
    final isExit = eventType == 'EXIT';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isExit ? Icons.warning_amber_rounded : Icons.shield_outlined,
              color: isExit ? Colors.red : Colors.teal,
            ),
            const SizedBox(width: 8),
            const Expanded(child: Text('Geofence Alert!')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isExit ? Colors.red.shade50 : Colors.teal.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isExit ? Colors.red.shade200 : Colors.teal.shade200,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isExit ? Icons.location_off : Icons.location_on,
                    color: isExit ? Colors.red : Colors.teal,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color:
                            isExit ? Colors.red.shade900 : Colors.teal.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Recorded at: ${DateFormat('h:mm a, MMM d').format(DateTime.tryParse(data['triggeredAt']?.toString() ?? '')?.toLocal() ?? DateTime.now())}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
              tooltip: 'Enable family notifications',
              icon: const Icon(Icons.notifications_none_rounded),
              onPressed: () async {
                final allow = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                            title: const Text('Family notifications'),
                            content: const Text(
                                'Allow Seftly to show recorded safety-zone alerts on this device. You can change this in your device settings.'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Not now')),
                              FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Continue'))
                            ]));
                if (allow == true) {
                  await NotificationService.instance.requestPermissions();
                }
              }),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Dismiss'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: isExit ? Colors.red : Colors.teal,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              final lat = (data['latitude'] as num?)?.toDouble();
              final lon = (data['longitude'] as num?)?.toDouble();
              final tsStr = data['timestamp']?.toString();
              final timestamp =
                  tsStr != null ? DateTime.tryParse(tsStr) : DateTime.now();
              final geofenceId = data['geofenceId']?.toString();

              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LocationTrackingScreen(
                    childId: childId,
                    childName: childName,
                    initialTrackingMode: MapTrackingMode.historyTrail,
                    focusTimestamp: timestamp,
                    focusLocation:
                        (lat != null && lon != null) ? LatLng(lat, lon) : null,
                    highlightGeofenceId: geofenceId,
                    breachType: eventType,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.map, size: 18),
            label: const Text('View Trail on Map'),
          ),
        ],
      ),
    );
  }

  void _showUnblockRequestDialog(UnblockRequest req) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.shield, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(child: Text('${req.childName} Requests Access')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('App: ${req.appName}',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(req.packageName,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Reason: "${req.reason}"',
                  style: const TextStyle(fontStyle: FontStyle.italic)),
            ),
            const SizedBox(height: 12),
            const Text('Grant temporary extra time?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _socketService?.sendUnblockResponse(
                requestId: req.requestId,
                childId: req.childId,
                packageName: req.packageName,
                approved: false,
              );
            },
            child: const Text('Decline', style: TextStyle(color: Colors.red)),
          ),
          FilledButton.tonal(
            onPressed: () {
              Navigator.pop(ctx);
              _socketService?.sendUnblockResponse(
                requestId: req.requestId,
                childId: req.childId,
                packageName: req.packageName,
                approved: true,
                temporaryDurationMinutes: 15,
              );
            },
            child: const Text('Allow 15 min'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _socketService?.sendUnblockResponse(
                requestId: req.requestId,
                childId: req.childId,
                packageName: req.packageName,
                approved: true,
                temporaryDurationMinutes: 60,
              );
            },
            child: const Text('Allow 1 Hour'),
          ),
        ],
      ),
    );
  }

  Future<void> _refresh() async {
    if (!mounted || _syncing) {
      return;
    }
    _syncing = true;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await ApiService.instance.listChildren();
      if (!mounted) {
        return;
      }
      setState(() {
        _children =
            raw.map((e) => Child.fromJson(e as Map<String, dynamic>)).toList();
        _lastSync = DateTime.now();
        _syncFailed = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _syncFailed = true;
        });
      }
    } finally {
      _syncing = false;
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    _socketService?.disconnect();
    await ApiService.instance.logout();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _addChild() async {
    final created = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const CreateChildScreen()));
    if (created == true && mounted) {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _statusCurrent;
    final online = current ? _children.where((c) => c.isOnline).length : null;
    return Scaffold(
      appBar: AppBar(
          title: const Row(children: [
            SeftlyMark(size: 32),
            SizedBox(width: 10),
            Expanded(
                child: Text('seftly',
                    overflow: TextOverflow.ellipsis, maxLines: 1))
          ]),
          actions: [
            IconButton(
                tooltip: 'Refresh family',
                onPressed: _loading ? null : _refresh,
                icon: const Icon(Icons.refresh_rounded)),
            IconButton(
                tooltip: 'Log out',
                onPressed: _logout,
                icon: const Icon(Icons.logout_rounded))
          ]),
      bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.people_outline_rounded),
                selectedIcon: Icon(Icons.people_rounded),
                label: 'Family'),
            NavigationDestination(
                icon: Icon(Icons.notifications_none_rounded),
                selectedIcon: Icon(Icons.notifications_rounded),
                label: 'Activity')
          ]),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              onPressed: _addChild,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add a child'))
          : null,
      body: SafeArea(
          child: _loading && _children.isEmpty
              ? const FamilyLoadingView()
              : _error != null && _children.isEmpty
                  ? SeftlyStateView(
                      icon: Icons.cloud_off_outlined,
                      title: 'We couldn’t load your family',
                      message: _error!,
                      error: true,
                      onAction: _refresh)
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: LayoutBuilder(
                          builder: (context, size) => ListView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: EdgeInsets.fromLTRB(
                                      size.maxWidth > 1100
                                          ? (size.maxWidth - 1060) / 2
                                          : 20,
                                      24,
                                      size.maxWidth > 1100
                                          ? (size.maxWidth - 1060) / 2
                                          : 20,
                                      100),
                                  children: [
                                    Text(
                                        _tab == 0
                                            ? 'Hello, parent.'
                                            : 'Your family’s activity',
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineMedium),
                                    const SizedBox(height: 8),
                                    Text(
                                        _tab == 0
                                            ? 'Your family at a glance. Choose a child to check in.'
                                            : 'Recorded safety-zone alerts from your children’s devices.',
                                        style: TextStyle(color: context.muted)),
                                    const SizedBox(height: 24),
                                    Wrap(
                                        spacing: 12,
                                        runSpacing: 12,
                                        children: [
                                          _FamilyStat(
                                              width: MediaQuery.textScalerOf(
                                                              context)
                                                          .scale(1) >
                                                      1.5
                                                  ? 148
                                                  : ((size.maxWidth - 64) / 3)
                                                      .clamp(90, 180),
                                              label: 'Children',
                                              value: '${_children.length}',
                                              icon:
                                                  Icons.people_outline_rounded),
                                          _FamilyStat(
                                              width: MediaQuery.textScalerOf(
                                                              context)
                                                          .scale(1) >
                                                      1.5
                                                  ? 148
                                                  : ((size.maxWidth - 64) / 3)
                                                      .clamp(90, 180),
                                              label: 'Online now',
                                              value: online?.toString() ??
                                                  'Unknown',
                                              icon: Icons.wifi_rounded),
                                          _FamilyStat(
                                              width: MediaQuery.textScalerOf(
                                                              context)
                                                          .scale(1) >
                                                      1.5
                                                  ? 148
                                                  : ((size.maxWidth - 64) / 3)
                                                      .clamp(90, 180),
                                              label: 'Unread alerts',
                                              value: _alertsAvailable
                                                  ? '${_alerts.length}'
                                                  : 'Unknown',
                                              icon: Icons
                                                  .notifications_none_rounded),
                                        ]),
                                    const SizedBox(height: 16),
                                    Wrap(spacing: 8, runSpacing: 8, children: [
                                      StatusPill(
                                          label: _syncFailed
                                              ? 'Showing cached information'
                                              : _lastSync == null
                                                  ? 'Not synchronized'
                                                  : 'Synced ${DateFormat('h:mm a').format(_lastSync!.toLocal())}',
                                          active: current),
                                      StatusPill(
                                          label: _socketService?.isConnected ==
                                                  true
                                              ? 'Live updates connected'
                                              : 'Live updates unavailable',
                                          active: _socketService?.isConnected ==
                                              true)
                                    ]),
                                    if (_syncFailed)
                                      Padding(
                                          padding:
                                              const EdgeInsets.only(top: 12),
                                          child: Text(
                                              'We couldn’t refresh. Connection status is unverified until the next successful update.',
                                              style: TextStyle(
                                                  color:
                                                      context.colors.error))),
                                    const SizedBox(height: 28),
                                    if (_tab == 0) ...[
                                      Text('Your children',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge),
                                      const SizedBox(height: 16),
                                      if (_children.isEmpty)
                                        SeftlyStateView(
                                            icon: Icons.family_restroom_rounded,
                                            title:
                                                'Start with your first child',
                                            message:
                                                'Create a child login, install Seftly Child on their Android device and complete setup together.',
                                            actionLabel: 'Add a child',
                                            onAction: _addChild),
                                      for (final child in _children)
                                        Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 20),
                                            child: ChildOverviewCard(
                                                key: ValueKey(child.id),
                                                child: child,
                                                socketService: _socketService,
                                                statusCurrent: current)),
                                    ] else if (!_alertsAvailable)
                                      SeftlyStateView(
                                          icon: Icons.cloud_off_outlined,
                                          title: 'Alerts unavailable',
                                          message:
                                              'We couldn’t refresh recorded alerts. Please try again.',
                                          onAction:
                                              _syncUnreadGeofenceNotifications)
                                    else if (_alerts.isEmpty)
                                      const SeftlyStateView(
                                          icon:
                                              Icons.notifications_none_rounded,
                                          title: 'No unread safety alerts',
                                          message:
                                              'New safety-zone alerts will appear here when a child’s device reports a crossing.')
                                    else ...[
                                      for (final alert in _alerts)
                                        Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 12),
                                            child: Card(
                                                child: ListTile(
                                                    contentPadding:
                                                        const EdgeInsets.all(
                                                            16),
                                                    leading:
                                                        Icon(Icons.location_on_outlined,
                                                            color: context
                                                                .colors
                                                                .primary),
                                                    title: Text(alert['title']
                                                            ?.toString() ??
                                                        alert['geofenceName']
                                                            ?.toString() ??
                                                        'Safety zone alert'),
                                                    subtitle: Text(
                                                        '${alert['childName'] ?? 'Child'} · ${alert['body'] ?? alert['eventType'] ?? ''}'),
                                                    trailing: const Icon(Icons.chevron_right_rounded),
                                                    onTap: () => _showGeofenceAlertDialog(alert)))),
                                    ],
                                  ])))),
    );
  }
}

class _FamilyStat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final double width;
  const _FamilyStat(
      {required this.label,
      required this.value,
      required this.icon,
      this.width = 148});
  @override
  Widget build(BuildContext context) => SizedBox(
      width: width,
      child: Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 22, color: context.colors.primary),
                    const SizedBox(height: 14),
                    Text(value,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(label,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: context.muted))
                  ]))));
}

class ChildOverviewCard extends StatelessWidget {
  final Child child;
  final SocketService? socketService;
  final bool statusCurrent;
  const ChildOverviewCard(
      {super.key,
      required this.child,
      this.socketService,
      this.statusCurrent = true});
  String _lastSeen() {
    final seen = child.device?.lastSeen;
    if (seen == null) return 'No device update yet';
    return 'Device updated ${DateFormat('MMM d, h:mm a').format(seen.toLocal())}';
  }

  @override
  Widget build(BuildContext context) {
    final online = statusCurrent && child.isOnline;
    final location = child.device?.lastLocation;
    final locFresh = location != null &&
        DateTime.now().difference(location.recordedAt).inMinutes < 5;
    void open(Widget page) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    final actions = <(IconData, String, String, VoidCallback?)>[
      (
        Icons.near_me_outlined,
        'Location',
        'Latest fix & route history',
        () => open(
            LocationTrackingScreen(childId: child.id, childName: child.name))
      ),
      (
        Icons.bar_chart_rounded,
        'App activity',
        'Usage & daily breakdown',
        () => open(AppUsageReportScreen(
            childId: child.id,
            childName: child.name,
            socketService: socketService))
      ),
      (
        Icons.apps_rounded,
        'App rules',
        'Limits, schedules & pause',
        () => open(AppBlockerScreen(childId: child.id, childName: child.name))
      ),
      (
        Icons.shield_outlined,
        'Safety zones',
        'Arrival & departure alerts',
        () => open(GeofencesScreen(
            childId: child.id,
            childName: child.name,
            socketService: socketService))
      ),
      (
        Icons.language_rounded,
        'Web rules',
        'Allow & block websites',
        () => open(WebFilterScreen(childId: child.id, childName: child.name))
      ),
      (
        Icons.history_rounded,
        'Browsing activity',
        'Reported website history',
        () => open(BrowsingHistoryScreen(
            childId: child.id,
            childName: child.name,
            socketService: socketService))
      ),
      (
        Icons.screen_share_outlined,
        'Screen sharing',
        'Approval on child device',
        online
            ? () => open(
                ScreenShareScreen(childId: child.id, childName: child.name))
            : null
      ),
      (
        Icons.videocam_outlined,
        'Camera check-in',
        'Approval on child device',
        online
            ? () => open(
                CameraStreamScreen(childId: child.id, childName: child.name))
            : null
      ),
    ];
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(
                    radius: 25,
                    backgroundColor: context.colors.primaryContainer,
                    foregroundColor: context.colors.onPrimaryContainer,
                    child: Text(child.name.characters.first.toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.w700))),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(child.name,
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 3),
                      Text('@${child.username}',
                          style: TextStyle(color: context.muted))
                    ]))
              ]),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                StatusPill(
                    label: !statusCurrent
                        ? 'Status unverified'
                        : child.device == null
                            ? 'Setup needed'
                            : online
                                ? 'Online'
                                : 'Offline',
                    active: online),
                if (child.isPremium != null)
                  StatusPill(
                      label: child.isPremium!
                          ? 'Access until ${child.expireDate == null ? 'renewal' : DateFormat('MMM d').format(child.expireDate!)}'
                          : 'Access expired')
              ]),
              const SizedBox(height: 14),
              Text(
                  child.device?.deviceName ??
                      'Connect Seftly Child to get started',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text(_lastSeen(),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: context.muted)),
              const SizedBox(height: 14),
              Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: context.colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            location == null
                                ? 'Location not reported yet'
                                : '${locFresh ? 'Recent location' : 'Last known location'} · ${DateFormat('MMM d, h:mm a').format(location.recordedAt.toLocal())}',
                            style: Theme.of(context).textTheme.labelLarge),
                        if (location != null) ...[
                          const SizedBox(height: 4),
                          Text(
                              '${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}${location.accuracy == null ? '' : ' · ±${location.accuracy!.round()} m'}',
                              style: Theme.of(context).textTheme.bodySmall)
                        ],
                        const SizedBox(height: 8),
                        Text(
                            child.recentUsage == null
                                ? 'App activity: awaiting a device report'
                                : 'Foreground app usage: ${((child.recentUsage!['totalScreenTimeSeconds'] as num? ?? 0) / 60).round()} min · ${child.recentUsage!['date'] ?? ''}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: context.muted)),
                      ])),
              const SizedBox(height: 20),
              LayoutBuilder(builder: (context, box) {
                final columns = box.maxWidth > 700
                    ? 4
                    : box.maxWidth > 280 &&
                            MediaQuery.textScalerOf(context).scale(1) < 1.5
                        ? 2
                        : 1;
                final width = (box.maxWidth - (columns - 1) * 10) / columns;
                return Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final (icon, title, subtitle, action) in actions.take(4))
                    SizedBox(
                        width: width,
                        child: _ChildAction(
                            icon: icon,
                            title: title,
                            subtitle: subtitle,
                            onTap: action))
                ]);
              }),
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: const Text('More family tools'),
                subtitle:
                    const Text('Web rules, browsing and approved check-ins'),
                children: [
                  for (final (icon, title, subtitle, action) in actions.skip(4))
                    ListTile(
                        leading: Icon(icon),
                        title: Text(title),
                        subtitle: Text(subtitle),
                        enabled: action != null,
                        onTap: action)
                ],
              ),
              if (!online)
                Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(
                        'Live sessions are available when the child device is confirmed online.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: context.muted))),
            ])));
  }
}

class _ChildAction extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;
  const _ChildAction(
      {required this.icon,
      required this.title,
      required this.subtitle,
      this.onTap});
  @override
  Widget build(BuildContext context) => Material(
      color: context.colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Icon(icon,
                    color:
                        onTap == null ? context.muted : context.colors.primary,
                    size: 22),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(title,
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(
                                  color: onTap == null
                                      ? context.muted
                                      : context.colors.onSurface)),
                      const SizedBox(height: 3),
                      Text(subtitle,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: context.muted))
                    ]))
              ]))));
}

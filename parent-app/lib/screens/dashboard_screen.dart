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
import 'child_detail_screen.dart';
import 'location_tracking_screen.dart';
import 'safety_alerts_screen.dart';
import 'login_screen.dart';
import '../theme/app_colors.dart';


class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  List<Child> _children = [];
  bool _loading = true;
  String? _error;
  SocketService? _socketService;
  Timer? _autoSyncTimer;

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
      if (mounted) _silentSync();
    });
  }

  Future<void> _silentSync() async {
    try {
      final raw = await ApiService.instance.listChildren();
      if (!mounted) return;
      setState(() {
        _children = raw.map((e) => Child.fromJson(e as Map<String, dynamic>)).toList();
      });
      _syncUnreadGeofenceNotifications();
    } catch (_) {}
  }

  Future<void> _syncUnreadGeofenceNotifications() async {
    try {
      final res = await ApiService.instance.getUnreadGeofenceEventsSummary();
      final events = (res['events'] as List<dynamic>?) ?? [];
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
        final lat = (location?['latitude'] as num?)?.toDouble() ?? (ev['latitude'] as num?)?.toDouble() ?? 0.0;
        final lon = (location?['longitude'] as num?)?.toDouble() ?? (ev['longitude'] as num?)?.toDouble() ?? 0.0;
        final triggeredAtStr = ev['triggeredAt']?.toString() ?? ev['timestamp']?.toString();
        final timestamp = triggeredAtStr != null ? DateTime.tryParse(triggeredAtStr) ?? DateTime.now() : DateTime.now();
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
    } catch (_) {}
  }

  void _reconnectSocket() async {
    final token = await ApiService.instance.accessToken;
    if (token != null && mounted) {
      _socketService?.updateTokenAndReconnect(token, onAuthError: _reconnectSocket);
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
                  sock.updateTokenAndReconnect(freshToken, onAuthError: connectWithAuth);
                }
              }
            },
          );
        }
        connectWithAuth();

        // Initial snapshot from server upon connecting
        sock.onInitialChildrenPresence((data) {
          if (!mounted) return;
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
                  _children[idx] = Child(
                    id: current.id,
                    name: current.name,
                    username: current.username,
                    device: ChildDevice(
                      id: dev?.id ?? '',
                      deviceName: devName ?? dev?.deviceName ?? 'Android Device',
                      platform: platform ?? dev?.platform ?? 'Android',
                      status: status.toUpperCase(),
                      lastSeen: status.toUpperCase() == 'ONLINE'
                          ? DateTime.now()
                          : (dev?.lastSeen ?? DateTime.now()),
                    ),
                  );
                }
              }
            }
          });
        });

        // Real-time status changes
        sock.onChildStatusChanged((data) {
          if (!mounted) return;
          final cid = data['childId'] as String?;
          final status = data['status'] as String?;
          final devName = data['deviceName'] as String?;
          if (cid != null && status != null) {
            setState(() {
              final idx = _children.indexWhere((c) => c.id == cid);
              if (idx != -1) {
                final current = _children[idx];
                final dev = current.device;
                _children[idx] = Child(
                  id: current.id,
                  name: current.name,
                  username: current.username,
                  device: ChildDevice(
                    id: dev?.id ?? '',
                    deviceName: devName ?? dev?.deviceName ?? 'Android Device',
                    platform: dev?.platform ?? 'Android',
                    status: status.toUpperCase(),
                    lastSeen: DateTime.now(),
                  ),
                );
              }
            });
          }
        });

        sock.onUnblockRequest((data) {
          if (!mounted) return;
          final req = UnblockRequest.fromJson(data);
          _showUnblockRequestDialog(req);
        });

        sock.onGeofenceAlert((data) {
          if (!mounted) return;
          final eventId = data['eventId']?.toString() ?? data['id']?.toString() ?? data['_id']?.toString() ?? '';
          final childId = data['childId']?.toString() ?? '';
          final childName = data['childName']?.toString() ?? 'Child';
          final geofenceId = data['geofenceId']?.toString() ?? '';
          final geofenceName = data['geofenceName']?.toString() ?? 'Safety Zone';
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

        sock.onSafetyAlertTriggered((data) {
          if (!mounted) return;
          _showSafetyAlertDialog(data);
        });

        _socketService = sock;
      }
    } catch (_) {}
  }

  void _showSafetyAlertDialog(Map<String, dynamic> data) {
    final childName = data['childName']?.toString() ?? 'Child';
    final childId = data['childId']?.toString() ?? '';
    final latestAlert = (data['latestAlert'] as Map<String, dynamic>?) ?? {};
    final alertType = latestAlert['alertType']?.toString() ?? 'Content Violation';
    final appName = latestAlert['appName']?.toString() ?? latestAlert['packageName']?.toString() ?? 'Unknown App';
    final severity = latestAlert['severity']?.toString() ?? 'HIGH';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade800, size: 28),
            const SizedBox(width: 8),
            const Expanded(child: Text('Content Safety Alert!')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Inappropriate content detected on $childName\'s device!',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.red.shade900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Type: $alertType',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                  ),
                  Text(
                    'App: $appName (Severity: $severity)',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Zero image data was transmitted. Tap "Review Now" to take action (Pause device or block app).',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Dismiss'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade800),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SafetyAlertsScreen(
                    childId: childId,
                    childName: childName,
                    socketService: _socketService,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.shield_outlined, size: 18),
            label: const Text('Review Now'),
          ),
        ],
      ),
    );
  }

  void _showGeofenceAlertDialog(Map<String, dynamic> data) {

    final childName = data['childName']?.toString() ?? 'Child';
    final childId = data['childId']?.toString() ?? '';
    final geofenceName = data['geofenceName']?.toString() ?? 'Boundary';
    final eventType = data['eventType']?.toString() ?? 'EXIT';
    final message = data['message']?.toString() ??
        (eventType == 'EXIT' ? '$childName left $geofenceName' : '$childName arrived at $geofenceName');
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
                        color: isExit ? Colors.red.shade900 : Colors.teal.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Recorded at: ${DateFormat('h:mm a, MMM d').format(DateTime.now())}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
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
              final timestamp = tsStr != null ? DateTime.tryParse(tsStr) : DateTime.now();
              final geofenceId = data['geofenceId']?.toString();

              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LocationTrackingScreen(
                    childId: childId,
                    childName: childName,
                    focusTimestamp: timestamp,
                    focusLocation: (lat != null && lon != null) ? LatLng(lat, lon) : null,
                    highlightGeofenceId: geofenceId,
                    breachType: eventType,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.map, size: 18),
            label: const Text('View on Map'),
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
            Text('App: ${req.appName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(req.packageName, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Reason: "${req.reason}"', style: const TextStyle(fontStyle: FontStyle.italic)),
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await ApiService.instance.listChildren();
      setState(() {
        _children = raw.map((e) => Child.fromJson(e as Map<String, dynamic>)).toList();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
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
    if (confirmed != true) return;

    _socketService?.disconnect();
    await ApiService.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seftly Parent Dashboard'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            tooltip: 'Log Out',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        'My Children',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.foreground,
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (_children.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text('No children registered yet.'),
                        ),
                      for (final child in _children)
                        _ChildCard(
                          child: child,
                          socketService: _socketService,
                          onRefresh: _silentSync,
                        ),
                    ],
                  ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const CreateChildScreen()),
          );
          if (created == true) _refresh();
        },
        icon: const Icon(Icons.add),
        label: const Text('Create Child'),
      ),
    );
  }
}

class _ChildCard extends StatelessWidget {
  final Child child;
  final SocketService? socketService;
  final VoidCallback? onRefresh;

  const _ChildCard({
    required this.child,
    this.socketService,
    this.onRefresh,
  });

  String _formatRelativeLastSeen(DateTime? dt) {
    if (dt == null) return 'Offline';
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inSeconds < 45) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('MMM d, h:mm a').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final online = child.isOnline;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChildDetailScreen(
                  initialChild: child,
                  socketService: socketService,
                ),
              ),
            );
            onRefresh?.call();
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.iconBgPurple,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.face_rounded,
                      size: 38,
                      color: AppColors.iconPurple,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Child Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        child.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: AppColors.foreground,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.phone_android_rounded,
                            size: 14,
                            color: AppColors.mutedForeground,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${child.device?.deviceName ?? 'Android Device'}\n(${child.device?.platform ?? 'Android'})',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppColors.foreground.withValues(alpha: 0.7),
                                height: 1.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Status Badge & Last Seen
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: online ? AppColors.statusOnlineBg : AppColors.statusOfflineBg,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: online ? AppColors.statusOnline : AppColors.statusOffline,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            online ? 'Online' : 'Offline',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: online ? AppColors.statusOnline : AppColors.statusOffline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          online ? Icons.wifi_rounded : Icons.access_time_rounded,
                          size: 13,
                          color: AppColors.mutedForeground,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          online ? 'Active now' : _formatRelativeLastSeen(child.device?.lastSeen),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

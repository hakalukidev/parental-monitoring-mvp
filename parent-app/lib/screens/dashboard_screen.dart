import 'package:flutter/material.dart';
import '../models/child.dart';
import '../models/app_policy.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import 'create_child_screen.dart';
import 'screen_share_screen.dart';
import 'camera_stream_screen.dart';
import 'location_tracking_screen.dart';
import 'app_blocker_screen.dart';
import 'web_filter_screen.dart';
import 'browsing_history_screen.dart';
import 'login_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Child> _children = [];
  bool _loading = true;
  String? _error;
  SocketService? _socketService;

  @override
  void initState() {
    super.initState();
    _initSocketAndLoad();
  }

  @override
  void dispose() {
    _socketService?.disconnect();
    super.dispose();
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

        sock.onChildStatusChanged((data) {
          if (!mounted) return;
          final cid = data['childId'] as String?;
          final status = data['status'] as String?;
          if (cid != null && status != null) {
            setState(() {
              final idx = _children.indexWhere((c) => c.id == cid);
              if (idx != -1) {
                final current = _children[idx];
                final dev = current.device;
                if (dev != null) {
                  _children[idx] = Child(
                    id: current.id,
                    name: current.name,
                    username: current.username,
                    device: ChildDevice(
                      id: dev.id,
                      deviceName: dev.deviceName,
                      platform: dev.platform,
                      status: status,
                      lastSeen: DateTime.now(),
                    ),
                  );
                }
              }
            });
          }
        });

        sock.onUnblockRequest((data) {
          if (!mounted) return;
          final req = UnblockRequest.fromJson(data);
          _showUnblockRequestDialog(req);
        });

        _socketService = sock;
      }
    } catch (_) {}
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
                      Text('My Children', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      if (_children.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text('No children registered yet.'),
                        ),
                      for (final child in _children)
                        _ChildCard(
                          child: child,
                          socketService: _socketService,
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

  const _ChildCard({required this.child, this.socketService});

  @override
  Widget build(BuildContext context) {
    final online = child.isOnline;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(child.name, style: Theme.of(context).textTheme.titleMedium),
                      Text('@${child.username}', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                Chip(
                  label: Text(online ? 'ONLINE' : 'OFFLINE'),
                  backgroundColor: online ? Colors.green.shade100 : Colors.grey.shade300,
                ),
              ],
            ),
            if (child.device != null) ...[
              const SizedBox(height: 8),
              Text('Device: ${child.device!.deviceName} (${child.device!.platform})'),
              Text('Last seen: ${child.device!.lastSeen.toLocal()}'),
            ],

            const Divider(height: 20),

            // Live Supervision Features
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LocationTrackingScreen(
                      childId: child.id,
                      childName: child.name,
                    ),
                  ),
                ),
                icon: const Icon(Icons.location_on),
                label: const Text('Child Location & Directions'),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: online
                        ? () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ScreenShareScreen(
                                  childId: child.id,
                                  childName: child.name,
                                ),
                              ),
                            )
                        : null,
                    icon: const Icon(Icons.screen_share),
                    label: const Text('Live Screen (Stealth)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: online
                        ? () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => CameraStreamScreen(
                                  childId: child.id,
                                  childName: child.name,
                                ),
                              ),
                            )
                        : null,
                    icon: const Icon(Icons.videocam),
                    label: const Text('Live Camera'),
                  ),
                ),
              ],
            ),

            const Divider(height: 20),

            // Requirement 3 & 4: Blocker & Web Filtering & Browsing History
            Text('Digital Wellbeing & Safety', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.indigo),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AppBlockerScreen(
                          childId: child.id,
                          childName: child.name,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.block, size: 18),
                    label: const Text('App Blocker'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.teal),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => WebFilterScreen(
                          childId: child.id,
                          childName: child.name,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.language, size: 18),
                    label: const Text('Web Filter'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BrowsingHistoryScreen(
                      childId: child.id,
                      childName: child.name,
                      socketService: socketService,
                    ),
                  ),
                ),
                icon: const Icon(Icons.history),
                label: const Text('Browsing History & Activity'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
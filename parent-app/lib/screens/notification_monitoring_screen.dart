import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/child_notification_entry.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

class NotificationMonitoringScreen extends StatefulWidget {
  final String childId;
  final String childName;
  final SocketService? socketService;

  const NotificationMonitoringScreen({
    super.key,
    required this.childId,
    required this.childName,
    this.socketService,
  });

  @override
  State<NotificationMonitoringScreen> createState() =>
      _NotificationMonitoringScreenState();
}

class _NotificationMonitoringScreenState
    extends State<NotificationMonitoringScreen> {
  final ApiService _api = ApiService.instance;
  final TextEditingController _searchController = TextEditingController();

  List<ChildNotificationEntry> _notifications = [];
  bool _loading = true;
  String? _error;

  String? _selectedPackage;
  DateTime? _selectedDate;
  int _page = 1;
  bool _hasMore = true;
  bool _loadingMore = false;

  final List<Map<String, String>> _quickAppFilters = [
    {'label': 'All Apps', 'package': ''},
    {'label': 'WhatsApp', 'package': 'com.whatsapp'},
    {'label': 'Messenger', 'package': 'com.facebook.orca'},
    {'label': 'Instagram', 'package': 'com.instagram.android'},
    {'label': 'SMS', 'package': 'com.google.android.apps.messaging'},
    {'label': 'Telegram', 'package': 'org.telegram.messenger'},
    {'label': 'YouTube', 'package': 'com.google.android.youtube'},
  ];

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _setupSocketListeners();
  }

  @override
  void dispose() {
    _searchController.dispose();
    widget.socketService?.off('new_notification_activity');
    super.dispose();
  }

  void _setupSocketListeners() {
    widget.socketService?.onNewNotificationActivity((data) {
      if (!mounted) return;
      final childId = data['childId'] as String?;
      if (childId != widget.childId) return;

      final rawNotif = data['notification'] is Map
          ? Map<String, dynamic>.from(data['notification'] as Map)
          : null;
      if (rawNotif != null) {
        final entry = ChildNotificationEntry.fromJson(rawNotif);
        setState(() {
          // Avoid duplicate by id
          _notifications.removeWhere((n) => n.id == entry.id || (n.externalId.isNotEmpty && n.externalId == entry.externalId));
          _notifications.insert(0, entry);
        });
      } else {
        // Fallback: reload first page if bulk activity
        _loadNotifications(refresh: true);
      }
    });
  }

  Future<void> _loadNotifications({bool refresh = false, bool loadMore = false}) async {
    if (refresh) {
      _page = 1;
      _hasMore = true;
    }

    if (loadMore) {
      if (_loadingMore || !_hasMore) return;
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      String? startDate;
      String? endDate;
      if (_selectedDate != null) {
        final d = _selectedDate!;
        startDate = DateTime(d.year, d.month, d.day).toIso8601String();
        endDate = DateTime(d.year, d.month, d.day, 23, 59, 59).toIso8601String();
      }

      final res = await _api.getNotifications(
        widget.childId,
        packageName: _selectedPackage,
        search: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
        startDate: startDate,
        endDate: endDate,
        page: _page,
        limit: 40,
      );

      final rawList = (res['notifications'] as List<dynamic>?) ??
          (res['data'] as List<dynamic>?) ??
          [];
      final fetched = rawList
          .whereType<Map>()
          .map((e) => ChildNotificationEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      final pagination = res['pagination'] is Map
          ? Map<String, dynamic>.from(res['pagination'] as Map)
          : null;
      final totalPages = pagination?['pages'] as int? ?? 1;

      setState(() {
        if (loadMore) {
          _notifications.addAll(fetched);
          _loadingMore = false;
        } else {
          _notifications = fetched;
          _loading = false;
        }
        _hasMore = _page < totalPages;
        if (_hasMore) {
          _page++;
        }
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _confirmClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Notification Log?'),
        content: const Text(
          'This will delete all stored notification records for this child. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _api.clearNotifications(widget.childId);
        setState(() {
          _notifications.clear();
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Notification history cleared')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to clear: $e')),
          );
        }
      }
    }
  }

  IconData _getAppIcon(String packageName) {
    final pkg = packageName.toLowerCase();
    if (pkg.contains('whatsapp')) return Icons.chat_bubble;
    if (pkg.contains('orca') || pkg.contains('messenger')) return Icons.messenger_outline;
    if (pkg.contains('instagram')) return Icons.camera_alt;
    if (pkg.contains('messaging') || pkg.contains('mms') || pkg.contains('sms')) {
      return Icons.sms;
    }
    if (pkg.contains('telegram')) return Icons.send;
    if (pkg.contains('youtube')) return Icons.play_arrow;
    if (pkg.contains('twitter') || pkg.contains('x.android')) return Icons.alternate_email;
    if (pkg.contains('tiktok')) return Icons.music_video;
    if (pkg.contains('mail') || pkg.contains('gmail')) return Icons.mail_outline;
    if (pkg.contains('discord')) return Icons.forum;
    if (pkg.contains('snapchat')) return Icons.camera;
    return Icons.notifications;
  }

  Color _getAppColor(String packageName) {
    final pkg = packageName.toLowerCase();
    if (pkg.contains('whatsapp')) return const Color(0xFF25D366);
    if (pkg.contains('orca') || pkg.contains('messenger')) return const Color(0xFF0084FF);
    if (pkg.contains('instagram')) return const Color(0xFFE1306C);
    if (pkg.contains('messaging') || pkg.contains('mms') || pkg.contains('sms')) {
      return Colors.amber.shade700;
    }
    if (pkg.contains('telegram')) return const Color(0xFF0088CC);
    if (pkg.contains('youtube')) return const Color(0xFFFF0000);
    if (pkg.contains('discord')) return const Color(0xFF5865F2);
    if (pkg.contains('snapchat')) return const Color(0xFFFFFC00);
    return Colors.indigo;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('App Notifications', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(
              widget.childName,
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.7)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear History',
            onPressed: _notifications.isEmpty ? null : _confirmClearHistory,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => _loadNotifications(refresh: true),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Date Filter Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search sender or message...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                _loadNotifications(refresh: true);
                              },
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
                    ),
                    onSubmitted: (_) => _loadNotifications(refresh: true),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(() => _selectedDate = picked);
                      _loadNotifications(refresh: true);
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _selectedDate != null
                            ? theme.colorScheme.primary
                            : Colors.grey.shade300,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      color: _selectedDate != null
                          ? theme.colorScheme.primary.withOpacity(0.1)
                          : null,
                    ),
                    child: Icon(
                      Icons.calendar_today,
                      size: 20,
                      color: _selectedDate != null
                          ? theme.colorScheme.primary
                          : Colors.grey.shade600,
                    ),
                  ),
                ),
                if (_selectedDate != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Clear Date Filter',
                    onPressed: () {
                      setState(() => _selectedDate = null);
                      _loadNotifications(refresh: true);
                    },
                  ),
              ],
            ),
          ),

          // App Category Chips
          SizedBox(
            height: 48,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              scrollDirection: Axis.horizontal,
              itemCount: _quickAppFilters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final filter = _quickAppFilters[index];
                final isSelected = (_selectedPackage ?? '') == filter['package'];

                return ChoiceChip(
                  label: Text(filter['label']!),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      _selectedPackage = selected && filter['package']!.isNotEmpty
                          ? filter['package']
                          : null;
                    });
                    _loadNotifications(refresh: true);
                  },
                  selectedColor: theme.colorScheme.primary.withOpacity(0.2),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                  ),
                );
              },
            ),
          ),

          const Divider(height: 1),

          // Notification List
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _notifications.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _notifications.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              const Text(
                'Failed to load notifications',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _loadNotifications(refresh: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_notifications.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.notifications_none, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text(
                'No Notifications Received Yet',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'When ${widget.childName} receives notifications from apps like WhatsApp, Messenger, or SMS, they will appear here in real time.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadNotifications(refresh: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification scrollInfo) {
          if (!_loadingMore &&
              _hasMore &&
              scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200) {
            _loadNotifications(loadMore: true);
          }
          return false;
        },
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: _notifications.length + (_loadingMore ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (index == _notifications.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final item = _notifications[index];
            return _buildNotificationCard(item);
          },
        ),
      ),
    );
  }

  Widget _buildNotificationCard(ChildNotificationEntry item) {
    final appColor = _getAppColor(item.packageName);
    final appIcon = _getAppIcon(item.packageName);
    final formattedTime = DateFormat('MMM d, h:mm a').format(item.postTime.toLocal());

    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App Icon Circle
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: appColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(appIcon, color: appColor, size: 22),
            ),
            const SizedBox(width: 12),

            // Content details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // App Name & Timestamp
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            item.appName,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: appColor,
                            ),
                          ),
                          if (item.subText != null && item.subText!.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item.subText!,
                                style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        formattedTime,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Title (Sender)
                  if (item.title.isNotEmpty)
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                  // Message / Content
                  if (item.content.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.content,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade800,
                        height: 1.25,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

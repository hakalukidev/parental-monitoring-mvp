import 'package:flutter/material.dart';
import '../models/app_policy.dart';
import '../services/api_service.dart';

class AppBlockerScreen extends StatefulWidget {
  final String childId;
  final String childName;

  const AppBlockerScreen({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  State<AppBlockerScreen> createState() => _AppBlockerScreenState();
}

class _AppBlockerScreenState extends State<AppBlockerScreen> {
  List<InstalledAppInfo> _apps = [];
  bool _isPaused = false;
  bool _loading = true;
  String? _error;
  String _searchQuery = '';
  String _selectedCategory = 'ALL';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await ApiService.instance.listChildApps(widget.childId);
      final rawApps = (res['apps'] as List<dynamic>?) ?? [];
      final isPaused = res['isPaused'] as bool? ?? false;

      setState(() {
        _apps = rawApps.map((e) => InstalledAppInfo.fromJson(e as Map<String, dynamic>)).toList();
        _isPaused = isPaused;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _togglePause(bool value) async {
    final prev = _isPaused;
    setState(() => _isPaused = value);
    try {
      await ApiService.instance.toggleDevicePause(widget.childId, value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(value
                ? 'Device paused! All non-essential apps are locked.'
                : 'Device unpaused. Regular rules restored.'),
            backgroundColor: value ? Colors.orange.shade800 : Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isPaused = prev);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update pause state: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _bulkUpdate(String category, String status, {int? limit}) async {
    try {
      await ApiService.instance.bulkUpdatePolicy(
        widget.childId,
        category: category,
        status: status,
        dailyLimitMinutes: limit,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bulk updated $category apps to $status')),
      );
      _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bulk update failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _openAppConfigSheet(InstalledAppInfo app) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AppConfigSheet(
        app: app,
        onSave: (newStatus, dailyLimit, schedules) async {
          Navigator.pop(context);
          final updated = InstalledAppInfo(
            packageName: app.packageName,
            appName: app.appName,
            category: app.category,
            status: newStatus,
            dailyLimitMinutes: dailyLimit,
            schedules: schedules,
            isSystemWhitelisted: app.isSystemWhitelisted,
            versionName: app.versionName,
            syncedAt: app.syncedAt,
          );

          try {
            await ApiService.instance.updateAppPolicy(
              widget.childId,
              app.packageName,
              updated.toPolicyJson(),
            );
            setState(() {
              final idx = _apps.indexWhere((a) => a.packageName == app.packageName);
              if (idx != -1) _apps[idx] = updated;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Updated rules for ${app.appName}')),
            );
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Update failed: $e'), backgroundColor: Colors.red),
            );
          }
        },
      ),
    );
  }

  List<InstalledAppInfo> get _filteredApps {
    return _apps.where((app) {
      final matchesSearch = _searchQuery.isEmpty ||
          app.appName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          app.packageName.toLowerCase().contains(_searchQuery.toLowerCase());

      if (!matchesSearch) return false;

      if (_selectedCategory == 'ALL') return true;
      if (_selectedCategory == 'BLOCKED') return app.status == 'BLOCKED';
      if (_selectedCategory == 'LIMITED') return app.status == 'TIME_LIMITED';
      return app.category.toUpperCase() == _selectedCategory;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.childName}'s Apps"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (val) {
              if (val == 'BLOCK_GAMES') _bulkUpdate('GAME', 'BLOCKED');
              if (val == 'ALLOW_GAMES') _bulkUpdate('GAME', 'ALWAYS_ALLOWED');
              if (val == 'BLOCK_SOCIAL') _bulkUpdate('SOCIAL', 'BLOCKED');
              if (val == 'ALLOW_SOCIAL') _bulkUpdate('SOCIAL', 'ALWAYS_ALLOWED');
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'BLOCK_GAMES',
                child: Row(
                  children: [
                    Icon(Icons.sports_esports, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Block All Games'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'ALLOW_GAMES',
                child: Row(
                  children: [
                    Icon(Icons.sports_esports, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Allow All Games'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'BLOCK_SOCIAL',
                child: Row(
                  children: [
                    Icon(Icons.people, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Block All Social Media'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'ALLOW_SOCIAL',
                child: Row(
                  children: [
                    Icon(Icons.people, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Allow All Social Media'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _loadData, child: const Text('Retry')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: Column(
                    children: [
                      // Instant Lockdown Switch Banner
                      Container(
                        margin: const EdgeInsets.all(12),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: _isPaused ? Colors.red.shade50 : Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _isPaused ? Colors.red.shade300 : Colors.blue.shade200,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _isPaused ? Icons.pause_circle_filled : Icons.shield,
                              color: _isPaused ? Colors.red : Colors.blue,
                              size: 32,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _isPaused ? 'Device Is Paused' : 'Instant Device Pause',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: _isPaused ? Colors.red.shade900 : Colors.blue.shade900,
                                    ),
                                  ),
                                  Text(
                                    _isPaused
                                        ? 'All 3rd-party apps locked'
                                        : 'Freeze non-essential apps instantly',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _isPaused ? Colors.red.shade700 : Colors.blue.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _isPaused,
                              activeColor: Colors.red,
                              onChanged: _togglePause,
                            ),
                          ],
                        ),
                      ),

                      // Search Bar
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: 'Search installed apps...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () => setState(() => _searchQuery = ''),
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          onChanged: (val) => setState(() => _searchQuery = val),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Category Filter Chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            _filterChip('ALL', 'All (${_apps.length})'),
                            _filterChip('BLOCKED', 'Blocked'),
                            _filterChip('LIMITED', 'Limited'),
                            _filterChip('GAME', 'Games'),
                            _filterChip('SOCIAL', 'Social'),
                            _filterChip('ENTERTAINMENT', 'Entertainment'),
                            _filterChip('PRODUCTIVITY', 'Productivity'),
                          ],
                        ),
                      ),

                      const Divider(height: 16),

                      // Apps List
                      Expanded(
                        child: _filteredApps.isEmpty
                            ? const Center(
                                child: Text('No apps found matching criteria.'),
                              )
                            : ListView.builder(
                                itemCount: _filteredApps.length,
                                itemBuilder: (ctx, idx) {
                                  final app = _filteredApps[idx];
                                  return _AppListItem(
                                    app: app,
                                    onTap: () => _openAppConfigSheet(app),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _filterChip(String category, String label) {
    final selected = _selectedCategory == category;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _selectedCategory = category),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _AppListItem extends StatelessWidget {
  final InstalledAppInfo app;
  final VoidCallback onTap;

  const _AppListItem({required this.app, required this.onTap});

  IconData _categoryIcon(String category) {
    switch (category.toUpperCase()) {
      case 'GAME':
        return Icons.sports_esports;
      case 'SOCIAL':
        return Icons.people;
      case 'ENTERTAINMENT':
        return Icons.movie;
      case 'EDUCATION':
        return Icons.school;
      case 'PRODUCTIVITY':
        return Icons.work;
      default:
        return Icons.apps;
    }
  }

  Widget _statusBadge(String status) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case 'BLOCKED':
        bg = Colors.red.shade100;
        fg = Colors.red.shade900;
        label = 'BLOCKED';
        break;
      case 'TIME_LIMITED':
        bg = Colors.orange.shade100;
        fg = Colors.orange.shade900;
        label = 'LIMITED';
        break;
      case 'SCHEDULED':
        bg = Colors.purple.shade100;
        fg = Colors.purple.shade900;
        label = 'SCHEDULED';
        break;
      default:
        bg = Colors.green.shade100;
        fg = Colors.green.shade900;
        label = 'ALLOWED';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Icon(_categoryIcon(app.category), color: Theme.of(context).colorScheme.primary),
      ),
      title: Text(app.appName, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(app.category, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          if (app.status == 'TIME_LIMITED' && app.dailyLimitMinutes != null)
            Text(
              'Limit: ${app.dailyLimitMinutes} min/day',
              style: const TextStyle(fontSize: 11, color: Colors.orange),
            ),
          if (app.status == 'SCHEDULED' && app.schedules.isNotEmpty)
            Text(
              'Schedule: ${app.schedules.first.startTime} - ${app.schedules.first.endTime}',
              style: const TextStyle(fontSize: 11, color: Colors.purple),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _statusBadge(app.status),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _AppConfigSheet extends StatefulWidget {
  final InstalledAppInfo app;
  final Function(String status, int? dailyLimit, List<AppSchedule> schedules) onSave;

  const _AppConfigSheet({required this.app, required this.onSave});

  @override
  State<_AppConfigSheet> createState() => _AppConfigSheetState();
}

class _AppConfigSheetState extends State<_AppConfigSheet> {
  late String _status;
  late double _dailyMinutes;
  TimeOfDay _startTime = const TimeOfDay(hour: 21, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 7, minute: 0);

  @override
  void initState() {
    super.initState();
    _status = widget.app.status;
    _dailyMinutes = (widget.app.dailyLimitMinutes ?? 60).toDouble();

    if (widget.app.schedules.isNotEmpty) {
      final s = widget.app.schedules.first;
      final startParts = s.startTime.split(':');
      final endParts = s.endTime.split(':');
      if (startParts.length == 2) {
        _startTime = TimeOfDay(hour: int.parse(startParts[0]), minute: int.parse(startParts[1]));
      }
      if (endParts.length == 2) {
        _endTime = TimeOfDay(hour: int.parse(endParts[0]), minute: int.parse(endParts[1]));
      }
    }
  }

  String _formatTime(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.app.appName,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(widget.app.packageName, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const Divider(height: 24),

          const Text('Access Rule:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),

          RadioListTile<String>(
            title: const Text('Always Allowed'),
            subtitle: const Text('No screen time limits or schedule restrictions'),
            value: 'ALWAYS_ALLOWED',
            groupValue: _status,
            onChanged: (val) => setState(() => _status = val!),
          ),
          RadioListTile<String>(
            title: const Text('Blocked (Stealth)'),
            subtitle: const Text('Shows fake loading spinner so child assumes app is unresponsive'),
            value: 'BLOCKED',
            groupValue: _status,
            onChanged: (val) => setState(() => _status = val!),
          ),
          RadioListTile<String>(
            title: const Text('Daily Time Quota'),
            subtitle: const Text('Limit total active minutes per day'),
            value: 'TIME_LIMITED',
            groupValue: _status,
            onChanged: (val) => setState(() => _status = val!),
          ),

          if (_status == 'TIME_LIMITED') ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Daily Limit:'),
                      Text(
                        '${_dailyMinutes.toInt()} minutes (${(_dailyMinutes / 60).toStringAsFixed(1)} hrs)',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                      ),
                    ],
                  ),
                  Slider(
                    value: _dailyMinutes,
                    min: 15,
                    max: 480,
                    divisions: 31,
                    label: '${_dailyMinutes.toInt()} min',
                    onChanged: (val) => setState(() => _dailyMinutes = val),
                  ),
                ],
              ),
            ),
          ],

          RadioListTile<String>(
            title: const Text('Schedule Restriction'),
            subtitle: const Text('Block during study or bedtime hours'),
            value: 'SCHEDULED',
            groupValue: _status,
            onChanged: (val) => setState(() => _status = val!),
          ),

          if (_status == 'SCHEDULED') ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.access_time),
                      label: Text('From: ${_formatTime(_startTime)}'),
                      onPressed: () async {
                        final picked = await showTimePicker(context: context, initialTime: _startTime);
                        if (picked != null) setState(() => _startTime = picked);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.access_time),
                      label: Text('To: ${_formatTime(_endTime)}'),
                      onPressed: () async {
                        final picked = await showTimePicker(context: context, initialTime: _endTime);
                        if (picked != null) setState(() => _endTime = picked);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                final limit = _status == 'TIME_LIMITED' ? _dailyMinutes.toInt() : null;
                final schedules = _status == 'SCHEDULED'
                    ? [
                        AppSchedule(
                          daysOfWeek: [0, 1, 2, 3, 4, 5, 6],
                          startTime: _formatTime(_startTime),
                          endTime: _formatTime(_endTime),
                        )
                      ]
                    : <AppSchedule>[];

                widget.onSave(_status, limit, schedules);
              },
              child: const Text('Save Rule'),
            ),
          ),
        ],
      ),
    );
  }
}

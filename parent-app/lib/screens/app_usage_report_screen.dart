import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/app_usage_report.dart';
import '../models/app_policy.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

class AppUsageReportScreen extends StatefulWidget {
  final String childId;
  final String childName;
  final SocketService? socketService;

  const AppUsageReportScreen({
    super.key,
    required this.childId,
    required this.childName,
    this.socketService,
  });

  @override
  State<AppUsageReportScreen> createState() => _AppUsageReportScreenState();
}

class _AppUsageReportScreenState extends State<AppUsageReportScreen> {
  AppUsageReport? _report;
  bool _loading = true;
  String? _error;
  String _searchQuery = '';
  String _selectedCategory = 'ALL';
  String _sortBy = 'USAGE'; // 'USAGE', 'NAME', 'LAUNCHES'
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadReport();
    _listenSocket();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _silentRefresh();
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  void _listenSocket() {
    widget.socketService?.onUsageUpdated((data) {
      if (!mounted) return;
      final cid = data['childId'] as String?;
      if (cid == widget.childId) {
        _silentRefresh();
      }
    });
  }

  Future<void> _loadReport() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await ApiService.instance.getTodayUsageReport(widget.childId);
      if (!mounted) return;
      setState(() {
        _report = AppUsageReport.fromJson(res);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _silentRefresh() async {
    try {
      final res = await ApiService.instance.getTodayUsageReport(widget.childId);
      if (!mounted) return;
      setState(() {
        _report = AppUsageReport.fromJson(res);
      });
    } catch (_) {}
  }

  Future<void> _requestSync() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Requesting live update from child device...'),
        duration: Duration(seconds: 2),
      ),
    );

    widget.socketService?.requestUsageSync(widget.childId);
    try {
      await ApiService.instance.requestUsageSync(widget.childId);
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 1200));
    _loadReport();
  }

  void _openAppRuleModal(AppUsageItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _QuickAppConfigSheet(
        childId: widget.childId,
        app: item,
        onUpdated: () {
          _loadReport();
        },
      ),
    );
  }

  List<AppUsageItem> get _filteredApps {
    if (_report == null) return [];
    var list = _report!.apps.where((app) {
      final matchesSearch = _searchQuery.isEmpty ||
          app.appName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          app.packageName.toLowerCase().contains(_searchQuery.toLowerCase());

      if (!matchesSearch) return false;

      if (_selectedCategory == 'ALL') return true;
      if (_selectedCategory == 'ACTIVE') return app.foregroundTimeSeconds > 0;
      if (_selectedCategory == 'BLOCKED') return app.status == 'BLOCKED';
      if (_selectedCategory == 'LIMITED') return app.status == 'TIME_LIMITED';
      return app.category.toUpperCase() == _selectedCategory;
    }).toList();

    switch (_sortBy) {
      case 'USAGE':
        list.sort((a, b) => b.foregroundTimeSeconds.compareTo(a.foregroundTimeSeconds));
        break;
      case 'LAUNCHES':
        list.sort((a, b) => b.launchCount.compareTo(a.launchCount));
        break;
      case 'NAME':
        list.sort((a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));
        break;
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final todayFormatted = DateFormat('EEEE, MMMM d, y').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("${widget.childName}'s Usage Report", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Text("Present Day (1-Day Details)", style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Request Live Sync',
            icon: const Icon(Icons.sync),
            onPressed: _requestSync,
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loadReport,
          ),
        ],
      ),
      body: _loading && _report == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _report == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _loadReport, child: const Text('Try Again')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadReport,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Date & Header Bar
                      _buildHeaderCard(theme, todayFormatted),
                      const SizedBox(height: 16),

                      // Key Metrics Grid
                      _buildMetricsGrid(theme),
                      const SizedBox(height: 16),

                      // Screen Time vs Downtime Distribution Bar
                      _buildDowntimeVsScreenTimeCard(theme),
                      const SizedBox(height: 16),

                      // Hourly Activity Chart
                      if (_report!.hourlyUsage.isNotEmpty) ...[
                        _buildHourlyActivityCard(theme),
                        const SizedBox(height: 16),
                      ],

                      // Category Breakdown Section
                      if (_report!.categoryBreakdown.isNotEmpty) ...[
                        _buildCategoryBreakdownCard(theme),
                        const SizedBox(height: 16),
                      ],

                      // Downtime & Restriction Insights Card
                      _buildDowntimeInsightsCard(theme),
                      const SizedBox(height: 16),

                      // Detailed App Usages Header & Filters
                      _buildAppUsageHeader(theme),
                      const SizedBox(height: 8),

                      // Filter chips
                      _buildFilterChips(),
                      const SizedBox(height: 12),

                      // App List
                      if (_filteredApps.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(32),
                          alignment: Alignment.center,
                          child: Column(
                            children: [
                              Icon(Icons.search_off, size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 8),
                              Text('No apps found for selected filter', style: TextStyle(color: Colors.grey.shade600)),
                            ],
                          ),
                        )
                      else
                        ..._filteredApps.map((app) => _buildAppItemCard(theme, app)),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
    );
  }

  Widget _buildHeaderCard(ThemeData theme, String todayFormatted) {
    final syncedAt = _report?.lastSyncedAt ?? DateTime.now();
    final timeStr = DateFormat('h:mm a').format(syncedAt.toLocal());

    return Card(
      elevation: 0,
      color: theme.colorScheme.primaryContainer.withOpacity(0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: theme.colorScheme.primary,
              child: const Icon(Icons.analytics_outlined, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    todayFormatted,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.green),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Synced at $timeStr',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '1-Day View',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsGrid(ThemeData theme) {
    final summary = _report!.summary;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                icon: Icons.timer,
                iconColor: Colors.blue.shade700,
                bgColor: Colors.blue.shade50,
                title: 'Total Screen Time',
                value: summary.formattedScreenTime,
                subtitle: '${summary.appsWithUsageCount} active apps today',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                icon: Icons.nightlight_round,
                iconColor: Colors.indigo.shade700,
                bgColor: Colors.indigo.shade50,
                title: 'Total Downtime',
                value: summary.formattedDowntime,
                subtitle: 'Screen off & rest time',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                icon: Icons.star_rounded,
                iconColor: Colors.amber.shade800,
                bgColor: Colors.amber.shade50,
                title: 'Most Used App',
                value: summary.mostUsedApp?.appName ?? 'None',
                subtitle: summary.mostUsedApp != null
                    ? summary.mostUsedApp!.formattedUsage
                    : 'No usage recorded yet',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                icon: Icons.shield_outlined,
                iconColor: summary.limitsReachedCount > 0 || summary.blockedAttemptsCount > 0
                    ? Colors.red.shade700
                    : Colors.teal.shade700,
                bgColor: summary.limitsReachedCount > 0 || summary.blockedAttemptsCount > 0
                    ? Colors.red.shade50
                    : Colors.teal.shade50,
                title: 'Restrictions & Limits',
                value: '${summary.limitsReachedCount} Limits Hit',
                subtitle: summary.isDevicePaused
                    ? 'Device paused'
                    : '${summary.blockedAttemptsCount} blocked attempts',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDowntimeVsScreenTimeCard(ThemeData theme) {
    final summary = _report!.summary;
    final screenPct = (summary.screenTimePercentage * 100).toInt();
    final downPct = (summary.downtimePercentage * 100).toInt();

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Screen Time vs Downtime',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                Text(
                  'Today\'s Balance',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Segmented Progress Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 16,
                child: Row(
                  children: [
                    if (summary.screenTimePercentage > 0)
                      Flexible(
                        flex: (summary.screenTimePercentage * 1000).toInt(),
                        child: Container(color: Colors.blue.shade600),
                      ),
                    if (summary.downtimePercentage > 0)
                      Flexible(
                        flex: (summary.downtimePercentage * 1000).toInt(),
                        child: Container(color: Colors.indigo.shade300),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(width: 12, height: 12, decoration: BoxDecoration(color: Colors.blue.shade600, borderRadius: BorderRadius.circular(3))),
                    const SizedBox(width: 6),
                    Text('Active Screen: ${summary.formattedScreenTime} ($screenPct%)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
                Row(
                  children: [
                    Container(width: 12, height: 12, decoration: BoxDecoration(color: Colors.indigo.shade300, borderRadius: BorderRadius.circular(3))),
                    const SizedBox(width: 6),
                    Text('Downtime: ${summary.formattedDowntime} ($downPct%)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHourlyActivityCard(ThemeData theme) {
    final hourly = _report!.hourlyUsage;
    final maxSec = hourly.fold<int>(0, (prev, elem) => elem.screenTimeSeconds > prev ? elem.screenTimeSeconds : prev);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Hourly Activity Timeline', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text('Today (0h - 23h)', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 100,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: hourly.map((h) {
                  final ratio = maxSec > 0 ? (h.screenTimeSeconds / maxSec) : 0.0;
                  final height = (ratio * 70).clamp(4.0, 70.0);
                  final isPeak = maxSec > 0 && h.screenTimeSeconds == maxSec && maxSec > 0;

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Tooltip(
                        message: '${h.formattedHour}: ${h.screenTimeMinutes} min',
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              height: height,
                              decoration: BoxDecoration(
                                color: isPeak
                                    ? Colors.amber.shade700
                                    : (h.screenTimeSeconds > 0 ? Colors.blue.shade600 : Colors.grey.shade200),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (h.hour % 4 == 0)
                              Text(
                                '${h.hour}h',
                                style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                              )
                            else
                              const SizedBox(height: 11),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryBreakdownCard(ThemeData theme) {
    final categories = _report!.categoryBreakdown.where((c) => c.totalTimeSeconds > 0).toList();

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('App Categories Breakdown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 14),
            if (categories.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No categorized usage recorded today yet.', style: TextStyle(color: Colors.grey)),
              )
            else
              ...categories.map((cat) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(cat.iconData, size: 18, color: cat.color),
                          const SizedBox(width: 8),
                          Text(cat.category, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          const Spacer(),
                          Text(cat.formattedTime, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(width: 6),
                          Text('(${cat.percentage}%)', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: (cat.percentage / 100.0).clamp(0.0, 1.0),
                        color: cat.color,
                        backgroundColor: cat.color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(4),
                        minHeight: 6,
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildDowntimeInsightsCard(ThemeData theme) {
    final summary = _report!.summary;
    final hasBedtime = summary.activeScheduleDowntime != null;

    return Card(
      elevation: 1,
      color: Colors.indigo.shade50.withOpacity(0.6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.indigo.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bedtime_outlined, color: Colors.indigo.shade800),
                const SizedBox(width: 8),
                Text(
                  'Downtime & Safety Rules',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.indigo.shade900),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _insightRow(
              icon: Icons.nightlight_round,
              title: 'Scheduled Bedtime Downtime:',
              value: hasBedtime ? summary.activeScheduleDowntime! : 'None active',
              valueColor: hasBedtime ? Colors.indigo.shade900 : Colors.grey.shade700,
            ),
            const Divider(height: 14),
            _insightRow(
              icon: Icons.pause_circle_outline,
              title: 'Instant Device Lockdown:',
              value: summary.isDevicePaused ? 'ACTIVE (Paused)' : 'Normal (Unpaused)',
              valueColor: summary.isDevicePaused ? Colors.red : Colors.green.shade800,
            ),
            const Divider(height: 14),
            _insightRow(
              icon: Icons.block_outlined,
              title: 'Blocked App Open Attempts Today:',
              value: '${summary.blockedAttemptsCount} attempts',
              valueColor: summary.blockedAttemptsCount > 0 ? Colors.orange.shade900 : Colors.teal.shade800,
            ),
            const Divider(height: 14),
            _insightRow(
              icon: Icons.timelapse,
              title: 'Apps Exceeding Daily Limits:',
              value: '${summary.limitsReachedCount} apps reached limit',
              valueColor: summary.limitsReachedCount > 0 ? Colors.red.shade800 : Colors.green.shade800,
            ),
          ],
        ),
      ),
    );
  }

  Widget _insightRow({
    required IconData icon,
    required String title,
    required String value,
    required Color valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.indigo.shade700),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: TextStyle(fontSize: 12, color: Colors.grey.shade800))),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: valueColor)),
      ],
    );
  }

  Widget _buildAppUsageHeader(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Detailed App Usage (${_filteredApps.length})',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            DropdownButton<String>(
              value: _sortBy,
              underline: const SizedBox(),
              icon: const Icon(Icons.sort, size: 18),
              style: TextStyle(fontSize: 12, color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
              items: const [
                DropdownMenuItem(value: 'USAGE', child: Text('Most Used')),
                DropdownMenuItem(value: 'LAUNCHES', child: Text('Most Opened')),
                DropdownMenuItem(value: 'NAME', child: Text('Alphabetical')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _sortBy = val);
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          decoration: InputDecoration(
            hintText: 'Search app name or package...',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => setState(() => _searchQuery = ''),
                  )
                : null,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            filled: true,
          ),
          onChanged: (val) => setState(() => _searchQuery = val),
        ),
      ],
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _filterChip('ALL', 'All'),
          _filterChip('ACTIVE', 'Active Today'),
          _filterChip('LIMITED', 'Time Limited'),
          _filterChip('BLOCKED', 'Blocked'),
          _filterChip('GAME', 'Games'),
          _filterChip('SOCIAL', 'Social'),
          _filterChip('ENTERTAINMENT', 'Entertainment'),
          _filterChip('PRODUCTIVITY', 'Productivity'),
        ],
      ),
    );
  }

  Widget _filterChip(String key, String label) {
    final selected = _selectedCategory == key;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _selectedCategory = key),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildAppItemCard(ThemeData theme, AppUsageItem app) {
    final totalScreenTime = _report?.summary.totalScreenTimeSeconds ?? 0;
    final pct = totalScreenTime > 0
        ? ((app.foregroundTimeSeconds / totalScreenTime) * 100).toStringAsFixed(1)
        : '0';

    Color categoryColor;
    IconData categoryIcon;
    switch (app.category.toUpperCase()) {
      case 'GAME':
        categoryColor = Colors.deepPurple;
        categoryIcon = Icons.sports_esports;
        break;
      case 'SOCIAL':
        categoryColor = Colors.blue;
        categoryIcon = Icons.people;
        break;
      case 'ENTERTAINMENT':
        categoryColor = Colors.amber.shade800;
        categoryIcon = Icons.movie;
        break;
      case 'EDUCATION':
        categoryColor = Colors.teal;
        categoryIcon = Icons.school;
        break;
      case 'PRODUCTIVITY':
        categoryColor = Colors.indigo;
        categoryIcon = Icons.work;
        break;
      default:
        categoryColor = Colors.blueGrey;
        categoryIcon = Icons.apps;
    }

    return Card(
      elevation: 0.5,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openAppRuleModal(app),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: categoryColor.withOpacity(0.12),
                    child: Icon(categoryIcon, color: categoryColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(app.appName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text(app.packageName, style: TextStyle(fontSize: 11, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        app.formattedUsageTime,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: app.foregroundTimeSeconds > 0 ? theme.colorScheme.primary : Colors.grey,
                        ),
                      ),
                      if (app.foregroundTimeSeconds > 0)
                        Text('$pct% of screen time', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Progress Bar
              if (totalScreenTime > 0 && app.foregroundTimeSeconds > 0) ...[
                LinearProgressIndicator(
                  value: (app.foregroundTimeSeconds / totalScreenTime).clamp(0.0, 1.0),
                  color: categoryColor,
                  backgroundColor: categoryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(3),
                  minHeight: 4,
                ),
                const SizedBox(height: 8),
              ],

              // Metadata Row (Launches, Last Used, Status)
              Row(
                children: [
                  Icon(Icons.touch_app, size: 13, color: Colors.grey.shade600),
                  const SizedBox(width: 3),
                  Text('${app.launchCount} opens', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                  const SizedBox(width: 12),
                  Icon(Icons.access_time, size: 13, color: Colors.grey.shade600),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      app.formattedLastUsed,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _buildStatusChip(app),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(AppUsageItem app) {
    Color bg;
    Color fg;
    String label;

    if (app.status == 'BLOCKED') {
      bg = Colors.red.shade50;
      fg = Colors.red.shade800;
      label = 'BLOCKED';
    } else if (app.isLimitExceeded) {
      bg = Colors.red.shade100;
      fg = Colors.red.shade900;
      label = 'LIMIT HIT (${app.dailyLimitMinutes}m)';
    } else if (app.status == 'TIME_LIMITED') {
      bg = Colors.orange.shade50;
      fg = Colors.orange.shade900;
      label = 'LIMIT: ${app.dailyLimitMinutes}m';
    } else if (app.status == 'SCHEDULED') {
      bg = Colors.purple.shade50;
      fg = Colors.purple.shade900;
      label = 'SCHEDULED';
    } else {
      bg = Colors.green.shade50;
      fg = Colors.green.shade800;
      label = 'ALLOWED';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: fg)),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final String title;
  final String value;
  final String subtitle;

  const _MetricCard({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.title,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, size: 18, color: iconColor),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAppConfigSheet extends StatefulWidget {
  final String childId;
  final AppUsageItem app;
  final VoidCallback onUpdated;

  const _QuickAppConfigSheet({
    required this.childId,
    required this.app,
    required this.onUpdated,
  });

  @override
  State<_QuickAppConfigSheet> createState() => _QuickAppConfigSheetState();
}

class _QuickAppConfigSheetState extends State<_QuickAppConfigSheet> {
  late String _status;
  late double _dailyMinutes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _status = widget.app.status;
    _dailyMinutes = (widget.app.dailyLimitMinutes ?? 60).toDouble();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final payload = {
        'appName': widget.app.appName,
        'category': widget.app.category,
        'status': _status,
        'dailyLimitMinutes': _status == 'TIME_LIMITED' ? _dailyMinutes.toInt() : null,
      };

      await ApiService.instance.updateAppPolicy(widget.childId, widget.app.packageName, payload);
      if (mounted) {
        Navigator.pop(context);
        widget.onUpdated();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Updated rules for ${widget.app.appName}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
                    Text(
                      'Today: ${widget.app.formattedUsageTime} • ${widget.app.launchCount} opens',
                      style: const TextStyle(fontSize: 12, color: Colors.blue),
                    ),
                  ],
                ),
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const Divider(height: 20),

          const Text('Access Rule:', style: TextStyle(fontWeight: FontWeight.bold)),
          RadioListTile<String>(
            title: const Text('Always Allowed'),
            value: 'ALWAYS_ALLOWED',
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
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Daily Limit:'),
                      Text(
                        '${_dailyMinutes.toInt()} min (${(_dailyMinutes / 60).toStringAsFixed(1)} hrs)',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                      ),
                    ],
                  ),
                  Slider(
                    value: _dailyMinutes,
                    min: 15,
                    max: 480,
                    divisions: 31,
                    onChanged: (val) => setState(() => _dailyMinutes = val),
                  ),
                ],
              ),
            ),
          ],
          RadioListTile<String>(
            title: const Text('Blocked'),
            subtitle: const Text('Lock this app completely'),
            value: 'BLOCKED',
            groupValue: _status,
            onChanged: (val) => setState(() => _status = val!),
          ),

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving ? const CircularProgressIndicator(color: Colors.white) : const Text('Save Rule'),
            ),
          ),
        ],
      ),
    );
  }
}

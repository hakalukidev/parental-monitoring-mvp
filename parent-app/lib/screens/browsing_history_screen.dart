import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/app_policy.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

class BrowsingHistoryScreen extends StatefulWidget {
  final String childId;
  final String childName;
  final SocketService? socketService;

  const BrowsingHistoryScreen({
    super.key,
    required this.childId,
    required this.childName,
    this.socketService,
  });

  @override
  State<BrowsingHistoryScreen> createState() => _BrowsingHistoryScreenState();
}

class _BrowsingHistoryScreenState extends State<BrowsingHistoryScreen> {
  List<BrowsingHistoryRecord> _records = [];
  BrowsingAnalytics? _analytics;
  bool _loading = true;
  String? _error;

  String _searchQuery = '';
  String _selectedFilter = 'ALL'; // ALL, FLAGGED, BLOCKED, INCOGNITO
  String? _selectedBrowser;
  DateTime _selectedDate = DateTime.now();
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _loadHistoryAndAnalytics();
    _setupSocketListeners();
  }

  @override
  void dispose() {
    widget.socketService?.off('new_browsing_activity');
    widget.socketService?.off('suspicious_web_alert');
    super.dispose();
  }

  void _setupSocketListeners() {
    widget.socketService?.onNewBrowsingActivity((data) {
      if (!mounted) return;
      final childId = data['childId'] as String?;
      final rawRecord = data['record'] as Map<String, dynamic>?;
      if (childId == widget.childId && rawRecord != null) {
        final record = BrowsingHistoryRecord.fromJson(rawRecord);
        setState(() {
          _records.insert(0, record);
          if (_analytics != null) {
            _analytics = BrowsingAnalytics(
              totalVisited: _analytics!.totalVisited + 1,
              blockedAttempts: record.isBlockedAttempt
                  ? _analytics!.blockedAttempts + 1
                  : _analytics!.blockedAttempts,
              topDomains: _analytics!.topDomains,
              categoryDistribution: _analytics!.categoryDistribution,
            );
          }
        });
      }
    });

    widget.socketService?.onSuspiciousWebAlert((data) {
      if (!mounted) return;
      final childId = data['childId'] as String?;
      final rawRecord = data['record'] as Map<String, dynamic>?;
      if (childId == widget.childId && rawRecord != null) {
        final record = BrowsingHistoryRecord.fromJson(rawRecord);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.warning_amber, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Alert: ${widget.childName} attempted to access ${record.domain}'),
                ),
              ],
            ),
            backgroundColor: Colors.red.shade800,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    });
  }

  Future<void> _loadHistoryAndAnalytics({bool append = false}) async {
    if (!append) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
      });
    }

    try {
      final startOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final endOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59);

      final historyFuture = ApiService.instance.listBrowsingHistory(
        widget.childId,
        startDate: startOfDay.toUtc().toIso8601String(),
        endDate: endOfDay.toUtc().toIso8601String(),
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        browser: _selectedBrowser,
        isFlagged: _selectedFilter == 'FLAGGED' ? true : null,
        isBlockedAttempt: _selectedFilter == 'BLOCKED' ? true : null,
        page: _page,
        limit: 50,
      );

      final analyticsFuture = ApiService.instance.getBrowsingAnalytics(widget.childId);

      final results = await Future.wait([historyFuture, analyticsFuture]);
      final historyRes = results[0];
      final analyticsRes = results[1];

      final rawList = (historyRes['records'] as List<dynamic>?) ?? [];
      final parsed = rawList.map((e) => BrowsingHistoryRecord.fromJson(e as Map<String, dynamic>)).toList();

      setState(() {
        if (append) {
          _records.addAll(parsed);
        } else {
          _records = parsed;
        }
        _analytics = BrowsingAnalytics.fromJson(analyticsRes);
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _blockDomain(String domain) async {
    try {
      await ApiService.instance.createWebRule(
        widget.childId,
        ruleType: 'DOMAIN',
        target: domain,
        action: 'BLOCK',
        isEnabled: true,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Blocked $domain! Future attempts will be blocked on device.'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to block domain: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Browsing History'),
        content: Text('Are you sure you want to clear browsing logs for ${widget.childName}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear History'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ApiService.instance.clearBrowsingHistory(widget.childId);
        if (!mounted) return;
        setState(() {
          _records.clear();
          _analytics = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Browsing history cleared.')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to clear: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildSummaryCard() {
    if (_analytics == null) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Today's Web Summary",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  DateFormat('EEE, MMM d').format(_selectedDate),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.background,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Sites Visited', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text(
                          '${_analytics!.totalVisited}',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _analytics!.blockedAttempts > 0 ? Colors.red.shade50 : Theme.of(context).colorScheme.background,
                      borderRadius: BorderRadius.circular(10),
                      border: _analytics!.blockedAttempts > 0
                          ? Border.all(color: Colors.red.shade200)
                          : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Blocked Attempts',
                          style: TextStyle(
                            fontSize: 12,
                            color: _analytics!.blockedAttempts > 0 ? Colors.red.shade900 : Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_analytics!.blockedAttempts}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: _analytics!.blockedAttempts > 0 ? Colors.red.shade900 : Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_analytics!.topDomains.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Top Sites Visited:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              for (final td in _analytics!.topDomains.take(3)) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          td.domain,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text('${td.count} visits (${td.percentage}%)', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ),
                LinearProgressIndicator(
                  value: td.percentage / 100.0,
                  backgroundColor: Colors.grey.shade200,
                  color: Theme.of(context).colorScheme.primary,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(2),
                ),
                const SizedBox(height: 4),
              ],
            ],
          ],
        ),
      ),
    );
  }

  IconData _browserIcon(String browser) {
    switch (browser.toUpperCase()) {
      case 'CHROME':
        return Icons.public;
      case 'FIREFOX':
        return Icons.local_fire_department;
      case 'EDGE':
        return Icons.explore;
      case 'SAMSUNG_BROWSER':
        return Icons.phone_android;
      case 'BRAVE':
        return Icons.shield;
      default:
        return Icons.language;
    }
  }

  Widget _safetyBadge(BrowsingHistoryRecord record) {
    if (record.isBlockedAttempt) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(4)),
        child: Text('BLOCKED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade900)),
      );
    }
    if (record.category == 'ADULT' || record.category == 'SUSPICIOUS') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(4)),
        child: Text('FLAGGED: ${record.category}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(4)),
      child: Text(record.category, style: TextStyle(fontSize: 10, color: Colors.green.shade800)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _records.where((r) {
      if (_selectedFilter == 'INCOGNITO' && !r.isIncognito) return false;
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.childName}'s Browsing"),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime.now().subtract(const Duration(days: 60)),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                setState(() => _selectedDate = picked);
                _loadHistoryAndAnalytics();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear History',
            onPressed: _clearHistory,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadHistoryAndAnalytics(),
          ),
        ],
      ),
      body: _loading && _records.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _records.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: () => _loadHistoryAndAnalytics(), child: const Text('Retry')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _loadHistoryAndAnalytics(),
                  child: ListView(
                    children: [
                      // Analytics Summary Card
                      _buildSummaryCard(),

                      // Search bar
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: 'Search URL, domain or title...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      setState(() => _searchQuery = '');
                                      _loadHistoryAndAnalytics();
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            filled: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          onSubmitted: (val) {
                            setState(() => _searchQuery = val);
                            _loadHistoryAndAnalytics();
                          },
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Filter chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            _filterChip('ALL', 'All'),
                            _filterChip('BLOCKED', 'Blocked Only'),
                            _filterChip('FLAGGED', 'Flagged Only'),
                            _filterChip('INCOGNITO', 'Incognito Tabs'),
                          ],
                        ),
                      ),

                      const Divider(height: 16),

                      // Timeline Feed
                      if (filtered.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.history, size: 56, color: Colors.grey),
                                SizedBox(height: 8),
                                Text('No browsing activity found for this date.'),
                              ],
                            ),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, indent: 64),
                          itemBuilder: (ctx, idx) {
                            final record = filtered[idx];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: record.isBlockedAttempt
                                    ? Colors.red.shade100
                                    : Theme.of(context).colorScheme.surfaceVariant,
                                child: Icon(
                                  _browserIcon(record.browser),
                                  color: record.isBlockedAttempt ? Colors.red : Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      record.title.isNotEmpty ? record.title : record.domain,
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (record.isIncognito) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(color: Colors.grey.shade800, borderRadius: BorderRadius.circular(4)),
                                      child: const Text('INCOGNITO', style: TextStyle(color: Colors.white, fontSize: 9)),
                                    ),
                                  ],
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 2),
                                  Text(
                                    record.url,
                                    style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Text(
                                        DateFormat('hh:mm a').format(record.visitedAt),
                                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                                      ),
                                      const SizedBox(width: 8),
                                      _safetyBadge(record),
                                      const Spacer(),
                                      TextButton.icon(
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        icon: const Icon(Icons.block, size: 14, color: Colors.red),
                                        label: const Text('Block Domain', style: TextStyle(fontSize: 11, color: Colors.red)),
                                        onPressed: () => _blockDomain(record.domain),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _filterChip(String filterKey, String label) {
    final selected = _selectedFilter == filterKey;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() => _selectedFilter = filterKey);
          _loadHistoryAndAnalytics();
        },
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

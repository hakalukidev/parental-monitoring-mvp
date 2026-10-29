import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/safety_alert_entry.dart';
import '../services/api_service.dart';
import '../services/mock_communication_provider.dart';
import '../services/socket_service.dart';
import 'app_blocker_screen.dart';

class SafetyAlertsScreen extends StatefulWidget {
  final String childId;
  final String childName;
  final SocketService? socketService;

  const SafetyAlertsScreen({
    super.key,
    required this.childId,
    required this.childName,
    this.socketService,
  });

  @override
  State<SafetyAlertsScreen> createState() => _SafetyAlertsScreenState();
}

class _SafetyAlertsScreenState extends State<SafetyAlertsScreen> {
  List<SafetyAlertEntry> _alerts = [];
  bool _isLoading = true;
  String? _error;
  int _unacknowledgedCount = 0;

  // Filter: 'ALL', 'UNACKNOWLEDGED', 'CRITICAL', 'ACKNOWLEDGED'
  String _activeFilter = 'ALL';
  bool _useMockData = false;

  final DateFormat _dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

  @override
  void initState() {
    super.initState();
    _loadAlerts();
    _setupSocketListener();
  }

  void _setupSocketListener() {
    final sock = widget.socketService;
    if (sock == null) return;

    sock.onSafetyAlertTriggered((data) {
      if (!mounted) return;
      if (data['childId'] == widget.childId) {
        final latest = data['latestAlert'] as Map<String, dynamic>?;
        final pkg = latest?['packageName'] as String?;
        final app = latest?['appName'] as String?;
        if (pkg != null && pkg.isNotEmpty && pkg != 'com.android.providers.media') {
          ApiService.instance.updateAppPolicy(widget.childId, pkg, {
            'status': 'BLOCKED',
            'appName': app ?? pkg,
          }).catchError((_) => <String, dynamic>{});
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Urgent: Inappropriate content detected on ${widget.childName}\'s device! App has been automatically closed and blocked.',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _loadAlerts();
      }
    });
  }

  Future<void> _loadAlerts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    if (_useMockData) {
      final mock = MockCommunicationProvider.getMockSafetyAlerts();
      setState(() {
        _alerts = mock;
        _unacknowledgedCount = mock.where((a) => !a.isAcknowledged).length;
        _isLoading = false;
      });
      return;
    }

    try {
      String? severity;
      bool? isAcknowledged;
      if (_activeFilter == 'UNACKNOWLEDGED') {
        isAcknowledged = false;
      } else if (_activeFilter == 'ACKNOWLEDGED') {
        isAcknowledged = true;
      } else if (_activeFilter == 'CRITICAL') {
        severity = 'CRITICAL';
      }

      final data = await ApiService.instance.getSafetyAlerts(
        widget.childId,
        severity: severity,
        isAcknowledged: isAcknowledged,
      );

      final list = (data['alerts'] as List<dynamic>?) ?? [];
      final parsed = list.map((e) => SafetyAlertEntry.fromJson(e as Map<String, dynamic>)).toList();
      final unack = (data['unacknowledgedCount'] as num?)?.toInt() ??
          parsed.where((a) => !a.isAcknowledged).length;

      setState(() {
        _alerts = parsed;
        _unacknowledgedCount = unack;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _acknowledgeAlert(SafetyAlertEntry alert) async {
    if (_useMockData) {
      setState(() {
        final index = _alerts.indexWhere((a) => a.id == alert.id);
        if (index != -1) {
          _alerts[index] = SafetyAlertEntry(
            id: alert.id,
            alertType: alert.alertType,
            packageName: alert.packageName,
            appName: alert.appName,
            confidenceScore: alert.confidenceScore,
            severity: alert.severity,
            isAcknowledged: true,
            acknowledgedAt: DateTime.now(),
            timestamp: alert.timestamp,
          );
          _unacknowledgedCount = _alerts.where((a) => !a.isAcknowledged).length;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alert marked as reviewed.')),
      );
      return;
    }

    try {
      await ApiService.instance.acknowledgeSafetyAlert(widget.childId, alert.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alert marked as reviewed.')),
      );
      _loadAlerts();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update alert: $e')),
      );
    }
  }


  Future<void> _pauseChildDevice() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pause Device Now?'),
        content: Text(
          'This will immediately lock ${widget.childName}\'s screen and block active apps until you unpause.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Pause Now'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ApiService.instance.toggleDevicePause(widget.childId, true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.black87,
            content: Text('${widget.childName}\'s device is now locked.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pause device: $e')),
        );
      }
    }
  }

  Future<void> _blockApp(String packageName, String? appName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Block ${appName ?? packageName}?'),
        content: Text(
          'This app will be immediately restricted on ${widget.childName}\'s device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Block App'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ApiService.instance.updateAppPolicy(
        widget.childId,
        packageName,
        {
          'status': 'BLOCKED',
          'appName': appName ?? packageName,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${appName ?? packageName} has been blocked.'),
            action: SnackBarAction(
              label: 'View in Blocker',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AppBlockerScreen(
                      childId: widget.childId,
                      childName: widget.childName,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to block app: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Safety & Content Alerts',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              widget.childName,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          // Demo toggle
          IconButton(
            tooltip: _useMockData ? 'Using Mock Data' : 'Using Live Server',
            icon: Icon(
              _useMockData ? Icons.science : Icons.science_outlined,
              color: _useMockData ? Colors.deepPurple : null,
            ),
            onPressed: () {
              setState(() => _useMockData = !_useMockData);
              _loadAlerts();
            },
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loadAlerts,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAlerts,
        child: Column(
          children: [
            // Urgent Warning Banner if there are unreviewed alerts
            if (_unacknowledgedCount > 0)
              Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.warning_rounded, color: Colors.red.shade900, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$_unacknowledgedCount Unreviewed Alert${_unacknowledgedCount > 1 ? 's' : ''}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.red.shade900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Potential inappropriate content viewed or saved on device.',
                            style: TextStyle(fontSize: 12, color: Colors.red.shade800),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: _pauseChildDevice,
                      child: const Text('Pause Device', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),

            // Privacy Guarantee Notice
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blueGrey.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, size: 18, color: Colors.blueGrey.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Privacy Assured: On-device neural detection only. Zero photos or screen recordings are transmitted to the cloud or saved.',
                      style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade800),
                    ),
                  ),
                ],
              ),
            ),

            // Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  _buildFilterChip('ALL', 'All Alerts'),
                  const SizedBox(width: 8),
                  _buildFilterChip('UNACKNOWLEDGED', 'Pending Review'),
                  const SizedBox(width: 8),
                  _buildFilterChip('CRITICAL', 'Critical Severity'),
                  const SizedBox(width: 8),
                  _buildFilterChip('ACKNOWLEDGED', 'Reviewed'),
                ],
              ),
            ),

            const Divider(height: 1),

            // Alerts List
            Expanded(
              child: _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String filterKey, String label) {
    final isSelected = _activeFilter == filterKey;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _activeFilter = filterKey);
          _loadAlerts();
        }
      },
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(
                'Failed to load safety alerts',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadAlerts,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    final filteredAlerts = _alerts.where((a) {
      if (_activeFilter == 'UNACKNOWLEDGED') return !a.isAcknowledged;
      if (_activeFilter == 'ACKNOWLEDGED') return a.isAcknowledged;
      if (_activeFilter == 'CRITICAL') return a.severity == SafetySeverity.critical;
      return true;
    }).toList();

    if (filteredAlerts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.green.shade400),
            const SizedBox(height: 16),
            Text(
              'No Safety Violations Detected',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              _activeFilter == 'UNACKNOWLEDGED'
                  ? 'All detected incidents have been reviewed.'
                  : 'No inappropriate content has been reported for this child.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: filteredAlerts.length,
      itemBuilder: (ctx, index) {
        final alert = filteredAlerts[index];
        return _buildAlertCard(alert);
      },
    );
  }

  Widget _buildAlertCard(SafetyAlertEntry alert) {
    Color severityColor;
    Color severityBg;
    switch (alert.severity) {
      case SafetySeverity.critical:
        severityColor = Colors.red.shade900;
        severityBg = Colors.red.shade50;
        break;
      case SafetySeverity.high:
        severityColor = Colors.deepOrange.shade900;
        severityBg = Colors.deepOrange.shade50;
        break;
      case SafetySeverity.medium:
        severityColor = Colors.amber.shade900;
        severityBg = Colors.amber.shade50;
        break;
    }

    final confidencePercent = (alert.confidenceScore * 100).toInt();

    return Card(
      elevation: alert.isAcknowledged ? 0.5 : 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: alert.isAcknowledged ? Colors.grey.shade300 : Colors.red.shade200,
          width: alert.isAcknowledged ? 1 : 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Severity Chip + Confidence + Timestamp
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: severityBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: severityColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    alert.severity.displayName.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: severityColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$confidencePercent% confidence',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
                  ),
                ),
                const Spacer(),
                Text(
                  _dateFormat.format(alert.timestamp),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Title and Details
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  alert.alertType == 'EXPLICIT_SCREEN_CONTENT'
                      ? Icons.screenshot_monitor_rounded
                      : Icons.broken_image_rounded,
                  color: alert.isAcknowledged ? Colors.grey.shade700 : Colors.red.shade800,
                  size: 26,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alert.alertTitle,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: alert.isAcknowledged ? Colors.grey.shade800 : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (alert.appName != null || alert.packageName != null)
                        Text(
                          'Source: ${alert.appName ?? alert.packageName} (${alert.packageName ?? "unknown"})',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            if (alert.packageName != null &&
                alert.packageName!.isNotEmpty &&
                alert.packageName != 'com.android.providers.media')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.shield_rounded, size: 16, color: Colors.red.shade800),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'App automatically closed & blocked for child safety',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.red.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Acknowledgment status or Actions
            const Divider(height: 16),
            if (alert.isAcknowledged)
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle, size: 16, color: Colors.green),
                      const SizedBox(width: 6),
                      Text(
                        alert.acknowledgedAt != null
                            ? 'Reviewed ${_dateFormat.format(alert.acknowledgedAt!)}'
                            : 'Reviewed by parent',
                        style: TextStyle(fontSize: 12, color: Colors.green.shade800),
                      ),
                    ],
                  ),
                  if (alert.packageName != null &&
                      alert.packageName!.isNotEmpty &&
                      alert.packageName != 'com.android.providers.media')
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: Colors.blueGrey.shade800,
                      ),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AppBlockerScreen(
                              childId: widget.childId,
                              childName: widget.childName,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.app_blocking_rounded, size: 16),
                      label: const Text('Manage in Blocker'),
                    ),
                ],
              )
            else
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: Colors.green.shade800,
                      side: BorderSide(color: Colors.green.shade300),
                    ),
                    onPressed: () => _acknowledgeAlert(alert),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Mark Reviewed'),
                  ),
                  if (alert.packageName != null &&
                      alert.packageName!.isNotEmpty &&
                      alert.packageName != 'com.android.providers.media')
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AppBlockerScreen(
                              childId: widget.childId,
                              childName: widget.childName,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.app_blocking_rounded, size: 16),
                      label: const Text('Manage in Blocker'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../design/seftly_widgets.dart';
import '../design/family_date_time.dart';
import '../services/api_service.dart';

class ActivityHistoryScreen extends StatefulWidget {
  final String childId, childName, kind;
  const ActivityHistoryScreen(
      {super.key,
      required this.childId,
      required this.childName,
      required this.kind});
  @override
  State<ActivityHistoryScreen> createState() => _ActivityHistoryScreenState();
}

class _ActivityHistoryScreenState extends State<ActivityHistoryScreen> {
  bool _loading = true, _saving = false;
  String? _error, _cursor, _package;
  DateTimeRange? _dates;
  int? _total;
  Map<String, dynamic> _configuration = {};
  final List<Map<String, dynamic>> _records = [];
  String get _title => switch (widget.kind) {
        'CALL' => 'Call activity',
        'SMS' => 'SMS activity',
        'NOTIFICATION' => 'Notification activity',
        _ => 'Photo & video safety'
      };
  IconData get _icon => switch (widget.kind) {
        'CALL' => Icons.call_outlined,
        'SMS' => Icons.sms_outlined,
        'NOTIFICATION' => Icons.notifications_none_rounded,
        _ => Icons.verified_user_outlined
      };
  String get _setting => switch (widget.kind) {
        'CALL' => 'callsEnabled',
        'SMS' => 'smsEnabled',
        'NOTIFICATION' => 'notificationsEnabled',
        _ => 'safetyEnabled'
      };
  String get _feature => switch (widget.kind) {
        'CALL' || 'SMS' => 'callSms',
        'NOTIFICATION' => 'notifications',
        _ => 'safety'
      };
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final configuration =
          await ApiService.instance.getActivityPolicy(widget.childId);
      final result = await ApiService.instance.listActivity(
          widget.childId, widget.kind,
          cursor: more ? _cursor : null,
          packageName: _package,
          start: _dates?.start,
          end: _dates == null
              ? null
              : DateTime(
                      _dates!.end.year, _dates!.end.month, _dates!.end.day + 1)
                  .subtract(const Duration(microseconds: 1)));
      if (!mounted) return;
      setState(() {
        _configuration = configuration;
        if (!more) _records.clear();
        _records.addAll((result['records'] as List)
            .map((x) => Map<String, dynamic>.from(x as Map)));
        _cursor = result['nextCursor'] as String?;
        _total = (result['total'] as num?)?.toInt();
        final allowed =
            (_configuration['policy'] as Map?)?['monitoredPackages'] as List? ??
                [];
        if (_package != null && !allowed.contains(_package)) _package = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _configure() async {
    final policy =
        Map<String, dynamic>.from(_configuration['policy'] as Map? ?? {});
    final available = (_configuration['features'] as Map?)?[_feature] == true;
    final allowed =
        Set<String>.from(policy['monitoredPackages'] as List? ?? []);
    var enabled = policy[_setting] == true;
    var retention = (policy['retentionDays'] as num?)?.toInt() ?? 30;
    List<dynamic> apps = [];
    if (widget.kind == 'NOTIFICATION') {
      try {
        apps = (await ApiService.instance.listChildApps(widget.childId))['apps']
                as List? ??
            [];
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('App inventory unavailable: $e')));
        }
      }
    }
    if (!mounted) return;
    final saved = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                    title: Text('Configure $_title'),
                    content: SizedBox(
                        width: 400,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title:
                                      const Text('Collect authorized activity'),
                                  subtitle: Text(available
                                      ? 'Device setup must also grant supported Android access.'
                                      : 'Unavailable pending server/platform/model verification.'),
                                  value: enabled,
                                  onChanged: available
                                      ? (v) => update(() => enabled = v)
                                      : null),
                              DropdownButtonFormField<int>(
                                  initialValue: retention,
                                  decoration: const InputDecoration(
                                      labelText:
                                          'Retention for activity records'),
                                  items: [
                                    for (final days in {7, 30, 90, retention})
                                      DropdownMenuItem(
                                          value: days,
                                          child: Text('$days days'))
                                  ],
                                  onChanged: (v) =>
                                      update(() => retention = v ?? 30)),
                              if (widget.kind == 'NOTIFICATION') ...[
                                const SizedBox(height: 12),
                                const Text(
                                    'Select apps. Notification bodies, OTPs and banking/security content are excluded.'),
                                if (apps.isEmpty)
                                  const Text(
                                      'No app inventory reported yet. Ask the child device to reconnect.'),
                                for (final raw in apps)
                                  if (raw is Map &&
                                      raw['packageName'] is String)
                                    CheckboxListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: Text((raw['appName'] ??
                                                raw['packageName'])
                                            .toString()),
                                        value: allowed
                                            .contains(raw['packageName']),
                                        onChanged: (v) => update(() {
                                              v == true
                                                  ? allowed.add(
                                                      raw['packageName']
                                                          as String)
                                                  : allowed.remove(
                                                      raw['packageName']);
                                            })),
                              ],
                              if (widget.kind == 'SAFETY')
                                const Text(
                                    'Selected media only. No original photos/videos are uploaded. A licensed, evaluated model is required before scanning can be enabled.'),
                            ]))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, {
                                _setting: enabled,
                                'retentionDays': retention,
                                if (widget.kind == 'NOTIFICATION')
                                  'monitoredPackages': allowed.toList()
                              }),
                          child: const Text('Save settings'))
                    ])));
    if (saved == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await ApiService.instance.updateActivityPolicy(widget.childId, saved);
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save settings: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: Text('Delete $_title history?'),
                content: const Text(
                    'This removes this child’s recorded activity in this category and prevents old queued events from restoring it.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Delete history'))
                ]));
    if (confirmed != true || !mounted) return;
    try {
      await ApiService.instance.deleteActivity(widget.childId, widget.kind);
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not delete history: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = _configuration['capabilities'] as Map? ?? {};
    final features = _configuration['features'] as Map? ?? {};
    final policy = _configuration['policy'] as Map? ?? {};
    final accessKey = switch (widget.kind) {
      'NOTIFICATION' => 'notificationAccess',
      'CALL' => 'callLogAccess',
      'SMS' => 'smsAccess',
      _ => 'safetyModel'
    };
    final access = capabilities[accessKey]?.toString() ?? 'UNKNOWN';
    return SeftlyScaffold(
        title: _title,
        subtitle: 'Activity shared by ${widget.childName}',
        icon: _icon,
        body: _loading && _records.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? SeftlyStateView(
                    icon: Icons.cloud_off,
                    title: 'Activity unavailable',
                    message: _error!,
                    error: true,
                    actionLabel: 'Retry',
                    onAction: () => _load())
                : RefreshIndicator(
                    onRefresh: () => _load(),
                    child:
                        ListView(padding: const EdgeInsets.all(20), children: [
                      Card(
                          child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        features[_feature] != true
                                            ? 'Feature unavailable on this server'
                                            : policy[_setting] != true
                                                ? 'Collection is off'
                                                : access != 'GRANTED' &&
                                                        access != 'AVAILABLE'
                                                    ? 'Device permission or model unavailable'
                                                    : 'Authorized collection configured',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                    const SizedBox(height: 8),
                                    Text(_configuration['online'] == true
                                        ? 'Child device is online'
                                        : 'Child device is offline or connection is unverified'),
                                    Text(
                                        'Device access: $access · Reported ${FamilyDateTime.parse(capabilities['updatedAt'])}'),
                                    Text(
                                        'Last successful sync: ${FamilyDateTime.parse(capabilities['lastSyncedAt'])}'),
                                    if (widget.kind == 'NOTIFICATION')
                                      Text(capabilities['listenerConnected'] ==
                                              true
                                          ? 'Notification listener is connected'
                                          : 'Notification listener connection is unverified'),
                                    for (final entry in const {
                                      'screen': 'Screen',
                                      'camera': 'Camera',
                                      'audio': 'Audio'
                                    }.entries)
                                      Text(
                                          '${entry.value} check-in last completed: ${FamilyDateTime.parse(((_configuration['lastCheckIns'] as Map?)?[entry.key] as Map?)?['endedAt'])}'),
                                    if (capabilities['queuedEvents'] != null)
                                      Text(
                                          '${capabilities['queuedEvents']} queued events · ${capabilities['droppedEvents'] ?? 0} dropped at storage limit'),
                                    Wrap(spacing: 8, children: [
                                      TextButton.icon(
                                          onPressed:
                                              _saving ? null : _configure,
                                          icon: const Icon(
                                              Icons.settings_outlined),
                                          label: const Text(
                                              'Configure collection')),
                                      TextButton.icon(
                                          onPressed: () => _load(),
                                          icon: const Icon(Icons.refresh),
                                          label: const Text('Refresh'))
                                    ]),
                                  ]))),
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, children: [
                        OutlinedButton.icon(
                            onPressed: () async {
                              final range = await showDateRangePicker(
                                  context: context,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now(),
                                  initialDateRange: _dates);
                              if (range != null && mounted) {
                                setState(() => _dates = range);
                                await _load();
                              }
                            },
                            icon: const Icon(Icons.date_range),
                            label: Text(_dates == null
                                ? 'Filter dates'
                                : '${FamilyDateTime.format(_dates!.start, pattern: 'MMM d')} – ${FamilyDateTime.format(_dates!.end, pattern: 'MMM d')}')),
                        if (_dates != null)
                          TextButton(
                              onPressed: () {
                                setState(() => _dates = null);
                                _load();
                              },
                              child: const Text('Clear dates')),
                        TextButton(
                            onPressed: _delete,
                            child: const Text('Delete history'))
                      ]),
                      if (widget.kind == 'NOTIFICATION')
                        DropdownButtonFormField<String>(
                            initialValue: _package,
                            isExpanded: true,
                            decoration: const InputDecoration(
                                labelText: 'Monitored app'),
                            items: [
                              const DropdownMenuItem<String>(
                                  value: null,
                                  child: Text('All monitored apps')),
                              for (final p
                                  in policy['monitoredPackages'] as List? ?? [])
                                DropdownMenuItem(
                                    value: p.toString(),
                                    child: Text(p.toString()))
                            ],
                            onChanged: (v) {
                              setState(() => _package = v);
                              _load();
                            }),
                      if (_total != null)
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                                '$_total activity events match this selection')),
                      if (_records.isEmpty)
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Column(children: [
                              Icon(_icon, size: 48),
                              const SizedBox(height: 12),
                              const Text(
                                  'No activity reported for this selection.'),
                              if (widget.kind == 'SAFETY')
                                const Text(
                                    'Coverage is selected media only. Classification remains disabled without a validated model.')
                            ])),
                      for (final record in _records)
                        Card(
                            child: ListTile(
                                leading: Icon(_icon),
                                title: Text(widget.kind == 'NOTIFICATION'
                                    ? '${record['packageName']} · ${record['eventType']}'
                                    : widget.kind == 'SAFETY'
                                        ? '${record['mediaType']} · ${record['category']}'
                                        : '${record['direction']} · ${record['maskedIdentifier'] ?? 'Identifier unavailable'}'),
                                subtitle: Text(
                                    '${FamilyDateTime.parse(record['eventAt'])}\n${widget.kind == 'CALL' ? 'Duration ${record['durationSeconds']} seconds' : widget.kind == 'SAFETY' ? 'Confidence ${record['confidence'] is num ? '${((record['confidence'] as num) * 100).toStringAsFixed(1)}%' : 'not reported'} · ${record['reviewStatus']} · ${record['modelVersion']}' : 'Synced ${FamilyDateTime.parse(record['syncedAt'])}'}'),
                                isThreeLine: true,
                                trailing: widget.kind == 'SAFETY'
                                    ? PopupMenuButton<String>(
                                        onSelected: (status) async {
                                          try {
                                            await ApiService.instance
                                                .reviewSafetyEvent(
                                                    widget.childId,
                                                    record['_id'] as String,
                                                    status);
                                            if (mounted) await _load();
                                          } catch (e) {
                                            if (mounted) {
                                              ScaffoldMessenger.of(this.context)
                                                  .showSnackBar(SnackBar(
                                                      content: Text(
                                                          'Review failed: $e')));
                                            }
                                          }
                                        },
                                        itemBuilder: (_) => const [
                                              PopupMenuItem(
                                                  value: 'CONFIRMED',
                                                  child: Text('Confirm alert')),
                                              PopupMenuItem(
                                                  value: 'DISMISSED',
                                                  child: Text(
                                                      'Dismiss false positive'))
                                            ])
                                    : null)),
                      if (_cursor != null)
                        TextButton(
                            onPressed:
                                _loading ? null : () => _load(more: true),
                            child: Text(
                                _loading ? 'Loading…' : 'Load older activity')),
                    ])));
  }
}

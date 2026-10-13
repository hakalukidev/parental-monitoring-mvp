import 'dart:async';
import 'package:flutter/material.dart';
import '../design/seftly_widgets.dart';
import '../design/family_date_time.dart';
import '../services/api_service.dart';
import 'activity_history_screen.dart';

class CommunicationHistoryScreen extends StatefulWidget {
  final String childId, childName, kind;
  const CommunicationHistoryScreen(
      {super.key,
      required this.childId,
      required this.childName,
      required this.kind});
  @override
  State<CommunicationHistoryScreen> createState() =>
      _CommunicationHistoryScreenState();
}

class _CommunicationHistoryScreenState
    extends State<CommunicationHistoryScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  bool _loading = true, _saving = false, _grouped = false;
  String? _error, _cursor, _direction, _thread;
  DateTimeRange? _dates;
  Map<String, dynamic> _configuration = {}, _statistics = {};
  final List<Map<String, dynamic>> _records = [];
  int? _total;
  int _generation = 0;
  bool get _calls => widget.kind == 'CALL';
  String get _title => _calls ? 'Call History' : 'Messages';
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final config =
          await ApiService.instance.getCommunicationPolicy(widget.childId);
      if (!mounted || generation != _generation) return;
      // Disabled new infrastructure has an explicit state; historical metadata remains reachable.
      if (config['available'] != true && config['capabilities'] == null) {
        setState(() {
          _configuration = config;
          _records.clear();
          _cursor = null;
          _total = 0;
        });
        return;
      }
      final start = _dates?.start;
      final end = _dates == null
          ? null
          : DateTime(_dates!.end.year, _dates!.end.month, _dates!.end.day + 1)
              .subtract(const Duration(microseconds: 1));
      final result = await ApiService.instance.getCommunications(
          widget.childId, widget.kind,
          cursor: more ? _cursor : null,
          search: _search.text,
          direction: _direction,
          threadId: _thread,
          start: start,
          end: end,
          grouped: _grouped);
      final now = DateTime.now();
      final stats = await ApiService.instance.getCommunications(
          widget.childId, widget.kind,
          statistics: true,
          start: start ??
              DateTime(now.year, now.month, now.day)
                  .subtract(const Duration(days: 6)),
          end: end ?? now,
          search: _search.text,
          direction: _direction,
          threadId: _thread);
      if (!mounted || generation != _generation) return;
      setState(() {
        _configuration = config;
        _statistics = stats;
        if (!more) _records.clear();
        _records.addAll(
            ((result[_grouped ? 'groups' : 'records'] as List?) ?? [])
                .map((r) => Map<String, dynamic>.from(r as Map)));
        _cursor = result['nextCursor'] as String?;
        _total = (result['total'] as num?)?.toInt();
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _configure() async {
    final policy =
        Map<String, dynamic>.from(_configuration['policy'] as Map? ?? {});
    final available = _configuration['available'] == true;
    var enabled = policy[_calls ? 'callsEnabled' : 'smsEnabled'] == true &&
        policy['fullCommunicationHistoryEnabled'] == true;
    var bodies = policy['messageBodiesEnabled'] == true;
    var contacts = policy['contactsEnabled'] == true;
    var mms = policy['mmsEnabled'] == true;
    var days = (policy['initialImportDays'] as num?)?.toInt() ?? 7;
    var retention = (policy['retentionDays'] as num?)?.toInt() ?? 30;
    final update = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, change) => AlertDialog(
                    title: Text('Configure $_title'),
                    content: SizedBox(
                        width: 400,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              const Text(
                                  'Guardian setup grants supported Android access once. These settings control automatic sync; no Seftly child approval is required. Only public provider records are covered.'),
                              SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title:
                                      const Text('Collect authorized history'),
                                  value: enabled,
                                  onChanged: available
                                      ? (v) => change(() => enabled = v)
                                      : null),
                              const Text(
                                  'Phone numbers, provider identifiers and available call/message details are encrypted at rest.'),
                              SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text(
                                      'Include authorized contact names'),
                                  subtitle: const Text(
                                      'Uses available call-log names or separately granted Contacts access.'),
                                  value: contacts,
                                  onChanged: available
                                      ? (v) => change(() => contacts = v)
                                      : null),
                              if (!_calls) ...[
                                SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text(
                                        'Include accessible message content'),
                                    subtitle: const Text(
                                        'SMS/MMS text only when provider access permits it. Security messages are suppressed conservatively; no private app messages.'),
                                    value: bodies,
                                    onChanged: available
                                        ? (v) => change(() => bodies = v)
                                        : null),
                                SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text(
                                        'Include supported MMS text/metadata'),
                                    subtitle: const Text(
                                        'Attachments remain on the device. MMS coverage may be restricted by the provider.'),
                                    value: mms,
                                    onChanged: available
                                        ? (v) => change(() => mms = v)
                                        : null),
                              ],
                              DropdownButtonFormField<int>(
                                  initialValue: days,
                                  decoration: const InputDecoration(
                                      labelText: 'Initial authorized import'),
                                  items: [
                                    for (final d in {1, 7, 30, days})
                                      DropdownMenuItem(
                                          value: d, child: Text('$d days'))
                                  ],
                                  onChanged: (v) =>
                                      change(() => days = v ?? 7)),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<int>(
                                  initialValue: retention,
                                  decoration: const InputDecoration(
                                      labelText: 'Retain history'),
                                  items: [
                                    for (final d in {7, 30, 90, retention})
                                      DropdownMenuItem(
                                          value: d, child: Text('$d days'))
                                  ],
                                  onChanged: (v) =>
                                      change(() => retention = v ?? 30)),
                              if (!available)
                                const Text(
                                    'Detailed history is unavailable on this server. Existing metadata can be viewed separately.'),
                            ]))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, {
                                _calls ? 'callsEnabled' : 'smsEnabled': enabled,
                                'fullCommunicationHistoryEnabled': enabled ||
                                    policy['fullCommunicationHistoryEnabled'] ==
                                        true,
                                'contactsEnabled': contacts,
                                'initialImportDays': days,
                                'retentionDays': retention,
                                if (!_calls) 'messageBodiesEnabled': bodies,
                                if (!_calls) 'mmsEnabled': mms
                              }),
                          child: const Text('Save settings'))
                    ])));
    if (update == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await ApiService.instance.updateActivityPolicy(widget.childId, update);
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
    final approved = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: Text('Delete $_title history?'),
                content: const Text(
                    'Deletes detailed content and earlier metadata for this child/category. Opaque expiring deduplication markers prevent previously stored records from returning.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Delete history'))
                ]));
    if (approved != true || !mounted) return;
    try {
      await ApiService.instance
          .deleteCommunications(widget.childId, widget.kind);
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
    final policy = _configuration['policy'] as Map? ?? {};
    final caps = _configuration['capabilities'] as Map? ?? {};
    final access =
        caps[_calls ? 'callLogAccess' : 'smsAccess']?.toString() ?? 'UNKNOWN';
    final daily = _statistics['daily'] as List? ?? [];
    final weekly = _statistics['weekly'] as List? ?? [];
    final count = daily.fold<int>(
        0, (sum, row) => sum + ((row as Map)['count'] as num? ?? 0).toInt());
    return SeftlyScaffold(
        title: _title,
        subtitle: 'Authorized provider history for ${widget.childName}',
        icon: _calls ? Icons.call_outlined : Icons.forum_outlined,
        appBar: AppBar(title: Text(_title)),
        body: _loading && _records.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? SeftlyStateView(
                    icon: Icons.cloud_off,
                    title: 'History unavailable',
                    message: _error!,
                    error: true,
                    actionLabel: 'Retry',
                    onAction: () => _load())
                : RefreshIndicator(
                    onRefresh: () => _load(),
                    child:
                        ListView(padding: const EdgeInsets.all(16), children: [
                      Card(
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        _configuration['available'] != true
                                            ? 'Detailed history unavailable'
                                            : policy['fullCommunicationHistoryEnabled'] !=
                                                        true ||
                                                    policy[_calls
                                                            ? 'callsEnabled'
                                                            : 'smsEnabled'] !=
                                                        true
                                                ? 'Collection is off'
                                                : access != 'GRANTED'
                                                    ? 'Android access unavailable'
                                                    : 'Authorized collection configured',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                    Text(_configuration['online'] == true
                                        ? 'Child device is online'
                                        : 'Child device is offline or connection is unverified'),
                                    Text('Android access: $access'),
                                    Text(
                                        'Last successful upload: ${FamilyDateTime.parse(caps[_calls ? 'lastCallSyncAt' : 'lastMessageSyncAt'])}'),
                                    Text(
                                        'Last provider scan: ${FamilyDateTime.parse(caps[_calls ? 'lastCallScanAt' : 'lastMessageScanAt'])}'),
                                    if (caps['queuedRecords'] != null)
                                      Text(
                                          '${caps['queuedRecords']} queued · ${caps['droppedRecords'] ?? 0} dropped at storage limit'),
                                    const SizedBox(height: 8),
                                    const Text(
                                        'This is partial authorized provider coverage, not all phone communications. Private messaging/VoIP stores, deleted records and telephone audio are outside this history.'),
                                    if (!_calls)
                                      Text(
                                          'SMS: ${caps['smsCoverage'] ?? 'Unverified'} · MMS: ${caps['mmsCoverage'] ?? 'Unverified'}. Android may restrict/delay protected messages. Attachments are not transferred.'),
                                    Wrap(spacing: 8, children: [
                                      TextButton.icon(
                                          onPressed:
                                              _saving ? null : _configure,
                                          icon: const Icon(
                                              Icons.settings_outlined),
                                          label: const Text(
                                              'Configure collection')),
                                      TextButton(
                                          onPressed: () => _load(),
                                          child: const Text('Refresh')),
                                      TextButton(
                                          onPressed: () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                  builder: (_) =>
                                                      ActivityHistoryScreen(
                                                          childId:
                                                              widget.childId,
                                                          childName:
                                                              widget.childName,
                                                          kind: widget.kind))),
                                          child: const Text('Earlier metadata'))
                                    ]),
                                  ]))),
                      const SizedBox(height: 12),
                      TextField(
                          controller: _search,
                          decoration: const InputDecoration(
                              labelText: 'Search words or full phone number',
                              prefixIcon: Icon(Icons.search)),
                          onChanged: (_) {
                            _debounce?.cancel();
                            _debounce = Timer(const Duration(milliseconds: 400),
                                () => _load());
                          }),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                          initialValue: _direction,
                          isExpanded: true,
                          decoration:
                              const InputDecoration(labelText: 'Direction'),
                          items: [
                            const DropdownMenuItem(
                                value: null, child: Text('All directions')),
                            for (final d in _calls
                                ? [
                                    'INCOMING',
                                    'OUTGOING',
                                    'MISSED',
                                    'REJECTED',
                                    'BLOCKED'
                                  ]
                                : ['INCOMING', 'OUTGOING'])
                              DropdownMenuItem(
                                  value: d, child: Text(d.toLowerCase()))
                          ],
                          onChanged: (v) {
                            setState(() => _direction = v);
                            _load();
                          }),
                      SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(_calls
                              ? 'Group repeated callers'
                              : 'Group message conversations'),
                          value: _grouped,
                          onChanged: (v) {
                            setState(() {
                              _grouped = v;
                              _thread = null;
                            });
                            _load();
                          }),
                      Wrap(spacing: 8, children: [
                        OutlinedButton.icon(
                            onPressed: () async {
                              final dates = await showDateRangePicker(
                                  context: context,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now(),
                                  initialDateRange: _dates);
                              if (dates != null && mounted) {
                                setState(() => _dates = dates);
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
                      if (_thread != null)
                        TextButton(
                            onPressed: () {
                              setState(() => _thread = null);
                              _load();
                            },
                            child: const Text('All conversations')),
                      if (_configuration['available'] == true)
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                                '${_total ?? 0} ${_grouped ? 'groups' : 'records'} matching · $count records ${_dates == null ? 'in the last 7 days' : 'in selected dates'} · Device statistics zone ${_statistics['timeZone'] ?? 'Unverified'}')),
                      for (final row in daily)
                        Text(
                            '${(row as Map)['_id']['day']} · ${row['_id']['direction'].toString().toLowerCase()} · ${row['count']} ${_calls ? 'calls' : 'messages'}${_calls ? ' · ${row['durationSeconds']} recorded seconds' : ''}'),
                      if (weekly.isNotEmpty)
                        const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Text('Weekly totals for this selection')),
                      for (final row in weekly)
                        Text(
                            '${(row as Map)['_id']['day']} · ${row['_id']['direction'].toString().toLowerCase()} · ${row['count']} ${_calls ? 'calls' : 'messages'}'),
                      if (_records.isEmpty)
                        const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                                'No authorized history reported for this selection.')),
                      for (final raw in _records) _recordCard(raw),
                      if (_cursor != null)
                        OutlinedButton(
                            onPressed:
                                _loading ? null : () => _load(more: true),
                            child: Text(_loading ? 'Loading…' : 'Load more')),
                    ])));
  }

  Widget _recordCard(Map<String, dynamic> raw) {
    final row =
        Map<String, dynamic>.from((_grouped ? raw['latest'] : raw) as Map);
    final detail = row['details'] as Map? ?? {};
    final address =
        (detail[_calls ? 'phoneNumber' : 'address'] ?? 'Address not reported')
            .toString();
    final status = row['contentStatus']?.toString();
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(detail['contactName']?.toString() ?? address,
                  style: Theme.of(context).textTheme.titleMedium),
              if (detail['contactName'] != null) SelectableText(address),
              Text(
                  '${row['direction'].toString().toLowerCase()} · ${FamilyDateTime.parse(row['eventAt'])} · ${row['transport']}'),
              if (_grouped)
                Text(
                    '${raw['count']} ${_calls ? 'calls' : 'messages'} in this group'),
              if (_calls)
                Text(row['durationSeconds'] is num
                    ? 'Duration ${row['durationSeconds']} seconds'
                    : 'Duration not reported'),
              if (!_calls) ...[
                const SizedBox(height: 8),
                if (status == 'AVAILABLE' && detail['body'] is String)
                  SelectableText(detail['body'] as String)
                else
                  Text(switch (status) {
                    'WITHHELD_SECURITY' => 'Content withheld for security',
                    'NOT_AUTHORIZED' => 'Content collection is off',
                    'TOO_LARGE' => 'Content exceeds the supported size limit',
                    _ => 'No text reported by the provider'
                  }),
                if (detail['read'] is bool)
                  Text(detail['read'] == true
                      ? 'Provider marks read'
                      : 'Provider marks unread'),
                Text('Delivery ${detail['deliveryStatus'] ?? 'UNKNOWN'}'),
                if (row['transport'] == 'MMS')
                  Text(
                      '${detail['attachmentCount'] ?? 'Unreported'} attachments · retained on device'),
                if (_grouped && detail['threadId'] != null)
                  TextButton(
                      onPressed: () {
                        setState(() {
                          _thread = detail['threadId'].toString();
                          _grouped = false;
                        });
                        _load();
                      },
                      child: const Text('Open conversation')),
              ],
              if (detail['subscriptionId'] != null)
                Text('SIM ${detail['subscriptionId']}'),
              if (detail['phoneAccountId'] != null)
                Text('Phone account ${detail['phoneAccountId']}'),
              Text(
                  'Provider ID ${detail['sourceId'] ?? 'Not reported'}${detail['threadId'] == null ? '' : ' · Thread ${detail['threadId']}'}'),
              Text('Synced ${FamilyDateTime.parse(row['syncedAt'])}',
                  style: Theme.of(context).textTheme.bodySmall),
            ])));
  }
}

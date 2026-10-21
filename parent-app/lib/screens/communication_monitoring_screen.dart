import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/child_call_entry.dart';
import '../models/child_sms_entry.dart';
import '../models/communication_capability.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/mock_communication_provider.dart';

class CommunicationMonitoringScreen extends StatefulWidget {
  final String childId;
  final String childName;
  final SocketService? socketService;

  const CommunicationMonitoringScreen({
    super.key,
    required this.childId,
    required this.childName,
    this.socketService,
  });

  @override
  State<CommunicationMonitoringScreen> createState() => _CommunicationMonitoringScreenState();
}

class _CommunicationMonitoringScreenState extends State<CommunicationMonitoringScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  CommunicationCapability _capability = CommunicationCapability.defaultInitial();
  bool _isLoadingCapabilities = true;

  // Calls state
  List<ChildCallEntry> _calls = [];
  bool _isLoadingCalls = true;
  String _callDirectionFilter = 'ALL';
  final TextEditingController _callSearchController = TextEditingController();

  // SMS state
  List<ChildSmsEntry> _smsList = [];
  bool _isLoadingSms = true;
  String _smsDirectionFilter = 'ALL';
  final TextEditingController _smsSearchController = TextEditingController();

  // Mock / Demo toggle
  bool _useMockData = false;

  final DateFormat _dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    _loadCapabilities();
    _loadCalls();
    _loadSms();

    _setupSocketListeners();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _callSearchController.dispose();
    _smsSearchController.dispose();
    super.dispose();
  }

  void _setupSocketListeners() {
    final sock = widget.socketService;
    if (sock == null) return;

    sock.onNewCallActivity((data) {
      if (!mounted) return;
      if (data['childId'] == widget.childId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('New call activity recorded'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _loadCalls();
      }
    });

    sock.onNewSmsActivity((data) {
      if (!mounted) return;
      if (data['childId'] == widget.childId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('New SMS message recorded'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _loadSms();
      }
    });

    sock.onCommunicationCapabilitiesUpdated((data) {
      if (!mounted) return;
      if (data['childId'] == widget.childId && data['capabilities'] != null) {
        setState(() {
          _capability = CommunicationCapability.fromJson(
            Map<String, dynamic>.from(data['capabilities'] as Map),
          );
        });
      }
    });
  }

  Future<void> _loadCapabilities() async {
    setState(() => _isLoadingCapabilities = true);
    try {
      if (_useMockData) {
        setState(() {
          _capability = MockCommunicationProvider.getMockCapabilities();
          _isLoadingCapabilities = false;
        });
        return;
      }
      final data = await ApiService.instance.getCommunicationCapabilities(widget.childId);
      if (mounted) {
        setState(() {
          _capability = CommunicationCapability.fromJson(data);
          _isLoadingCapabilities = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingCapabilities = false);
      }
    }
  }

  Future<void> _loadCalls() async {
    setState(() => _isLoadingCalls = true);
    if (_useMockData) {
      final mock = MockCommunicationProvider.getMockCalls();
      setState(() {
        _calls = _filterCallsLocally(mock);
        _isLoadingCalls = false;
      });
      return;
    }

    try {
      final res = await ApiService.instance.getCallHistory(
        widget.childId,
        direction: _callDirectionFilter == 'ALL' ? null : _callDirectionFilter,
        search: _callSearchController.text.trim().isEmpty ? null : _callSearchController.text.trim(),
        limit: 50,
      );
      final rawList = (res['calls'] as List<dynamic>?) ?? [];
      final parsed = rawList.map((e) => ChildCallEntry.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      if (mounted) {
        setState(() {
          _calls = parsed;
          _isLoadingCalls = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingCalls = false);
      }
    }
  }

  List<ChildCallEntry> _filterCallsLocally(List<ChildCallEntry> list) {
    var filtered = list;
    if (_callDirectionFilter != 'ALL') {
      filtered = filtered.where((c) => c.direction.name.toUpperCase() == _callDirectionFilter).toList();
    }
    final q = _callSearchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      filtered = filtered.where((c) {
        final nameMatch = c.contactName?.toLowerCase().contains(q) ?? false;
        final numMatch = c.phoneNumber?.toLowerCase().contains(q) ?? false;
        return nameMatch || numMatch;
      }).toList();
    }
    return filtered;
  }

  Future<void> _loadSms() async {
    setState(() => _isLoadingSms = true);
    if (_useMockData) {
      final mock = MockCommunicationProvider.getMockSms();
      setState(() {
        _smsList = _filterSmsLocally(mock);
        _isLoadingSms = false;
      });
      return;
    }

    try {
      final res = await ApiService.instance.getSmsHistory(
        widget.childId,
        direction: _smsDirectionFilter == 'ALL' ? null : _smsDirectionFilter,
        search: _smsSearchController.text.trim().isEmpty ? null : _smsSearchController.text.trim(),
        limit: 50,
      );
      final rawList = (res['messages'] as List<dynamic>?) ?? [];
      final parsed = rawList.map((e) => ChildSmsEntry.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      if (mounted) {
        setState(() {
          _smsList = parsed;
          _isLoadingSms = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingSms = false);
      }
    }
  }

  List<ChildSmsEntry> _filterSmsLocally(List<ChildSmsEntry> list) {
    var filtered = list;
    if (_smsDirectionFilter != 'ALL') {
      filtered = filtered.where((s) => s.direction.name.toUpperCase() == _smsDirectionFilter).toList();
    }
    final q = _smsSearchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      filtered = filtered.where((s) {
        final nameMatch = s.contactName?.toLowerCase().contains(q) ?? false;
        final numMatch = s.phoneNumber?.toLowerCase().contains(q) ?? false;
        return nameMatch || numMatch;
      }).toList();
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.childName} — Calls & SMS'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.call), text: 'Calls'),
            Tab(icon: Icon(Icons.mark_chat_unread_outlined), text: 'Messages'),
          ],
        ),
        actions: [
          if (kDebugMode)
            IconButton(
              tooltip: _useMockData ? 'Switch to Real Data' : 'Switch to Demo Mock Data',
              icon: Icon(_useMockData ? Icons.bug_report : Icons.bug_report_outlined),
              onPressed: () {
                setState(() => _useMockData = !_useMockData);
                _loadCapabilities();
                _loadCalls();
                _loadSms();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(_useMockData ? 'Showing Demo Mock Data' : 'Showing Real Device Data'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          _buildCapabilityBanner(theme),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCallsTab(theme),
                _buildSmsTab(theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapabilityBanner(ThemeData theme) {
    if (_isLoadingCapabilities) return const SizedBox.shrink();

    final isCallRestricted = !_capability.callsStatus.isAvailable;
    final isSmsRestricted = !_capability.smsMetadataStatus.isAvailable;

    if (!isCallRestricted && !isSmsRestricted) {
      return const SizedBox.shrink();
    }

    String message;
    if (isCallRestricted && isSmsRestricted) {
      message = 'Call & SMS permissions are not granted or restricted on this child device.';
    } else if (isCallRestricted) {
      message = 'Call log monitoring permission is disabled on this child device.';
    } else {
      message = 'SMS access is restricted or not permitted on this child device.';
    }

    return Container(
      width: double.infinity,
      color: Colors.amber.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.amber.shade900, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.amber.shade900,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // Calls Tab
  // ==========================================
  Widget _buildCallsTab(ThemeData theme) {
    return Column(
      children: [
        // Search & Filters
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _callSearchController,
            decoration: InputDecoration(
              hintText: 'Search by contact or number...',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              suffixIcon: _callSearchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _callSearchController.clear();
                        _loadCalls();
                      },
                    )
                  : null,
            ),
            onSubmitted: (_) => _loadCalls(),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _buildFilterChip('All', 'ALL', _callDirectionFilter, (val) {
                setState(() => _callDirectionFilter = val);
                _loadCalls();
              }),
              _buildFilterChip('Incoming', 'INCOMING', _callDirectionFilter, (val) {
                setState(() => _callDirectionFilter = val);
                _loadCalls();
              }),
              _buildFilterChip('Outgoing', 'OUTGOING', _callDirectionFilter, (val) {
                setState(() => _callDirectionFilter = val);
                _loadCalls();
              }),
              _buildFilterChip('Missed', 'MISSED', _callDirectionFilter, (val) {
                setState(() => _callDirectionFilter = val);
                _loadCalls();
              }),
              _buildFilterChip('Rejected', 'REJECTED', _callDirectionFilter, (val) {
                setState(() => _callDirectionFilter = val);
                _loadCalls();
              }),
            ],
          ),
        ),
        const Divider(height: 16),

        // Calls list
        Expanded(
          child: _isLoadingCalls
              ? const Center(child: CircularProgressIndicator())
              : _calls.isEmpty
                  ? _buildEmptyState(
                      icon: Icons.phone_disabled_outlined,
                      title: 'No call records found',
                      subtitle: !_capability.callsStatus.isAvailable
                          ? 'Permission is required on child device to view calls.'
                          : 'Recent call history will appear here once recorded.',
                    )
                  : RefreshIndicator(
                      onRefresh: _loadCalls,
                      child: ListView.separated(
                        itemCount: _calls.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final call = _calls[index];
                          return _buildCallTile(call, theme);
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildCallTile(ChildCallEntry call, ThemeData theme) {
    IconData icon;
    Color iconColor;

    switch (call.direction) {
      case CallDirection.incoming:
        icon = Icons.call_received;
        iconColor = Colors.green;
        break;
      case CallDirection.outgoing:
        icon = Icons.call_made;
        iconColor = Colors.blue;
        break;
      case CallDirection.missed:
        icon = Icons.call_missed;
        iconColor = Colors.red;
        break;
      case CallDirection.rejected:
        icon = Icons.phone_disabled;
        iconColor = Colors.orange;
        break;
      case CallDirection.unknown:
        icon = Icons.phone;
        iconColor = Colors.grey;
        break;
    }

    final title = call.contactName?.isNotEmpty == true
        ? call.contactName!
        : (call.phoneNumber?.isNotEmpty == true ? call.phoneNumber! : 'Unknown Number');

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: iconColor.withValues(alpha: 0.15),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (call.contactName != null && call.phoneNumber != null)
            Text(call.phoneNumber!, style: theme.textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(
            '${call.direction.displayName} • ${_dateFormat.format(call.timestamp)}',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
          ),
        ],
      ),
      trailing: Text(
        call.formattedDuration,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: call.durationSeconds > 0 ? Colors.black87 : Colors.grey,
        ),
      ),
      onTap: () => _showCallDetailsSheet(call),
    );
  }

  void _showCallDetailsSheet(ChildCallEntry call) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Call Details', style: Theme.of(context).textTheme.titleLarge),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(),
                _buildDetailRow('Contact Name', call.contactName ?? 'Unknown / Not in contacts'),
                _buildDetailRow('Phone Number', call.phoneNumber ?? 'Private / Withheld'),
                _buildDetailRow('Direction', call.direction.displayName),
                _buildDetailRow('Duration', call.formattedDuration),
                _buildDetailRow('Date & Time', _dateFormat.format(call.timestamp)),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==========================================
  // SMS Tab
  // ==========================================
  Widget _buildSmsTab(ThemeData theme) {
    return Column(
      children: [
        // Search & Filters
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _smsSearchController,
            decoration: InputDecoration(
              hintText: 'Search messages by contact or number...',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              suffixIcon: _smsSearchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _smsSearchController.clear();
                        _loadSms();
                      },
                    )
                  : null,
            ),
            onSubmitted: (_) => _loadSms(),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _buildFilterChip('All', 'ALL', _smsDirectionFilter, (val) {
                setState(() => _smsDirectionFilter = val);
                _loadSms();
              }),
              _buildFilterChip('Incoming', 'INCOMING', _smsDirectionFilter, (val) {
                setState(() => _smsDirectionFilter = val);
                _loadSms();
              }),
              _buildFilterChip('Outgoing', 'OUTGOING', _smsDirectionFilter, (val) {
                setState(() => _smsDirectionFilter = val);
                _loadSms();
              }),
            ],
          ),
        ),
        const Divider(height: 16),

        // SMS list
        Expanded(
          child: _isLoadingSms
              ? const Center(child: CircularProgressIndicator())
              : _smsList.isEmpty
                  ? _buildEmptyState(
                      icon: Icons.chat_bubble_outline,
                      title: 'No SMS messages found',
                      subtitle: !_capability.smsMetadataStatus.isAvailable
                          ? 'SMS access is restricted on this child device.'
                          : 'Incoming and outgoing SMS activity will appear here.',
                    )
                  : RefreshIndicator(
                      onRefresh: _loadSms,
                      child: ListView.separated(
                        itemCount: _smsList.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final sms = _smsList[index];
                          return _buildSmsTile(sms, theme);
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildSmsTile(ChildSmsEntry sms, ThemeData theme) {
    final isIncoming = sms.direction == SmsDirection.incoming;
    final iconColor = isIncoming ? Colors.teal : Colors.indigo;
    final directionBadge = isIncoming ? 'Incoming' : 'Outgoing';

    final title = sms.contactName?.isNotEmpty == true
        ? sms.contactName!
        : (sms.phoneNumber?.isNotEmpty == true ? sms.phoneNumber! : 'Unknown Number');

    final bodyPreview = sms.hasBody && sms.body != null
        ? sms.body!
        : 'Message content unavailable due to privacy restrictions';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: iconColor.withValues(alpha: 0.15),
        child: Icon(
          isIncoming ? Icons.sms_outlined : Icons.outbox_outlined,
          color: iconColor,
          size: 20,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              directionBadge,
              style: theme.textTheme.bodySmall?.copyWith(
                color: iconColor,
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            bodyPreview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: sms.hasBody ? Colors.black87 : Colors.grey.shade600,
              fontStyle: sms.hasBody ? FontStyle.normal : FontStyle.italic,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _dateFormat.format(sms.timestamp),
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade500),
          ),
        ],
      ),
      isThreeLine: true,
      onTap: () => _showSmsDetailsSheet(sms),
    );
  }

  void _showSmsDetailsSheet(ChildSmsEntry sms) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('SMS Message', style: Theme.of(context).textTheme.titleLarge),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(),
                _buildDetailRow('Contact Name', sms.contactName ?? 'Unknown / Not in contacts'),
                _buildDetailRow('Phone Number', sms.phoneNumber ?? 'Unknown'),
                _buildDetailRow('Direction', sms.direction.displayName),
                _buildDetailRow('Date & Time', _dateFormat.format(sms.timestamp)),
                const SizedBox(height: 12),
                Text('Message Content', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    sms.hasBody && sms.body != null
                        ? sms.body!
                        : 'Message content is not accessible due to device privacy permissions.',
                    style: TextStyle(
                      color: sms.hasBody ? Colors.black87 : Colors.grey.shade600,
                      fontStyle: sms.hasBody ? FontStyle.normal : FontStyle.italic,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String label, String value, String currentSelected, Function(String) onSelect) {
    final isSelected = currentSelected == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => onSelect(value),
        selectedColor: Theme.of(context).colorScheme.primaryContainer,
      ),
    );
  }

  Widget _buildEmptyState({required IconData icon, required String title, required String subtitle}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}

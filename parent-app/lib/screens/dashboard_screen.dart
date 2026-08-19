import 'package:flutter/material.dart';
import '../models/child.dart';
import '../services/api_service.dart';
import 'create_child_screen.dart';
import 'screen_share_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Child> _children = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parent Dashboard'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
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
                          child: Text('No children yet.'),
                        ),
                      for (final child in _children) _ChildCard(child: child),
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
  const _ChildCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final online = child.isOnline;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: online
                    ? () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ScreenShareScreen(childId: child.id, childName: child.name),
                          ),
                        )
                    : null,
                icon: const Icon(Icons.screen_share),
                label: const Text('Share Screen'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

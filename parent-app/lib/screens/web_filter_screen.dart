import 'package:flutter/material.dart';
import '../models/app_policy.dart';
import '../services/api_service.dart';

class WebFilterScreen extends StatefulWidget {
  final String childId;
  final String childName;

  const WebFilterScreen({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  State<WebFilterScreen> createState() => _WebFilterScreenState();
}

class _WebFilterScreenState extends State<WebFilterScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<WebBlockRule> _rules = [];
  bool _loading = true;
  String? _error;

  // Predefined category rules map
  final Map<String, String> _predefinedCategories = {
    'ADULT': 'Adult & Explicit Content',
    'GAMBLING': 'Gambling & Betting',
    'GAMING': 'Online Gaming & Streaming',
    'SOCIAL': 'Social Media Websites',
    'VIOLENCE': 'Violence & Dangerous Content',
    'SAFESEARCH': 'Enforce SafeSearch (Google/Bing/Yahoo)',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadRules();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRules() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final raw = await ApiService.instance.listWebRules(widget.childId);
      setState(() {
        _rules = raw.map((e) => WebBlockRule.fromJson(e as Map<String, dynamic>)).toList();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  WebBlockRule? _findCategoryRule(String categoryKey) {
    try {
      return _rules.firstWhere(
        (r) => r.ruleType == 'CATEGORY' && r.target.toUpperCase() == categoryKey.toUpperCase(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _toggleCategory(String categoryKey, bool enable) async {
    final existing = _findCategoryRule(categoryKey);
    try {
      if (existing != null) {
        await ApiService.instance.updateWebRule(
          widget.childId,
          existing.id,
          isEnabled: enable,
        );
        setState(() => existing.isEnabled = enable);
      } else {
        final newRuleMap = await ApiService.instance.createWebRule(
          widget.childId,
          ruleType: 'CATEGORY',
          target: categoryKey,
          action: 'BLOCK',
          isEnabled: enable,
        );
        setState(() => _rules.insert(0, WebBlockRule.fromJson(newRuleMap)));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(enable ? 'Filter enabled' : 'Filter disabled'),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update filter: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _addCustomRule() async {
    final targetController = TextEditingController();
    String ruleType = 'DOMAIN';
    String action = 'BLOCK';

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Web Filter Rule'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: targetController,
                decoration: const InputDecoration(
                  labelText: 'Website Domain or Keyword',
                  hintText: 'e.g. roblox.com, *casino*, tiktok',
                  helperText: 'Supports wildcards like *.bet or *gambling*',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              const Text('Rule Type:', style: TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Radio<String>(
                    value: 'DOMAIN',
                    groupValue: ruleType,
                    onChanged: (val) => setDialogState(() => ruleType = val!),
                  ),
                  const Text('Domain'),
                  const SizedBox(width: 16),
                  Radio<String>(
                    value: 'KEYWORD',
                    groupValue: ruleType,
                    onChanged: (val) => setDialogState(() => ruleType = val!),
                  ),
                  const Text('Keyword'),
                ],
              ),
              const SizedBox(height: 8),
              const Text('Action:', style: TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Radio<String>(
                    value: 'BLOCK',
                    groupValue: action,
                    onChanged: (val) => setDialogState(() => action = val!),
                  ),
                  const Text('Block (Blacklist)'),
                  const SizedBox(width: 16),
                  Radio<String>(
                    value: 'ALLOW',
                    groupValue: action,
                    onChanged: (val) => setDialogState(() => action = val!),
                  ),
                  const Text('Allow (Whitelist)'),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add Rule'),
            ),
          ],
        ),
      ),
    );

    if (created == true && targetController.text.trim().isNotEmpty) {
      try {
        final newRuleMap = await ApiService.instance.createWebRule(
          widget.childId,
          ruleType: ruleType,
          target: targetController.text.trim(),
          action: action,
          isEnabled: true,
        );
        setState(() => _rules.insert(0, WebBlockRule.fromJson(newRuleMap)));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Added rule: ${targetController.text.trim()}')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to add rule: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _deleteRule(WebBlockRule rule) async {
    try {
      await ApiService.instance.deleteWebRule(widget.childId, rule.id);
      setState(() => _rules.removeWhere((r) => r.id == rule.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted rule: ${rule.target}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete rule: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final customRules = _rules.where((r) => r.ruleType != 'CATEGORY').toList();

    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.childName}'s Web Filter"),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadRules),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.category), text: 'Categories'),
            Tab(icon: Icon(Icons.link), text: 'Custom Rules'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 1: Category Toggles
                    ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Card(
                          color: Colors.blue.shade50,
                          child: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.blue),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Category filters block inappropriate websites and search queries locally on the device.',
                                    style: TextStyle(fontSize: 13, color: Colors.blueGrey),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        for (final entry in _predefinedCategories.entries) ...[
                          _categoryTile(entry.key, entry.value),
                          const Divider(height: 1),
                        ],
                      ],
                    ),

                    // Tab 2: Custom Rules
                    customRules.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.language, size: 64, color: Colors.grey),
                                const SizedBox(height: 16),
                                const Text('No custom website rules added yet.'),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add Blocked Website'),
                                  onPressed: _addCustomRule,
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: customRules.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (ctx, idx) {
                              final rule = customRules[idx];
                              final isBlock = rule.action == 'BLOCK';
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isBlock ? Colors.red.shade100 : Colors.green.shade100,
                                  child: Icon(
                                    isBlock ? Icons.block : Icons.check,
                                    color: isBlock ? Colors.red : Colors.green,
                                  ),
                                ),
                                title: Text(rule.target, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                  '${rule.ruleType} • ${rule.action}',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Switch(
                                      value: rule.isEnabled,
                                      onChanged: (val) async {
                                        try {
                                          await ApiService.instance.updateWebRule(
                                            widget.childId,
                                            rule.id,
                                            isEnabled: val,
                                          );
                                          setState(() => rule.isEnabled = val);
                                        } catch (_) {}
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                                      onPressed: () => _deleteRule(rule),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ],
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCustomRule,
        icon: const Icon(Icons.add),
        label: const Text('Add Web Rule'),
      ),
    );
  }

  Widget _categoryTile(String categoryKey, String title) {
    final existing = _findCategoryRule(categoryKey);
    final isEnabled = existing?.isEnabled ?? false;

    IconData icon;
    switch (categoryKey) {
      case 'ADULT':
        icon = Icons.warning_amber_rounded;
        break;
      case 'GAMBLING':
        icon = Icons.casino;
        break;
      case 'GAMING':
        icon = Icons.sports_esports;
        break;
      case 'SOCIAL':
        icon = Icons.people;
        break;
      case 'VIOLENCE':
        icon = Icons.security;
        break;
      case 'SAFESEARCH':
        icon = Icons.search;
        break;
      default:
        icon = Icons.shield;
    }

    return SwitchListTile(
      secondary: CircleAvatar(
        backgroundColor: isEnabled ? Colors.red.shade100 : Colors.grey.shade200,
        child: Icon(icon, color: isEnabled ? Colors.red.shade800 : Colors.grey.shade700),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(
        isEnabled ? 'Active (Blocked)' : 'Inactive (Allowed)',
        style: TextStyle(fontSize: 12, color: isEnabled ? Colors.red : Colors.grey),
      ),
      value: isEnabled,
      onChanged: (val) => _toggleCategory(categoryKey, val),
    );
  }
}

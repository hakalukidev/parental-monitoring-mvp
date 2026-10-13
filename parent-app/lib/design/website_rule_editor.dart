import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class WebsiteRuleEditor extends StatefulWidget {
  final String childId;
  final String target;
  final String ruleType;
  final String action;
  const WebsiteRuleEditor(
      {super.key,
      required this.childId,
      this.target = '',
      this.ruleType = 'DOMAIN',
      this.action = 'BLOCK'});
  @override
  State<WebsiteRuleEditor> createState() => _WebsiteRuleEditorState();
}

class _WebsiteRuleEditorState extends State<WebsiteRuleEditor> {
  late final TextEditingController _target;
  late String _type, _action;
  Timer? _timer;
  int _revision = 0;
  Map<String, dynamic>? _preview;
  String? _error;
  bool _checking = false;
  @override
  void initState() {
    super.initState();
    _target = TextEditingController(text: widget.target);
    _type = widget.ruleType;
    _action = widget.action;
    if (widget.target.isNotEmpty) _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _target.dispose();
    super.dispose();
  }

  void _schedule() {
    _timer?.cancel();
    final revision = ++_revision;
    setState(() {
      _preview = null;
      _error = null;
      _checking = _target.text.trim().isNotEmpty;
    });
    if (!_checking) return;
    _timer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final result = await ApiService.instance
            .previewWebRule(widget.childId, _type, _target.text);
        if (result['target'] is! String ||
            !['DOMAIN', 'URL', 'KEYWORD'].contains(result['ruleType'])) {
          throw StateError(
              'Website preview is unavailable. Update the server and retry.');
        }
        if (!mounted || revision != _revision) return;
        setState(() {
          _preview = result;
          _checking = false;
        });
      } catch (e) {
        if (!mounted || revision != _revision) return;
        setState(() {
          _error = e.toString();
          _checking = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
            widget.target.isEmpty ? 'Add a website rule' : 'Edit website rule'),
        content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
                child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                    controller: _target,
                    autofocus: true,
                    onChanged: (_) => _schedule(),
                    decoration: const InputDecoration(
                        labelText: 'Website address or keyword',
                        hintText: 'www.example.com or example.com/path',
                        helperText:
                            'HTTP/HTTPS, domains and *.example.com are supported')),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                    initialValue: _type,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Scope'),
                    items: const [
                      DropdownMenuItem(
                          value: 'DOMAIN',
                          child: Text('Domain and subdomains')),
                      DropdownMenuItem(
                          value: 'URL',
                          child: Text('Exact URL, path and query')),
                      DropdownMenuItem(value: 'KEYWORD', child: Text('Keyword'))
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        _type = v;
                        _schedule();
                      }
                    }),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'BLOCK',
                          label: Text('Block'),
                          icon: Icon(Icons.block)),
                      ButtonSegment(
                          value: 'ALLOW',
                          label: Text('Allow'),
                          icon: Icon(Icons.check))
                    ],
                    selected: {
                      _action
                    },
                    onSelectionChanged: (v) =>
                        setState(() => _action = v.first)),
                const SizedBox(height: 16),
                if (_checking)
                  const LinearProgressIndicator(
                      semanticsLabel: 'Checking website address'),
                if (_preview != null) ...[
                  const Text('Normalized address',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  SelectableText(_preview!['target'] as String),
                  Text(_preview!['ruleType'] == 'URL'
                      ? 'Matches this scheme, hostname, path and query only. Fragments are ignored.'
                      : _preview!['ruleType'] == 'DOMAIN'
                          ? 'Matches the site and its subdomains at hostname boundaries.'
                          : 'Allow rules take precedence over matching blocks.'),
                ],
                if (_error != null)
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                if (_error != null)
                  TextButton(
                      onPressed: _schedule,
                      child: const Text('Retry validation')),
                if (_preview?['requiresChildUpdate'] == true)
                  const Text(
                      'Update Seftly Child before saving an exact URL rule.'),
                const SizedBox(height: 8),
                const Text(
                    'A path-specific address is saved as an exact URL, never as a broader domain block.'),
              ],
            ))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: _preview == null ||
                      _preview?['requiresChildUpdate'] == true
                  ? null
                  : () =>
                      Navigator.pop(context, {..._preview!, 'action': _action}),
              child: const Text('Save rule'))
        ],
      );
}

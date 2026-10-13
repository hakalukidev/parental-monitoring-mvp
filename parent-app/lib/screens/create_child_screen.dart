import 'package:flutter/material.dart';
import '../design/form_validation.dart';
import '../design/seftly_widgets.dart';
import '../services/api_service.dart';

class CreateChildScreen extends StatefulWidget {
  const CreateChildScreen({super.key});
  @override
  State<CreateChildScreen> createState() => _CreateChildScreenState();
}

class _CreateChildScreenState extends State<CreateChildScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _username = TextEditingController(),
      _password = TextEditingController(),
      _confirm = TextEditingController();
  bool _loading = false;
  String? _error;
  @override
  void dispose() {
    for (final c in [_name, _username, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ApiService.instance.createChild(
          name: _name.text.trim(),
          username: _username.text.trim(),
          password: _password.text,
          confirmPassword: _confirm.text);
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: const Text('Ready to connect'),
                  content: Text(
                      'Install Seftly Child on ${_name.text.trim()}’s Android device. Sign in with ${_username.text.trim()} and the password you just created. Complete the guided setup together. Screen and camera sessions will still ask for approval each time.'),
                  actions: [
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Got it'))
                  ]));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => SeftlyScaffold(
      title: 'A place for your child',
      subtitle:
          '1. Create a login   2. Install Seftly Child   3. Set up together',
      icon: Icons.person_add_alt_1_outlined,
      appBar: AppBar(title: const Text('Add a child')),
      body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Card(
                      child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Form(
                              key: _formKey,
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text('Let’s get acquainted',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge),
                                    const SizedBox(height: 8),
                                    const Text(
                                        'Each child has their own login, device and rules.'),
                                    const SizedBox(height: 24),
                                    TextFormField(
                                        controller: _name,
                                        enabled: !_loading,
                                        decoration: const InputDecoration(
                                            labelText: 'Child’s name'),
                                        textCapitalization:
                                            TextCapitalization.words,
                                        textInputAction: TextInputAction.next,
                                        validator: FormValidation.name),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                        controller: _username,
                                        enabled: !_loading,
                                        decoration: const InputDecoration(
                                            labelText: 'Child’s username',
                                            helperText:
                                                'Use this to sign in on their device.'),
                                        textInputAction: TextInputAction.next,
                                        autocorrect: false,
                                        validator: FormValidation.username),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                        controller: _password,
                                        enabled: !_loading,
                                        obscureText: true,
                                        autocorrect: false,
                                        enableSuggestions: false,
                                        textInputAction: TextInputAction.next,
                                        decoration: const InputDecoration(
                                            labelText: 'Password',
                                            helperText:
                                                'At least eight characters'),
                                        validator: FormValidation.password),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                        controller: _confirm,
                                        enabled: !_loading,
                                        obscureText: true,
                                        autocorrect: false,
                                        enableSuggestions: false,
                                        decoration: const InputDecoration(
                                            labelText: 'Confirm password'),
                                        onFieldSubmitted: (_) => _submit(),
                                        validator: (v) => v != _password.text
                                            ? 'Passwords do not match'
                                            : FormValidation.password(v)),
                                    if (_error != null) ...[
                                      const SizedBox(height: 16),
                                      Semantics(
                                          liveRegion: true,
                                          child: Text(_error!,
                                              style: TextStyle(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .error)))
                                    ],
                                    const SizedBox(height: 24),
                                    FilledButton.icon(
                                        onPressed: _loading ? null : _submit,
                                        icon: const Icon(
                                            Icons.arrow_forward_rounded),
                                        label: Text(_loading
                                            ? 'Creating child account…'
                                            : 'Create child login')),
                                  ]))))))));
}

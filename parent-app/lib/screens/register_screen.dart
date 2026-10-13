import 'package:flutter/material.dart';
import '../design/form_validation.dart';
import '../design/seftly_widgets.dart';
import '../services/api_service.dart';
import 'dashboard_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _email = TextEditingController(),
      _password = TextEditingController(),
      _confirm = TextEditingController();
  bool _loading = false, _hidden = true;
  String? _error;
  @override
  void dispose() {
    for (final c in [_name, _email, _password, _confirm]) {
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
      await ApiService.instance.register(
          name: _name.text.trim(),
          email: _email.text.trim(),
          password: _password.text,
          confirmPassword: _confirm.text);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
          (_) => false);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthFrame(
      title: 'Your family, connected.',
      subtitle:
          'Create your parent account, then connect each child’s device with a separate login.',
      form: Form(
          key: _formKey,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Create an account',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 24),
            TextFormField(
                controller: _name,
                enabled: !_loading,
                decoration: const InputDecoration(
                    labelText: 'Your name',
                    prefixIcon: Icon(Icons.person_outline_rounded)),
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                validator: FormValidation.name),
            const SizedBox(height: 16),
            TextFormField(
                controller: _email,
                enabled: !_loading,
                decoration: const InputDecoration(
                    labelText: 'Email address',
                    prefixIcon: Icon(Icons.mail_outline_rounded)),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                validator: FormValidation.email),
            const SizedBox(height: 16),
            TextFormField(
                controller: _password,
                enabled: !_loading,
                obscureText: _hidden,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                    labelText: 'Password',
                    helperText:
                        'At least eight characters. Use a unique password.',
                    helperMaxLines: 2,
                    suffixIcon: IconButton(
                        tooltip: _hidden ? 'Show password' : 'Hide password',
                        onPressed: () => setState(() => _hidden = !_hidden),
                        icon: Icon(_hidden
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined))),
                validator: FormValidation.password),
            const SizedBox(height: 16),
            TextFormField(
                controller: _confirm,
                enabled: !_loading,
                obscureText: _hidden,
                autocorrect: false,
                enableSuggestions: false,
                decoration:
                    const InputDecoration(labelText: 'Confirm password'),
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
                          color: Theme.of(context).colorScheme.error)))
            ],
            const SizedBox(height: 24),
            FilledButton(
                onPressed: _loading ? null : _submit,
                child: Text(_loading
                    ? 'Creating your account…'
                    : 'Create parent account')),
            const SizedBox(height: 8),
            TextButton(
                onPressed: _loading ? null : () => Navigator.of(context).pop(),
                child: const Text('Already have an account? Sign in')),
          ])));
}

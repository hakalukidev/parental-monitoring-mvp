import 'package:flutter/material.dart';
import '../design/form_validation.dart';
import '../design/seftly_widgets.dart';
import '../services/api_service.dart';
import 'register_screen.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController(), _password = TextEditingController();
  bool _hidden = true, _loading = false;
  String? _error;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
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
      await ApiService.instance
          .login(email: _email.text.trim(), password: _password.text);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DashboardScreen()));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthFrame(
      title: 'Welcome back.',
      subtitle:
          'Keep close to the little things that matter.\nSign in to your family’s Seftly account.',
      form: AutofillGroup(
          child: Form(
              key: _formKey,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Sign in',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 24),
                    TextFormField(
                        controller: _email,
                        enabled: !_loading,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                            labelText: 'Email address',
                            prefixIcon: Icon(Icons.mail_outline_rounded)),
                        keyboardType: TextInputType.emailAddress,
                        validator: FormValidation.email),
                    const SizedBox(height: 16),
                    TextFormField(
                        controller: _password,
                        enabled: !_loading,
                        autofillHints: const [AutofillHints.password],
                        obscureText: _hidden,
                        enableSuggestions: false,
                        autocorrect: false,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                                tooltip:
                                    _hidden ? 'Show password' : 'Hide password',
                                onPressed: () =>
                                    setState(() => _hidden = !_hidden),
                                icon: Icon(_hidden
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined))),
                        validator: (v) => v == null || v.isEmpty
                            ? 'Enter your password'
                            : null),
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
                        child: _loading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Sign in to Seftly')),
                    const SizedBox(height: 12),
                    TextButton(
                        onPressed: _loading
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => const RegisterScreen())),
                        child: const Text('New here? Create a parent account')),
                  ]))));
}

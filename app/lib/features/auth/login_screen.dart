import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).login(_user.text, _pass.text);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _serverSettings() async {
    final store = ref.read(localStoreProvider);
    final ctrl = TextEditingController(text: store.serverUrl);
    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Server address'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'http://192.168.1.10:8000')),
          const SizedBox(height: 8),
          const Text(
            'Same computer: http://localhost:8000\n'
            'Android emulator: http://10.0.2.2:8000\n'
            'Phone on Wi-Fi: http://<computer IP>:8000',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved == true && ctrl.text.trim().isNotEmpty) {
      await store.setServerUrl(ctrl.text);
      if (mounted) {
        setState(() => _error = null); // refresh the "Server:" line
        showSnack(context, 'Server set to ${store.serverUrl}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final height = MediaQuery.sizeOf(context).height;
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(children: [
        // Green brand band behind the card.
        Container(height: height * 0.42, decoration: const BoxDecoration(gradient: AppColors.brandGradient)),
        Positioned(
          top: -60,
          right: -40,
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.06)),
          ),
        ),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: softShadow),
                    child: const AppLogo(size: 84),
                  ),
                  const SizedBox(height: 16),
                  Text('M Ishaq Poultry Services',
                      textAlign: TextAlign.center,
                      style: t.headlineSmall?.copyWith(color: Colors.white)),
                  const SizedBox(height: 4),
                  Text('Supply · Invoices · Customer Accounts',
                      textAlign: TextAlign.center,
                      style: t.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85))),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: softShadow,
                    ),
                    child: Form(
                      key: _form,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text('Welcome back', style: t.titleLarge),
                        const SizedBox(height: 4),
                        Text('Sign in to continue', style: t.bodyMedium?.copyWith(color: AppColors.textMuted)),
                        const SizedBox(height: 22),
                        TextFormField(
                          controller: _user,
                          decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person_outline)),
                          textInputAction: TextInputAction.next,
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter username' : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _pass,
                          obscureText: _hide,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                              onPressed: () => setState(() => _hide = !_hide),
                            ),
                          ),
                          onFieldSubmitted: (_) => _submit(),
                          validator: (v) => (v == null || v.isEmpty) ? 'Enter password' : null,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFDECEC),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Icon(Icons.error_outline, color: AppColors.due, size: 20),
                              const SizedBox(width: 8),
                              Expanded(child: Text(_error!, style: t.bodyMedium?.copyWith(color: AppColors.due))),
                            ]),
                          ),
                        ],
                        const SizedBox(height: 22),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(
                                  height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                              : const Text('Login'),
                        ),
                        const SizedBox(height: 10),
                        TextButton.icon(
                          onPressed: _serverSettings,
                          icon: const Icon(Icons.dns_outlined, size: 18),
                          label: const Text('Server settings'),
                        ),
                        Text(
                          'Server: ${ref.read(localStoreProvider).serverUrl}',
                          textAlign: TextAlign.center,
                          style: t.bodySmall?.copyWith(color: AppColors.textMuted),
                        ),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

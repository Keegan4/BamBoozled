import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../../core/theme/colors.dart';
import '../../core/theme/panda_theme.dart';
import '../../core/widgets/panda_mascot.dart';
import '../../data/providers.dart';

/// Email and password. Accounts are added by the project owner in Supabase, so there is no sign-up.
class SignInDialog extends ConsumerStatefulWidget {
  const SignInDialog({super.key});

  @override
  ConsumerState<SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends ConsumerState<SignInDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _show = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy) return;
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = 'Please enter a valid email address');
      return;
    }
    if (_password.text.isEmpty) {
      setState(() => _error = 'Please enter your password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider)!.signIn(email, _password.text);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Signed in — your tasks will now sync.')));
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is AuthException
              ? 'That email or password didn’t work. Check them, or ask whoever set up your account.'
              : 'We couldn’t reach the server. Check your internet connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    // Centered so the dialog's tight width doesn't stretch the panda over the text below it.
    icon: const Center(child: PandaMascot(size: 72)),
    title: const Text('Sign in to sync', style: PandaText.title),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Use the email and password you were given.',
              style: PandaText.body.copyWith(color: PandaColors.muted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(hintText: 'you@school.edu.sg'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: !_show,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                hintText: 'Password',
                suffixIcon: IconButton(
                  tooltip: _show ? 'Hide password' : 'Show password',
                  icon: Icon(_show ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                  onPressed: () => setState(() => _show = !_show),
                ),
              ),
              onSubmitted: (_) => _signIn(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: PandaText.caption.copyWith(color: PandaColors.overdue)),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      FilledButton(onPressed: _busy ? null : _signIn, child: const Text('Sign in')),
    ],
  );
}

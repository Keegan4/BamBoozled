import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/panda_theme.dart';
import '../../core/widgets/panda_mascot.dart';
import '../../data/providers.dart';

/// Two steps: enter email → enter the 6-digit code from the email.
class SignInDialog extends ConsumerStatefulWidget {
  const SignInDialog({super.key});

  @override
  ConsumerState<SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends ConsumerState<SignInDialog> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String failure) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _error = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() async {
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = 'Please enter a valid email address');
      return;
    }
    await _run(() async {
      await ref.read(authServiceProvider)!.sendCode(email);
      if (mounted) setState(() => _codeSent = true);
    }, 'We couldn’t send the email. Check your internet connection and try again.');
  }

  Future<void> _verify() async {
    await _run(() async {
      await ref.read(authServiceProvider)!.verifyCode(_email.text, _code.text);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Signed in — your tasks will now sync.')));
    }, 'That code didn’t work. Check it, or ask for a new one.');
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const PandaMascot(size: 72),
    title: Text(_codeSent ? 'Check your email' : 'Sign in to sync', style: PandaText.title),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _codeSent
                ? 'We sent a 6-digit code to ${_email.text.trim()}. Type it below.'
                : 'We’ll email you a 6-digit code. No password needed.',
            style: PandaText.body.copyWith(color: PandaColors.muted),
          ),
          const SizedBox(height: 16),
          if (!_codeSent)
            TextField(
              controller: _email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(hintText: 'you@school.edu.sg'),
              onSubmitted: (_) => _sendCode(),
            )
          else
            TextField(
              controller: _code,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              style: PandaText.title.copyWith(letterSpacing: 8),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(hintText: '123456'),
              onSubmitted: (_) => _verify(),
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: PandaText.caption.copyWith(color: PandaColors.overdue)),
          ],
        ],
      ),
    ),
    actions: [
      if (_codeSent)
        TextButton(
          onPressed: _busy ? null : () => setState(() => _codeSent = false),
          child: const Text('Use a different email'),
        )
      else
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      FilledButton(
        onPressed: _busy ? null : (_codeSent ? _verify : _sendCode),
        child: Text(_codeSent ? 'Sign in' : 'Email me a code'),
      ),
    ],
  );
}

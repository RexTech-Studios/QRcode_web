import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/auth_service.dart';
import '../../utils/app_colors.dart';
import '../../widgets/section_card.dart';

/// Counts failed sign-ins and locks the form for a while after too many.
/// UX only: a page reload resets it, and Firebase rate-limits on the server.
class LoginAttemptTracker {
  LoginAttemptTracker({
    this.maxAttempts = 5,
    this.cooldown = const Duration(seconds: 60),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int maxAttempts;
  final Duration cooldown;
  final DateTime Function() _clock;

  int _failures = 0;
  DateTime? _lockedUntil;

  void recordFailure() {
    _failures++;
    if (_failures >= maxAttempts) {
      _failures = 0;
      _lockedUntil = _clock().add(cooldown);
    }
  }

  void reset() {
    _failures = 0;
    _lockedUntil = null;
  }

  Duration get remaining {
    final until = _lockedUntil;
    if (until == null) return Duration.zero;
    final left = until.difference(_clock());
    return left.isNegative ? Duration.zero : left;
  }

  bool get isLocked => remaining > Duration.zero;
}

/// Admin sign-in. Shown by the auth gate whenever nobody is signed in.
class LoginScreen extends StatefulWidget {
  /// Shown above the form, e.g. after a non-admin account was signed out.
  final String? notice;

  const LoginScreen({super.key, this.notice});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _tracker = LoginAttemptTracker();

  Timer? _cooldownTicker;
  bool _obscurePassword = true;
  bool _busy = false;
  String? _error;
  String? _resetConfirmation;

  @override
  void dispose() {
    _cooldownTicker?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _startCooldownTicker() {
    _cooldownTicker?.cancel();
    _cooldownTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_tracker.isLocked) {
        timer.cancel();
        _error = null;
      }
      if (mounted) setState(() {});
    });
  }

  Future<void> _submit() async {
    if (_busy || _tracker.isLocked) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _error = 'Enter your email and password.';
        _resetConfirmation = null;
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _resetConfirmation = null;
    });

    final result = await AuthService.signIn(email, password);

    // On success the auth gate replaces this screen, unless the account turns
    // out not to be the admin, when the form has to be usable again.
    if (!mounted) return;
    if (result.isSuccess) {
      TextInput.finishAutofillContext();
      _tracker.reset();
      _passwordController.clear();
    } else if (result.isCredentialFailure) {
      _tracker.recordFailure();
      if (_tracker.isLocked) _startCooldownTicker();
    }
    setState(() {
      _busy = false;
      _error = result.error;
    });
  }

  Future<void> _forgotPassword() async {
    if (_busy) return;

    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() {
        _error = 'Enter your email above, then tap "Forgot password?" again.';
        _resetConfirmation = null;
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _resetConfirmation = null;
    });

    await AuthService.sendPasswordReset(email);

    if (!mounted) return;
    setState(() {
      _busy = false;
      _resetConfirmation =
          'If an account exists for that email, a password reset link is on its way.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final locked = _tracker.isLocked;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SectionCard(
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _Brand(),
                      const SizedBox(height: 22),
                      const Text(
                        'Admin sign in',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (widget.notice != null) ...[
                        _Message(text: widget.notice!, isError: true),
                        const SizedBox(height: 14),
                      ],
                      const FieldLabel('Email'),
                      TextField(
                        controller: _emailController,
                        enabled: !_busy,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username],
                        autocorrect: false,
                      ),
                      const SizedBox(height: 14),
                      const FieldLabel('Password'),
                      TextField(
                        controller: _passwordController,
                        enabled: !_busy,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        autocorrect: false,
                        enableSuggestions: false,
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 20,
                              color: AppColors.iconMuted,
                            ),
                          ),
                        ),
                      ),
                      if (locked) ...[
                        const SizedBox(height: 14),
                        _Message(
                          text:
                              'Too many failed attempts. Try again in ${_tracker.remaining.inSeconds + 1}s.',
                          isError: true,
                        ),
                      ] else if (_error != null) ...[
                        const SizedBox(height: 14),
                        _Message(text: _error!, isError: true),
                      ],
                      if (_resetConfirmation != null) ...[
                        const SizedBox(height: 14),
                        _Message(text: _resetConfirmation!, isError: false),
                      ],
                      const SizedBox(height: 18),
                      ElevatedButton(
                        onPressed: _busy || locked ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Sign in'),
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: _busy ? null : _forgotPassword,
                        child: const Text('Forgot password?'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.chat_bubble, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 10),
        const Text(
          'ReviewQR',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  final bool isError;

  const _Message({required this.text, required this.isError});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: isError ? AppColors.danger : AppColors.primary,
      ),
    );
  }
}

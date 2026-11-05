import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'firebase_service.dart';

/// Outcome of a sign-in attempt. [error] is safe to show to the user.
class SignInResult {
  final String? error;

  /// True for wrong email/password, so the login screen can count it towards
  /// its cooldown. Network failures and the like don't count.
  final bool isCredentialFailure;

  const SignInResult.success() : error = null, isCredentialFailure = false;

  const SignInResult.failure(String this.error, {this.isCredentialFailure = false});

  bool get isSuccess => error == null;
}

/// Wraps Firebase Auth for the admin login. Email + password only, and there
/// is deliberately no sign-up: the admin account is created in the console.
class AuthService {
  AuthService._();

  static const String _defaultError = 'Could not sign in. Please try again.';

  /// Every code that means "those credentials didn't work". They all map to
  /// one message so a visitor can't tell which of the two was wrong, or
  /// whether the account exists at all.
  static const Set<String> _credentialErrorCodes = {
    'invalid-credential',
    'invalid-login-credentials',
    'wrong-password',
    'user-not-found',
    'invalid-email',
  };

  static bool isCredentialErrorCode(String code) =>
      _credentialErrorCodes.contains(code);

  static String messageForCode(String code) {
    if (isCredentialErrorCode(code)) return 'Incorrect email or password.';
    switch (code) {
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a few minutes and try again.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      default:
        return _defaultError;
    }
  }

  static Stream<User?> get authStateChanges => FirebaseService.isAvailable
      ? FirebaseAuth.instance.authStateChanges()
      : Stream<User?>.value(null);

  static String? get currentUid => FirebaseService.isAvailable
      ? FirebaseAuth.instance.currentUser?.uid
      : null;

  /// Completes once Firebase has restored any saved session, so the splash
  /// can cover that wait. Never throws: the auth gate stays closed either way.
  static Future<void> waitForInitialAuthState() async {
    try {
      await authStateChanges.first.timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('AuthService.waitForInitialAuthState: $e');
    }
  }

  static Future<SignInResult> signIn(String email, String password) async {
    if (!FirebaseService.isAvailable) {
      return const SignInResult.failure(_defaultError);
    }
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return const SignInResult.success();
    } on FirebaseAuthException catch (e) {
      return SignInResult.failure(
        messageForCode(e.code),
        isCredentialFailure: isCredentialErrorCode(e.code),
      );
    } catch (e) {
      debugPrint('AuthService.signIn failed: $e');
      return const SignInResult.failure(_defaultError);
    }
  }

  static Future<void> signOut() async {
    if (!FirebaseService.isAvailable) return;
    await FirebaseAuth.instance.signOut();
  }

  /// Never reports the outcome: the caller always shows the same neutral
  /// confirmation, so this can't be used to discover which emails exist.
  static Future<void> sendPasswordReset(String email) async {
    if (!FirebaseService.isAvailable) return;
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      debugPrint('AuthService.sendPasswordReset failed: ${e.code}');
    } catch (e) {
      debugPrint('AuthService.sendPasswordReset failed: $e');
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reviewqr_admin/screens/auth/login_screen.dart';
import 'package:reviewqr_admin/services/auth_service.dart';

void main() {
  group('AuthService.messageForCode', () {
    test('wrong email and wrong password are indistinguishable', () {
      final messages = {
        for (final code in [
          'invalid-credential',
          'invalid-login-credentials',
          'wrong-password',
          'user-not-found',
          'invalid-email',
        ])
          AuthService.messageForCode(code),
      };
      expect(messages, hasLength(1));
      expect(messages.single, isNot(contains('account')));
    });

    test('other failures get their own message', () {
      expect(AuthService.messageForCode('user-disabled'), contains('disabled'));
      expect(AuthService.messageForCode('too-many-requests'), contains('Too many'));
      expect(AuthService.messageForCode('network-request-failed'), contains('Network'));
    });

    test('an unknown code falls back without leaking it', () {
      expect(
        AuthService.messageForCode('some-new-code'),
        isNot(contains('some-new-code')),
      );
    });

    test('only credential errors count towards the cooldown', () {
      expect(AuthService.isCredentialErrorCode('invalid-credential'), isTrue);
      expect(AuthService.isCredentialErrorCode('network-request-failed'), isFalse);
      expect(AuthService.isCredentialErrorCode('too-many-requests'), isFalse);
    });
  });

  group('LoginAttemptTracker', () {
    late DateTime now;
    late LoginAttemptTracker tracker;

    setUp(() {
      now = DateTime(2026, 1, 1);
      tracker = LoginAttemptTracker(clock: () => now);
    });

    test('locks on the fifth failure, not before', () {
      for (var i = 0; i < 4; i++) {
        tracker.recordFailure();
      }
      expect(tracker.isLocked, isFalse);
      tracker.recordFailure();
      expect(tracker.isLocked, isTrue);
    });

    test('unlocks after the cooldown and starts counting afresh', () {
      for (var i = 0; i < 5; i++) {
        tracker.recordFailure();
      }
      now = now.add(const Duration(seconds: 61));
      expect(tracker.isLocked, isFalse);
      tracker.recordFailure();
      expect(tracker.isLocked, isFalse);
    });

    test('reset clears a lock', () {
      for (var i = 0; i < 5; i++) {
        tracker.recordFailure();
      }
      tracker.reset();
      expect(tracker.isLocked, isFalse);
    });
  });

  group('LoginScreen', () {
    Widget app({String? notice}) =>
        MaterialApp(home: LoginScreen(notice: notice));

    testWidgets('fits a 320px phone without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(app(notice: 'Not authorized.'));
      expect(tester.takeException(), isNull);
      expect(find.text('Not authorized.'), findsOneWidget);
    });

    testWidgets('has no sign-up path', (tester) async {
      await tester.pumpWidget(app());
      expect(find.textContaining(RegExp('sign up|create account|register', caseSensitive: false)), findsNothing);
    });

    testWidgets('toggles password visibility', (tester) async {
      await tester.pumpWidget(app());
      bool obscured() =>
          tester.widgetList<TextField>(find.byType(TextField)).last.obscureText;

      expect(obscured(), isTrue);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(obscured(), isFalse);
    });

    testWidgets('asks for both fields before calling Firebase', (tester) async {
      await tester.pumpWidget(app());
      await tester.tap(find.text('Sign in'));
      await tester.pump();
      expect(find.text('Enter your email and password.'), findsOneWidget);
    });
  });
}

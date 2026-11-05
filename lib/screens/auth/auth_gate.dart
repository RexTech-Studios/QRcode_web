import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/navigation_provider.dart';
import '../../providers/qr_provider.dart';
import '../../providers/shop_provider.dart';
import '../../services/auth_service.dart';
import '../../services/hive_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_config.dart';
import '../dashboard/dashboard_screen.dart';
import 'login_screen.dart';

enum _GateState { waiting, signedOut, loadingData, admin }

/// The only way into the dashboard. Fails closed: [DashboardScreen] is built
/// only once the signed-in uid matches [AppConfig.adminUid] and its data has
/// loaded. Every other state shows a spinner or the login form.
///
/// This hides the UI. firestore.rules is what actually protects the data.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<User?>? _authSubscription;
  _GateState _state = _GateState.waiting;
  bool _notAuthorized = false;

  /// Bumped on every auth event so a slow load can tell it has been overtaken.
  int _authEvent = 0;

  @override
  void initState() {
    super.initState();
    _authSubscription = AuthService.authStateChanges.listen(_onAuthChanged);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _onAuthChanged(User? user) async {
    final event = ++_authEvent;

    if (user == null) {
      // Runs for any sign-out, including one from another tab, and for a
      // signed-out first load, which also clears anything an older build
      // cached in this browser before there was a login.
      await _clearLocalData();
      if (!mounted || event != _authEvent) return;
      setState(() => _state = _GateState.signedOut);
      return;
    }

    if (!AppConfig.isAdmin(user.uid)) {
      _notAuthorized = true;
      // Drop the dashboard straight away if a different account signed in
      // from another tab. The sign-out below then lands in the branch above.
      if (_state == _GateState.admin || _state == _GateState.loadingData) {
        setState(() => _state = _GateState.waiting);
      }
      await AuthService.signOut();
      return;
    }

    setState(() {
      _notAuthorized = false;
      _state = _GateState.loadingData;
    });
    await _loadAdminData();
    if (!mounted) return;
    if (event != _authEvent) {
      // Signed out mid-load, so the load may have refilled the cache that
      // sign-out just cleared.
      if (!AppConfig.isAdmin(AuthService.currentUid)) await _clearLocalData();
      return;
    }
    setState(() => _state = _GateState.admin);
  }

  Future<void> _loadAdminData() async {
    final shopProvider = context.read<ShopProvider>();
    final qrProvider = context.read<QrProvider>();
    final fresh = await Future.wait([
      shopProvider.loadShops(),
      qrProvider.loadQrCodes(),
    ]);
    // Only against fresh data: a stale cache could wrongly say a code is missing.
    if (fresh.every((isFresh) => isFresh)) {
      await shopProvider.backfillQrCodes(qrProvider.qrCodes);
    }
  }

  Future<void> _clearLocalData() async {
    if (!mounted) return;
    final shopProvider = context.read<ShopProvider>();
    final qrProvider = context.read<QrProvider>();
    final navigationProvider = context.read<NavigationProvider>();

    await HiveService.clearShopsAndQrCodes();
    shopProvider.reset();
    qrProvider.reset();
    navigationProvider.reset();
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _GateState.admin:
        return const DashboardScreen();
      case _GateState.signedOut:
        return LoginScreen(
          notice: _notAuthorized
              ? 'Not authorized. This account does not have admin access.'
              : null,
        );
      case _GateState.waiting:
      case _GateState.loadingData:
        return const Scaffold(
          backgroundColor: AppColors.scaffoldBackground,
          body: Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        );
    }
  }
}

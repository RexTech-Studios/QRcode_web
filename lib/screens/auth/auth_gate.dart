import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/sales_user_model.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/qr_provider.dart';
import '../../providers/rep_provider.dart';
import '../../providers/sales_admin_provider.dart';
import '../../providers/shop_provider.dart';
import '../../services/auth_service.dart';
import '../../services/hive_service.dart';
import '../../services/sales_repository.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_config.dart';
import '../../utils/gate_access.dart';
import '../dashboard/dashboard_screen.dart';
import '../sales/rep_home_screen.dart';
import 'login_screen.dart';

enum _GateState { waiting, signedOut, loadingData, admin, rep }

/// The only way into the dashboard or the sales screen. Fails closed:
/// [DashboardScreen] is built only once the signed-in uid matches
/// [AppConfig.adminUid] and its data has loaded, and [RepHomeScreen] only for
/// an active sales account the admin created. Every other state shows a
/// spinner or the login form.
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
  String? _notice;

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

  bool get _signedInAsAdmin => AppConfig.isAdmin(AuthService.currentUid);

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

    if (AppConfig.isAdmin(user.uid)) {
      setState(() {
        _notice = null;
        _state = _GateState.loadingData;
      });
      await _loadAdminData();
      if (!mounted) return;
      if (event != _authEvent) {
        // Signed out mid-load, so the load may have refilled the cache that
        // sign-out just cleared.
        if (!_signedInAsAdmin) await _clearLocalData();
        return;
      }
      setState(() => _state = _GateState.admin);
      return;
    }

    // Anyone else must be a sales person the admin created. Drop whatever was
    // on screen straight away, then check their record.
    setState(() {
      _notice = null;
      _state = _GateState.loadingData;
    });

    SalesUser? salesUser;
    try {
      salesUser = await context.read<SalesRepository>().fetchUser(user.uid);
    } catch (_) {
      // Can't prove who this is, so don't let them in.
      _rejectAndSignOut(
        'Could not check your account. Check your connection and try again.',
      );
      return;
    }
    if (!mounted || event != _authEvent) return;

    switch (decideGateAccess(user.uid, salesUser)) {
      case GateAccess.rep:
        await context.read<RepProvider>().load(salesUser!);
        if (!mounted) return;
        if (event != _authEvent) {
          await _clearLocalData();
          return;
        }
        setState(() => _state = _GateState.rep);
      case GateAccess.disabled:
        _rejectAndSignOut(
          'This account has been turned off. Contact the admin.',
        );
      case GateAccess.notAuthorized:
      case GateAccess.admin:
        _rejectAndSignOut('Not authorized. This account does not have access.');
    }
  }

  /// Sign-out lands in the signed-out branch above, which shows the notice.
  void _rejectAndSignOut(String notice) {
    _notice = notice;
    if (mounted) setState(() => _state = _GateState.waiting);
    AuthService.signOut();
  }

  Future<void> _loadAdminData() async {
    final shopProvider = context.read<ShopProvider>();
    final qrProvider = context.read<QrProvider>();
    // Never throws, so a problem with the sales team can't block the dashboard.
    final salesLoad = context.read<SalesAdminProvider>().load();
    final fresh = await Future.wait([
      shopProvider.loadShops(),
      qrProvider.loadQrCodes(),
    ]);
    await salesLoad;
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
    final salesAdminProvider = context.read<SalesAdminProvider>();
    final repProvider = context.read<RepProvider>();

    await HiveService.clearShopsAndQrCodes();
    shopProvider.reset();
    qrProvider.reset();
    navigationProvider.reset();
    salesAdminProvider.reset();
    repProvider.reset();
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _GateState.admin:
        return const DashboardScreen();
      case _GateState.rep:
        return const RepHomeScreen();
      case _GateState.signedOut:
        return LoginScreen(notice: _notice);
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

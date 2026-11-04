import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/navigation_provider.dart';
import 'providers/qr_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/shop_provider.dart';
import 'screens/customer/review_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/splash/splash_screen.dart';
import 'services/firebase_service.dart';
import 'services/hive_service.dart';
import 'utils/app_theme.dart';
import 'widgets/viewport_compensator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HiveService.init();
  await FirebaseService.init();

  // A customer scanning a QR code lands on "/review/<id>". That public page
  // only needs the single shop it looks up itself, so skip the admin-side
  // "fetch every shop / qr code" syncs that would otherwise fire at startup
  // and slow the first paint for the vast majority of visitors.
  final firstSegment = Uri.base.pathSegments.isNotEmpty
      ? Uri.base.pathSegments.first
      : '';
  final isReviewRoute = firstSegment == 'review';

  runApp(ReviewQrAdminApp(isReviewRoute: isReviewRoute));
}

class ReviewQrAdminApp extends StatelessWidget {
  final bool isReviewRoute;

  const ReviewQrAdminApp({super.key, this.isReviewRoute = false});

  static Route<dynamic>? _generateRoute(RouteSettings settings) {
    final uri = Uri.parse(settings.name ?? '/');
    if (uri.pathSegments.length == 2 && uri.pathSegments.first == 'review') {
      final shopId = uri.pathSegments[1];
      return MaterialPageRoute(
        builder: (_) => ViewportCompensator(
          child: ReviewScreen(shopId: shopId),
        ),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NavigationProvider()),
        // On the public review route these admin providers stay idle: their
        // Firestore "fetch all" syncs are skipped so they don't compete with
        // the review page's single-shop lookup. They still initialize lazily
        // (and load) if the dashboard is ever navigated to in this session.
        ChangeNotifierProvider(
          create: (_) => isReviewRoute ? ShopProvider() : (ShopProvider()..loadShops()),
        ),
        ChangeNotifierProvider(
          create: (_) => isReviewRoute ? QrProvider() : (QrProvider()..loadQrCodes()),
        ),
        ChangeNotifierProvider(
          create: (_) => isReviewRoute ? SettingsProvider() : (SettingsProvider()..loadSettings()),
        ),
      ],
      child: MaterialApp(
        title: 'ReviewQR Admin',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        // No `home:` here — onGenerateInitialRoutes below owns the initial
        // route (and falls back to the splash screen). Specifying both trips
        // a framework assertion: "home argument will be redundant".
        onGenerateRoute: _generateRoute,
        // The default initial-route builder walks every path prefix
        // ("/", "/review", "/review/<id>") and stacks a route for each
        // match, so a deep link to "/review/<id>" silently pushes the home
        // route underneath it too - one back press then lands on the
        // dashboard instead of exiting. Returning only the matched route
        // keeps the initial stack to a single entry.
        onGenerateInitialRoutes: (initialRouteName) {
          final route = _generateRoute(RouteSettings(name: initialRouteName));
          if (route != null) return [route];
          return [
            MaterialPageRoute(
              builder: (_) => SplashScreen(next: (_) => const DashboardScreen()),
            ),
          ];
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/navigation_provider.dart';
import 'providers/qr_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/shop_provider.dart';
import 'screens/auth/auth_gate.dart';
import 'screens/customer/link_not_found_screen.dart';
import 'screens/customer/review_screen.dart';
import 'screens/splash/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/firebase_service.dart';
import 'services/hive_service.dart';
import 'utils/app_routes.dart';
import 'utils/app_theme.dart';
import 'widgets/viewport_compensator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HiveService.init();
  await FirebaseService.init();

  runApp(ReviewQrAdminApp(isReviewRoute: isReviewLocation(Uri.base)));
}

class ReviewQrAdminApp extends StatelessWidget {
  final bool isReviewRoute;

  const ReviewQrAdminApp({super.key, this.isReviewRoute = false});

  static Route<dynamic> _generateRoute(RouteSettings settings) {
    final route = settings.name ?? '/';

    final shopId = reviewShopId(route);
    if (shopId != null) {
      return MaterialPageRoute(
        builder: (_) => ViewportCompensator(
          child: ReviewScreen(shopId: shopId),
        ),
      );
    }

    if (isReviewPath(route)) {
      return MaterialPageRoute(builder: (_) => const LinkNotFoundScreen());
    }

    // "/" and every unknown route.
    return MaterialPageRoute(
      builder: (_) => SplashScreen(
        init: AuthService.waitForInitialAuthState,
        next: (_) => const AuthGate(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NavigationProvider()),
        // Shops and QR codes load from AuthGate once the admin is confirmed,
        // never here: signed-out visitors and customers must not fetch them.
        ChangeNotifierProvider(create: (_) => ShopProvider()),
        ChangeNotifierProvider(create: (_) => QrProvider()),
        ChangeNotifierProvider(
          create: (_) => isReviewRoute ? SettingsProvider() : (SettingsProvider()..loadSettings()),
        ),
      ],
      child: MaterialApp(
        title: 'Full Star QR Admin',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        // No `home:` here — onGenerateInitialRoutes below owns the initial
        // route. Specifying both trips a framework assertion: "home argument
        // will be redundant".
        onGenerateRoute: _generateRoute,
        // The default initial-route builder walks every path prefix
        // ("/", "/review", "/review/<id>") and stacks a route for each
        // match, so a deep link to "/review/<id>" silently pushes the home
        // route underneath it too - one back press then lands on the
        // login instead of exiting. Returning only the matched route
        // keeps the initial stack to a single entry.
        onGenerateInitialRoutes: (initialRouteName) => [
          _generateRoute(RouteSettings(name: initialRouteName)),
        ],
      ),
    );
  }
}

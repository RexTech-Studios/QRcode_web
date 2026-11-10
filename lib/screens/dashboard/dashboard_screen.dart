import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/navigation_provider.dart';
import '../../utils/app_colors.dart';
import '../../widgets/sidebar.dart';
import '../../widgets/top_bar.dart';
import '../analytics/analytics_screen.dart';
import '../generate_qr/generate_qr_screen.dart';
import '../my_qr_codes/my_qr_codes_screen.dart';
import '../sales/sales_team_screen.dart';
import '../settings/settings_screen.dart';
import '../shops/shops_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final current = context.watch<NavigationProvider>().current;

    final body = IndexedStack(
      index: current.index,
      children: const [
        GenerateQrScreen(),
        MyQrCodesScreen(),
        ShopsScreen(),
        AnalyticsScreen(),
        SalesTeamScreen(),
        SettingsScreen(),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 900;

        return Scaffold(
          backgroundColor: AppColors.scaffoldBackground,
          drawer: isCompact ? const Drawer(width: 248, child: Sidebar()) : null,
          body: Row(
            children: [
              if (!isCompact) const Sidebar(),
              Expanded(
                child: Builder(
                  builder: (context) => Column(
                    children: [
                      TopBar(
                        onMenuTap: isCompact
                            ? () => Scaffold.of(context).openDrawer()
                            : null,
                      ),
                      Expanded(child: body),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

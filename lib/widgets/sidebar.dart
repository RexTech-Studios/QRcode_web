import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/navigation_provider.dart';
import '../services/auth_service.dart';
import '../utils/app_colors.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationProvider>();
    final scaffold = Scaffold.maybeOf(context);
    void goTo(DashboardTab tab) {
      nav.goTo(tab);
      if (scaffold?.isDrawerOpen ?? false) scaffold!.closeDrawer();
    }

    return Container(
      width: 248,
      decoration: const BoxDecoration(
        color: AppColors.sidebarBackground,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.chat_bubble,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Flexible(
                          child: Text(
                            'Full Star QR',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Column(
                      children: [
                        _NavItem(
                          icon: Icons.grid_view_rounded,
                          label: 'Generate QR',
                          selected: nav.current == DashboardTab.generateQr,
                          onTap: () => goTo(DashboardTab.generateQr),
                        ),
                        _NavItem(
                          icon: Icons.apps_rounded,
                          label: 'My QR Codes',
                          selected: nav.current == DashboardTab.myQrCodes,
                          onTap: () => goTo(DashboardTab.myQrCodes),
                        ),
                        _NavItem(
                          icon: Icons.storefront_rounded,
                          label: 'Shops',
                          selected: nav.current == DashboardTab.shops,
                          onTap: () => goTo(DashboardTab.shops),
                        ),
                        _NavItem(
                          icon: Icons.bar_chart_rounded,
                          label: 'Analytics',
                          selected: nav.current == DashboardTab.analytics,
                          onTap: () => goTo(DashboardTab.analytics),
                        ),
                        _NavItem(
                          icon: Icons.groups_rounded,
                          label: 'Sales Team',
                          selected: nav.current == DashboardTab.salesTeam,
                          onTap: () => goTo(DashboardTab.salesTeam),
                        ),
                        _NavItem(
                          icon: Icons.settings_rounded,
                          label: 'Settings',
                          selected: nav.current == DashboardTab.settings,
                          onTap: () => goTo(DashboardTab.settings),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                    child: _NavItem(
                      icon: Icons.logout_rounded,
                      label: 'Logout',
                      selected: false,
                      onTap: () {
                        if (scaffold?.isDrawerOpen ?? false) {
                          scaffold!.closeDrawer();
                        }
                        AuthService.signOut();
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: _LocalStorageCard(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryLight : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? AppColors.primary : AppColors.iconMuted,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? AppColors.primaryDark
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LocalStorageCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.scaffoldBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.purpleAccentBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.layers_rounded,
                  color: AppColors.purpleAccent,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Local Storage',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: const [
              Text(
                'Hive (Enabled)',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              SizedBox(width: 4),
              Icon(Icons.check_circle, size: 14, color: AppColors.primary),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Fast offline storage for shops and QR codes',
            style: TextStyle(
              fontSize: 11.5,
              color: AppColors.textSecondary,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

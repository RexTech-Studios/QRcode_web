import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/navigation_provider.dart';
import '../../providers/qr_provider.dart';
import '../../providers/shop_provider.dart';
import '../../services/export_service.dart';
import '../../services/firebase_service.dart';
import '../../utils/app_colors.dart';
import '../../widgets/section_card.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final shops = context.watch<ShopProvider>().shops;
    final qrCodes = context.watch<QrProvider>().qrCodes;
    final isCompact = MediaQuery.sizeOf(context).width < 600;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isCompact ? 16 : 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Settings',
            style: TextStyle(
              fontSize: isCompact ? 21 : 26,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Manage your data, exports, and preferences.',
            style: TextStyle(fontSize: 14.5, color: AppColors.textSecondary),
          ),
          SizedBox(height: isCompact ? 20 : 28),

          // ── Stats row ────────────────────────────────────────────────────
          _SectionLabel('Overview'),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 560;
              final cards = [
                _StatCard(
                  icon: Icons.storefront_rounded,
                  iconBg: AppColors.primarySoft,
                  iconColor: AppColors.primary,
                  label: 'Total Shops',
                  value: '${shops.length}',
                  onTap: () => context
                      .read<NavigationProvider>()
                      .goTo(DashboardTab.shops),
                ),
                _StatCard(
                  icon: Icons.apps_rounded,
                  iconBg: AppColors.purpleAccentBg,
                  iconColor: AppColors.purpleAccent,
                  label: 'Total QR Codes',
                  value: '${qrCodes.length}',
                  onTap: () => context
                      .read<NavigationProvider>()
                      .goTo(DashboardTab.myQrCodes),
                ),
              ];
              if (wide) {
                return Row(
                  children: [
                    Expanded(child: cards[0]),
                    const SizedBox(width: 14),
                    Expanded(child: cards[1]),
                  ],
                );
              }
              return Column(
                children: [cards[0], const SizedBox(height: 12), cards[1]],
              );
            },
          ),
          const SizedBox(height: 28),

          // ── Export data ──────────────────────────────────────────────────
          _SectionLabel('Export Data'),
          const SizedBox(height: 12),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Download all your shops and QR code data.',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth > 480;
                    final exportJson = _ExportButton(
                      icon: Icons.download_rounded,
                      label: 'Export as JSON',
                      subtitle: 'Machine-readable data backup',
                      onTap: () => ExportService.downloadJson(
                        shops: shops,
                        qrCodes: qrCodes,
                      ),
                    );
                    final exportPdf = _ExportButton(
                      icon: Icons.picture_as_pdf_rounded,
                      label: 'Export as PDF',
                      subtitle: 'Printable summary report',
                      onTap: () => ExportService.downloadPdf(
                        shops: shops,
                        qrCodes: qrCodes,
                      ),
                    );
                    if (wide) {
                      return Row(
                        children: [
                          Expanded(child: exportJson),
                          const SizedBox(width: 12),
                          Expanded(child: exportPdf),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        exportJson,
                        const SizedBox(height: 10),
                        exportPdf,
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── Analytics shortcut ───────────────────────────────────────────
          _SectionLabel('Analytics'),
          const SizedBox(height: 12),
          SectionCard(
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.amberAccentBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.bar_chart_rounded,
                    color: AppColors.amberAccent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'View Analytics',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Review scan counts, feedback trends, and shop performance.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () => context
                      .read<NavigationProvider>()
                      .goTo(DashboardTab.analytics),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── Storage info ─────────────────────────────────────────────────
          _SectionLabel('Storage'),
          const SizedBox(height: 12),
          SectionCard(
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.purpleAccentBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.layers_rounded,
                    color: AppColors.purpleAccent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Local Storage (Hive)',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Data is saved locally with Hive and synced to Firebase.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        Icons.check_circle,
                        size: 14,
                        color: AppColors.primary,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'Active',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── Maintenance ──────────────────────────────────────────────────
          _SectionLabel('Maintenance'),
          const SizedBox(height: 12),
          const _LegacyFieldsCard(),
        ],
      ),
    );
  }
}

/// One-off manual cleanup of contact fields left on shop docs by the removed
/// email feature. Runs only when pressed and confirmed, never automatically.
class _LegacyFieldsCard extends StatefulWidget {
  const _LegacyFieldsCard();

  @override
  State<_LegacyFieldsCard> createState() => _LegacyFieldsCardState();
}

class _LegacyFieldsCardState extends State<_LegacyFieldsCard> {
  bool _busy = false;

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      final shopIds = await FirebaseService.fetchShopIdsWithLegacyFields();
      if (!mounted) return;
      if (shopIds == null) {
        _showMessage('Could not check the shops. Check your connection and try again.');
        return;
      }
      if (shopIds.isEmpty) {
        _showMessage('Nothing to remove. No shop has these fields.');
        return;
      }

      final confirmed = await _confirm(shopIds.length);
      if (confirmed != true || !mounted) return;

      final cleaned = await FirebaseService.removeLegacyContactFields(shopIds);
      if (!mounted) return;
      _showMessage(
        cleaned == shopIds.length
            ? 'Removed legacy contact fields from $cleaned shop(s).'
            : 'Only $cleaned of ${shopIds.length} shop(s) were cleaned. Press the button again to finish.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirm(int count) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Remove legacy contact fields?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          '$count shop document(s) will change. This permanently deletes '
          '${FirebaseService.legacyContactFields.join(', ')} from them and '
          'touches nothing else. It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: Text('Remove from $count shop(s)'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Remove legacy contact fields',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            'Deletes old email and WhatsApp fields from shop records. Shows how many shops will change before anything happens.',
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: _busy ? null : _start,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: Text(_busy ? 'Working...' : 'Remove legacy contact fields'),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _StatCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = SectionCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null)
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.iconMuted,
              size: 22,
            ),
        ],
      ),
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: card,
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _ExportButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        alignment: Alignment.centerLeft,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

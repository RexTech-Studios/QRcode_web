import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/qr_provider.dart';
import '../providers/shop_provider.dart';
import '../services/export_service.dart';
import '../utils/app_colors.dart';

class TopBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback? onMenuTap;

  const TopBar({super.key, this.onMenuTap});

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: preferredSize.height,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (onMenuTap != null)
            IconButton(
              onPressed: onMenuTap,
              icon: const Icon(Icons.menu_rounded, color: AppColors.textPrimary),
            ),
          const Spacer(),
          _ExportButton(),
        ],
      ),
    );
  }
}

class _ExportButton extends StatefulWidget {
  @override
  State<_ExportButton> createState() => _ExportButtonState();
}

class _ExportButtonState extends State<_ExportButton> {
  bool _loading = false;

  Future<void> _export(String format) async {
    final shops = context.read<ShopProvider>().shops.toList();
    final qrCodes = context.read<QrProvider>().qrCodes.toList();

    setState(() => _loading = true);
    try {
      if (format == 'json') {
        ExportService.downloadJson(shops: shops, qrCodes: qrCodes);
      } else {
        await ExportService.downloadPdf(shops: shops, qrCodes: qrCodes);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.data_object_rounded, size: 18),
          onPressed: _loading ? null : () => _export('json'),
          child: const Text('Download as JSON'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
          onPressed: _loading ? null : () => _export('pdf'),
          child: const Text('Download as PDF'),
        ),
      ],
      builder: (context, controller, _) => FilledButton.icon(
        onPressed: _loading
            ? null
            : () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
        icon: _loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.download_rounded, size: 18),
        label: const Text('Export Data'),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

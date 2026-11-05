import 'package:flutter/material.dart';

import '../../utils/app_colors.dart';

/// Shown for a malformed `/review/...` link, so a damaged or mistyped QR URL
/// never lands a customer on the admin login.
class LinkNotFoundScreen extends StatelessWidget {
  const LinkNotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.link_off_rounded, color: AppColors.iconMuted, size: 44),
                SizedBox(height: 16),
                Text(
                  'Link not found',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Please scan the QR code again, or ask the business for a new one.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

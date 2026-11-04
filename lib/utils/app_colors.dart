import 'package:flutter/material.dart';

/// Central color palette for the ReviewQR admin dashboard.
/// Keep this the single source of truth for the green/white theme.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF1C8A3E);
  static const Color primaryDark = Color(0xFF136B2E);
  static const Color primaryLight = Color(0xFFE6F6EA);
  static const Color primarySoft = Color(0xFFEFFBF2);

  static const Color scaffoldBackground = Color(0xFFF7F9FA);
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color sidebarBackground = Color(0xFFFFFFFF);

  static const Color textPrimary = Color(0xFF14181F);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textMuted = Color(0xFF9CA3AF);

  static const Color border = Color(0xFFE5E7EB);
  static const Color borderFocused = primary;

  static const Color iconMuted = Color(0xFF9AA2AE);

  static const Color purpleAccent = Color(0xFF8B5CF6);
  static const Color purpleAccentBg = Color(0xFFF3EEFF);

  static const Color amberAccent = Color(0xFFF5B301);
  static const Color amberAccentBg = Color(0xFFFFF8E6);

  static const Color danger = Color(0xFFE23D3D);

  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x0A0F172A),
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
  ];
}

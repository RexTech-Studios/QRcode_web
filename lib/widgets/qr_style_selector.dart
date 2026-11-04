import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/qr_code_model.dart';
import '../utils/app_colors.dart';

class QrStyleConfig {
  final QrEyeShape eyeShape;
  final QrDataModuleShape dataShape;
  final Color color;

  const QrStyleConfig({
    required this.eyeShape,
    required this.dataShape,
    required this.color,
  });
}

const Map<QRStyle, QrStyleConfig> qrStyleConfigs = {
  QRStyle.classic: QrStyleConfig(
    eyeShape: QrEyeShape.square,
    dataShape: QrDataModuleShape.square,
    color: Color(0xFF14181F),
  ),
  QRStyle.rounded: QrStyleConfig(
    eyeShape: QrEyeShape.circle,
    dataShape: QrDataModuleShape.circle,
    color: Color(0xFF14181F),
  ),
  QRStyle.dotsGreen: QrStyleConfig(
    eyeShape: QrEyeShape.circle,
    dataShape: QrDataModuleShape.circle,
    color: AppColors.primary,
  ),
  QRStyle.minimal: QrStyleConfig(
    eyeShape: QrEyeShape.square,
    dataShape: QrDataModuleShape.square,
    color: Color(0xFF6B7280),
  ),
};

class QrStyleSelector extends StatelessWidget {
  final QRStyle selected;
  final ValueChanged<QRStyle> onChanged;

  const QrStyleSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: QRStyle.values.map((style) {
        final isSelected = style == selected;
        final config = qrStyleConfigs[style]!;
        return Padding(
          padding: EdgeInsets.zero,
          child: GestureDetector(
            onTap: () => onChanged(style),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.border,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: IgnorePointer(
                    child: QrImageView(
                      data: 'https://reviewqr.app/preview',
                      version: QrVersions.auto,
                      padding: EdgeInsets.zero,
                      eyeStyle: QrEyeStyle(
                        eyeShape: config.eyeShape,
                        color: config.color,
                      ),
                      dataModuleStyle: QrDataModuleStyle(
                        dataModuleShape: config.dataShape,
                        color: config.color,
                      ),
                    ),
                  ),
                ),
                if (isSelected)
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

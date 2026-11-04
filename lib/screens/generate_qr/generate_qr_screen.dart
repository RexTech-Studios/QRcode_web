import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/shop_model.dart';
import '../../providers/qr_provider.dart';
import '../../providers/shop_provider.dart';
import '../../services/download_helper.dart';
import '../../services/qr_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/validators.dart';
import '../../widgets/qr_style_selector.dart';
import '../../widgets/section_card.dart';

class GenerateQrScreen extends StatefulWidget {
  const GenerateQrScreen({super.key});

  @override
  State<GenerateQrScreen> createState() => _GenerateQrScreenState();
}

class _GenerateQrScreenState extends State<GenerateQrScreen> {
  final _shopNameController = TextEditingController();
  final _reviewUrlController = TextEditingController();
  final _labelController = TextEditingController(text: 'Review us on Google');

  final GlobalKey _qrBoundaryKey = GlobalKey();
  late String _draftShopId;
  bool _isSaving = false;

  bool _isSavingShop = false;
  bool? _lastSaveSucceeded;
  String? _saveMessage;

  @override
  void initState() {
    super.initState();
    _draftShopId = QrService.newShopId();
    _shopNameController.addListener(_onFieldChanged);
    _reviewUrlController.addListener(_onFieldChanged);
    _labelController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    setState(() {
      _lastSaveSucceeded = null;
      _saveMessage = null;
    });
  }

  @override
  void dispose() {
    _shopNameController.removeListener(_onFieldChanged);
    _reviewUrlController.removeListener(_onFieldChanged);
    _labelController.removeListener(_onFieldChanged);
    _shopNameController.dispose();
    _reviewUrlController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  bool get _isUrlValid =>
      Validators.isValidGoogleMapsUrl(_reviewUrlController.text);
  bool get _canGenerate =>
      Validators.isNotEmpty(_shopNameController.text) && _isUrlValid;

  // saveShop reuses the ID of an existing shop with the same name, so the QR must too.
  String get _previewShopId {
    final name = _shopNameController.text.trim().toLowerCase();
    for (final s in context.watch<ShopProvider>().shops) {
      if (s.shopName.toLowerCase() == name) return s.shopId;
    }
    return _draftShopId;
  }

  String get _previewContent => QrService.buildReviewPageUrl(_previewShopId);

  Future<void> _handleSaveShop() async {
    if (_isSavingShop) return;

    if (!_canGenerate) {
      setState(() {
        _lastSaveSucceeded = false;
        _saveMessage = _shopNameController.text.trim().isEmpty
            ? 'Enter a shop name before saving.'
            : 'Enter a valid Google Maps review link before saving.';
      });
      return;
    }
    setState(() => _isSavingShop = true);
    try {
      final shopProvider = context.read<ShopProvider>();
      final qrProvider = context.read<QrProvider>();
      final shop = await shopProvider.saveShop(
        shopName: _shopNameController.text,
        googleReviewUrl: _reviewUrlController.text,
        preferredShopId: _draftShopId,
      );

      // Create a QR record so the shop shows up on the My QR Codes page,
      // but only if one doesn't already exist for this shop.
      if (qrProvider.qrCodesForShop(shop.shopId).isEmpty) {
        await qrProvider.generateAndSaveQr(
          shopId: shop.shopId,
          qrLabel: _labelController.text,
          style: qrProvider.selectedStyle,
        );
      }

      if (!mounted) return;
      final sheetWarning = shopProvider.lastSheetWarning;
      setState(() {
        _lastSaveSucceeded = sheetWarning == null;
        _saveMessage = sheetWarning == null
            ? 'Saved! "${shop.shopName}" and its review link are stored and ready to use.'
            : 'Shop saved, but its Google Sheet could not be created. $sheetWarning';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lastSaveSucceeded = false;
        _saveMessage =
            "Could not upload this shop. Check your internet connection and try again — the QR code won't work until it's saved.";
      });
    } finally {
      if (mounted) setState(() => _isSavingShop = false);
    }
  }

  Future<void> _handleDownload() async {
    if (!_canGenerate || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      final shopProvider = context.read<ShopProvider>();
      final qrProvider = context.read<QrProvider>();

      // saveShop may throw if Firebase cloud sync fails, but the shop is still
      // saved to Hive locally. Capture the shop from selectedShop so we can
      // still generate the QR code even when cloud sync fails.
      ShopModel? shop;
      bool cloudSyncFailed = false;
      try {
        shop = await shopProvider.saveShop(
          shopName: _shopNameController.text,
          googleReviewUrl: _reviewUrlController.text,
          preferredShopId: _draftShopId,
        );
      } on StateError {
        cloudSyncFailed = true;
        shop = shopProvider.selectedShop;
      }

      if (shop == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not save the shop. Try again.'),
            ),
          );
        }
        return;
      }

      try {
        await qrProvider.generateAndSaveQr(
          shopId: shop.shopId,
          qrLabel: _labelController.text,
          style: qrProvider.selectedStyle,
        );
      } on StateError {
        cloudSyncFailed = true;
      }

      await _downloadPng(shop.shopName);

      if (mounted) {
        if (cloudSyncFailed) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'QR code saved locally and downloaded. Cloud sync failed — check your connection.',
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('QR code saved and downloaded.'),
              backgroundColor: AppColors.primary,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not generate the QR code. Check your connection and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _downloadPng(String shopName) async {
    final boundary =
        _qrBoundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 3);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;
    final bytes = byteData.buffer.asUint8List();
    final safeName = shopName.trim().isEmpty
        ? 'reviewqr'
        : shopName.trim().replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
    downloadBytes(bytes, '${safeName}_qr_code.png');
  }

  Future<void> _handleShare() async {
    if (!_canGenerate) return;
    // The link only works once the shop is in Firestore, so save it first.
    final ShopModel shop;
    try {
      shop = await context.read<ShopProvider>().saveShop(
        shopName: _shopNameController.text,
        googleReviewUrl: _reviewUrlController.text,
        preferredShopId: _draftShopId,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not upload this shop, so the link would not work yet. Check your connection and try again.',
            ),
          ),
        );
      }
      return;
    }
    await Clipboard.setData(
      ClipboardData(text: QrService.buildReviewPageUrl(shop.shopId)),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Review link copied to clipboard.'),
          backgroundColor: AppColors.primary,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final qrProvider = context.watch<QrProvider>();

    return LayoutBuilder(
      builder: (context, outerConstraints) {
        final isCompact = outerConstraints.maxWidth < 600;
        final isWide = outerConstraints.maxWidth > 960;

        return SingleChildScrollView(
          padding: EdgeInsets.all(isCompact ? 16 : 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Generate Review QR Code',
                style: TextStyle(
                  fontSize: isCompact ? 21 : 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Create a QR code from your Google Maps review link and share it with customers.',
                style: TextStyle(
                  fontSize: 14.5,
                  color: AppColors.textSecondary,
                ),
              ),
              SizedBox(height: isCompact ? 18 : 24),
              Builder(
                builder: (context) {
                  final formCard = _buildFormCard(qrProvider);
                  final previewCard = _buildPreviewCard(qrProvider);
                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: formCard),
                        const SizedBox(width: 24),
                        Expanded(flex: 2, child: previewCard),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      formCard,
                      const SizedBox(height: 24),
                      previewCard,
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFormCard(QrProvider qrProvider) {
    final urlHasText = _reviewUrlController.text.isNotEmpty;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StepHeader(number: '1', title: 'Enter Google Maps Review Link'),
          const SizedBox(height: 20),
          const FieldLabel('Shop Name'),
          TextField(
            controller: _shopNameController,
            decoration: const InputDecoration(
              hintText: 'e.g. Rextech Cafe',
              prefixIcon: Icon(Icons.storefront_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 18),
          const FieldLabel('Google Maps Review Link'),
          TextField(
            controller: _reviewUrlController,
            decoration: InputDecoration(
              hintText: 'https://g.page/r/xxxxxxx/review',
              prefixIcon: const Icon(Icons.link_rounded, size: 20),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: !urlHasText
                      ? AppColors.border
                      : (_isUrlValid ? AppColors.primary : AppColors.danger),
                  width: !urlHasText ? 1 : 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            urlHasText && !_isUrlValid
                ? 'Enter a valid Google Maps review link'
                : 'Paste the "Write a review" link from your Google Maps business.',
            style: TextStyle(
              fontSize: 12.5,
              color: urlHasText && !_isUrlValid
                  ? AppColors.danger
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          const _GoogleFormInfoCard(),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _isSavingShop ? null : _handleSaveShop,
              icon: _isSavingShop
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  : const Icon(Icons.save_outlined, size: 17),
              label: Text(_isSavingShop ? 'Saving...' : 'Save Shop Link'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                textStyle: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
                foregroundColor: AppColors.primary,
                backgroundColor: Colors.white,
                side: const BorderSide(color: AppColors.primary),
              ),
            ),
          ),
          if (_saveMessage != null) ...[
            const SizedBox(height: 12),
            _SaveStatusBanner(
              success: _lastSaveSucceeded == true,
              message: _saveMessage!,
            ),
          ],
          const SizedBox(height: 18),
          const _InfoBox(),
          const SizedBox(height: 28),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 24),
          const StepHeader(number: '2', title: 'Customize (Optional)'),
          const SizedBox(height: 20),
          const FieldLabel('QR Style'),
          QrStyleSelector(
            selected: qrProvider.selectedStyle,
            onChanged: qrProvider.selectStyle,
          ),
          const SizedBox(height: 20),
          const FieldLabel('Add a Label'),
          TextField(
            controller: _labelController,
            decoration: const InputDecoration(
              hintText: 'Review us on Google',
              prefixIcon: Icon(Icons.text_fields_rounded, size: 20),
            ),
          ),
          const SizedBox(height: 24),
          const _HiveSyncBar(),
        ],
      ),
    );
  }

  Widget _buildPreviewCard(QrProvider qrProvider) {
    final config = qrStyleConfigs[qrProvider.selectedStyle]!;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'QR Code Preview',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: RepaintBoundary(
              key: _qrBoundaryKey,
              child: Container(
                width: 240,
                height: 240,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                  boxShadow: AppColors.cardShadow,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    QrImageView(
                      data: _previewContent,
                      version: QrVersions.auto,
                      eyeStyle: QrEyeStyle(
                        eyeShape: config.eyeShape,
                        color: config.color,
                      ),
                      dataModuleStyle: QrDataModuleStyle(
                        dataModuleShape: config.dataShape,
                        color: config.color,
                      ),
                    ),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.location_on,
                        color: AppColors.primary,
                        size: 26,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.g_mobiledata_rounded,
                    color: Colors.blue,
                    size: 26,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _labelController.text.isEmpty
                        ? 'Review us on Google'
                        : _labelController.text,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _canGenerate && !_isSaving ? _handleDownload : null,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download_rounded, size: 18),
              label: Text(_isSaving ? 'Saving...' : 'Download QR Code'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _canGenerate ? _handleShare : null,
              icon: const Icon(Icons.share_rounded, size: 18),
              label: const Text('Share Link'),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoogleFormInfoCard extends StatelessWidget {
  const _GoogleFormInfoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.assignment_outlined,
              color: AppColors.primary,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Google Sheets Feedback',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Low ratings (1–3 stars) are automatically saved to this shop\'s Google Sheet tab with the shop name, date, time, and comment. Ratings of 4–5 stars redirect customers to Google Maps to leave a public review.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    height: 1.4,
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

class _SaveStatusBanner extends StatelessWidget {
  final bool success;
  final String message;

  const _SaveStatusBanner({required this.success, required this.message});

  @override
  Widget build(BuildContext context) {
    final color = success ? AppColors.primary : AppColors.danger;
    final bg = success ? AppColors.primarySoft : const Color(0xFFFDEDED);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            success ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: color,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(
                Icons.info_outline_rounded,
                color: AppColors.primary,
                size: 18,
              ),
              SizedBox(width: 8),
              Text(
                'How to get the review link?',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _step('1. Open your business on Google Maps.'),
          _step('2. Click on "Write a review".'),
          _step('3. Copy the link from your browser and paste here.'),
        ],
      ),
    );
  }

  Widget _step(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4, left: 26),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12.5,
        color: AppColors.textSecondary,
        height: 1.4,
      ),
    ),
  );
}

class _HiveSyncBar extends StatelessWidget {
  const _HiveSyncBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.scaffoldBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.purpleAccentBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.layers_rounded,
              color: AppColors.purpleAccent,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Using Hive (Local Database)',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'QR codes and shop data are saved locally with Hive and also synced to Firebase (Cloud).',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _pill(Icons.layers_rounded, 'Hive (Local Storage)'),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 14,
                      color: AppColors.textMuted,
                    ),
                    _pill(
                      Icons.local_fire_department_rounded,
                      'Firebase (Cloud Sync)',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.amberAccent),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/assignment_model.dart';
import '../../models/qr_code_model.dart';
import '../../models/shop_model.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/qr_provider.dart';
import '../../providers/sales_admin_provider.dart';
import '../../providers/shop_provider.dart';
import '../../services/download_helper.dart';
import '../../utils/app_colors.dart';
import '../../utils/validators.dart';
import '../../widgets/coming_soon_placeholder.dart';
import '../../widgets/qr_style_selector.dart';
import '../../widgets/section_card.dart';

class MyQrCodesScreen extends StatefulWidget {
  const MyQrCodesScreen({super.key});

  @override
  State<MyQrCodesScreen> createState() => _MyQrCodesScreenState();
}

class _MyQrCodesScreenState extends State<MyQrCodesScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Matches the QR number ("296" or "QR296"), the shop name or the label.
  /// Exact QR-number matches are listed first.
  List<QRCodeModel> _filter(
    List<QRCodeModel> qrCodes,
    Map<String, ShopModel> shopsById,
    SalesAdminProvider sales,
  ) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return qrCodes;
    final exactCode = RegExp(r'^\d+$').hasMatch(q) ? 'qr$q' : q;
    bool matches(QRCodeModel qr) {
      final shopName = shopsById[qr.shopId]?.shopName.toLowerCase() ?? '';
      final holder =
          sales.assignmentFor(qr.shopId)?.assignedToName.toLowerCase() ?? '';
      return qr.qrCode.toLowerCase().contains(q) ||
          shopName.contains(q) ||
          holder.contains(q) ||
          qr.qrLabel.toLowerCase().contains(q);
    }

    final results = qrCodes.where(matches).toList();
    results.sort((a, b) {
      final aExact = a.qrCode.toLowerCase() == exactCode ? 0 : 1;
      final bExact = b.qrCode.toLowerCase() == exactCode ? 0 : 1;
      return aExact.compareTo(bExact);
    });
    return results;
  }

  @override
  Widget build(BuildContext context) {
    final allQrCodes = context.watch<QrProvider>().qrCodes;
    final shops = context.watch<ShopProvider>().shops;
    final shopsById = {for (final s in shops) s.shopId: s};
    final sales = context.watch<SalesAdminProvider>();
    final qrCodes = _filter(allQrCodes, shopsById, sales);

    if (allQrCodes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ComingSoonPlaceholder(
              icon: Icons.apps_rounded,
              title: 'My QR Codes',
              subtitle: 'Your saved QR codes will be listed here next.',
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => context.read<NavigationProvider>().goTo(
                DashboardTab.generateQr,
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Generate a QR Code'),
            ),
          ],
        ),
      );
    }

    final isCompact = MediaQuery.sizeOf(context).width < 600;
    return SingleChildScrollView(
      padding: EdgeInsets.all(isCompact ? 16 : 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'My QR Codes',
            style: TextStyle(
              fontSize: isCompact ? 21 : 26,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _query.trim().isEmpty
                ? '${allQrCodes.length} saved QR code${allQrCodes.length == 1 ? '' : 's'}.'
                : '${qrCodes.length} of ${allQrCodes.length} QR codes match.',
            style: const TextStyle(
              fontSize: 14.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText:
                    'Search by QR number (e.g. QR296), shop name or label',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (qrCodes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  'No QR codes match your search.',
                  style: TextStyle(
                    fontSize: 15,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth > 1300
                    ? 4
                    : constraints.maxWidth > 980
                    ? 3
                    : constraints.maxWidth > 640
                    ? 2
                    : 1;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: qrCodes.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 20,
                    crossAxisSpacing: 20,
                    mainAxisExtent: 440,
                  ),
                  itemBuilder: (context, index) {
                    final qr = qrCodes[index];
                    return _QrCodeCard(
                      qr: qr,
                      shop: shopsById[qr.shopId],
                      assignment: sales.assignmentFor(qr.shopId),
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card
// ---------------------------------------------------------------------------

class _QrCodeCard extends StatelessWidget {
  final QRCodeModel qr;
  final ShopModel? shop;
  final Assignment? assignment;

  const _QrCodeCard({required this.qr, required this.shop, this.assignment});

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  Future<void> _openSheet(BuildContext context) async {
    final url = shop?.googleSheetsUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the Google Sheet.')),
        );
      }
    }
  }

  Future<void> _copyLink(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: qr.qrContent));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Review link copied to clipboard.'),
          backgroundColor: AppColors.primary,
        ),
      );
    }
  }

  /// Minimum output resolution (in pixels, per side) for downloaded QR PNGs,
  /// so codes stay crisp when enlarged or printed.
  static const double _minExportSize = 2048;

  Future<void> _downloadQr(BuildContext context, GlobalKey key) async {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    // Render at a pixel ratio high enough that the exported PNG is at least
    // _minExportSize on its shortest side, regardless of the on-screen
    // preview size, so the QR stays sharp when zoomed in or printed.
    final shortestSide = boundary.size.shortestSide;
    final pixelRatio = shortestSide > 0
        ? (_minExportSize / shortestSide).clamp(1.0, 32.0)
        : 8.0;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;
    final bytes = byteData.buffer.asUint8List();
    final safeName = (shop?.shopName ?? 'reviewqr').trim().replaceAll(
      RegExp(r'[^a-zA-Z0-9]+'),
      '_',
    );
    downloadBytes(bytes, '${safeName}_qr_code.png');
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete QR Code?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Are you sure you want to delete "${qr.qrLabel}"? This cannot be undone.',
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
            child: const Text('Delete QR Code'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await context.read<QrProvider>().deleteQrCode(qr.qrId);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('QR code deleted.')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not delete the QR code. Check your connection and try again.',
            ),
          ),
        );
      }
    }
  }

  void _openEditModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _EditQrModal(qr: qr, shop: shop),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = qrStyleConfigs[qr.qrStyle]!;
    final qrKey = GlobalKey();

    return SectionCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: RepaintBoundary(
              key: qrKey,
              child: Container(
                width: 120,
                height: 120,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: QrImageView(
                  data: qr.qrContent,
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
          ),
          const SizedBox(height: 14),
          if (qr.qrCode.isNotEmpty)
            Align(
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  qr.qrCode,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            shop?.shopName ?? 'Unknown shop',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            qr.qrLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Created ${_formatDate(qr.createdAt)}',
            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
          if (qr.updatedAt != null) ...[
            const SizedBox(height: 2),
            Text(
              'Updated ${_formatDate(qr.updatedAt!)}',
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textMuted,
              ),
            ),
          ],
          if (assignment != null) ...[
            const SizedBox(height: 4),
            Text(
              assignment!.isSold
                  ? 'Sold by ${assignment!.assignedToName} on ${_formatDate(assignment!.soldAt!)}'
                  : 'Assigned to ${assignment!.assignedToName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ],
          if (shop?.googleSheetsUrl != null &&
              shop!.googleSheetsUrl!.isNotEmpty) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () => _openSheet(context),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF81C784)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(
                      Icons.table_chart_outlined,
                      size: 14,
                      color: Color(0xFF2E7D32),
                    ),
                    SizedBox(width: 5),
                    Text(
                      'View Google Sheet',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else if (shop != null) ...[
            // Sheet creation failed when this shop was added — let the owner
            // generate it on demand instead of leaving the card without a link.
            const SizedBox(height: 10),
            _GenerateSheetButton(shop: shop!),
          ],
          const Spacer(),
          // Primary action: Edit QR
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openEditModal(context),
              icon: const Icon(Icons.edit_rounded, size: 15),
              label: const Text('Edit QR'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                textStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Secondary actions row: Copy Link, Download QR, Delete
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copyLink(context),
                  icon: const Icon(Icons.link_rounded, size: 14),
                  label: const Text('Copy Link'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    textStyle: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _downloadQr(context, qrKey),
                  icon: const Icon(Icons.download_rounded, size: 14),
                  label: const Text('Download'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    textStyle: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: () => _confirmDelete(context),
                icon: const Icon(Icons.delete_outline_rounded, size: 19),
                color: AppColors.danger,
                tooltip: 'Delete',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Generate-sheet button (for shops whose sheet failed to create at add time)
// ---------------------------------------------------------------------------

class _GenerateSheetButton extends StatefulWidget {
  final ShopModel shop;

  const _GenerateSheetButton({required this.shop});

  @override
  State<_GenerateSheetButton> createState() => _GenerateSheetButtonState();
}

class _GenerateSheetButtonState extends State<_GenerateSheetButton> {
  bool _busy = false;

  Future<void> _generate() async {
    setState(() => _busy = true);
    final provider = context.read<ShopProvider>();
    final result = await provider.ensureSheetForShop(widget.shop);
    if (!mounted) return;
    setState(() => _busy = false);

    final messenger = ScaffoldMessenger.of(context);
    if (result != null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Google Sheet created for this shop.'),
          backgroundColor: AppColors.primary,
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            provider.lastSheetWarning ??
                'Could not create the Google Sheet. Please try again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _busy ? null : _generate,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFFFB74D)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_busy)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFE65100),
                ),
              )
            else
              const Icon(
                Icons.add_chart_outlined,
                size: 14,
                color: Color(0xFFE65100),
              ),
            const SizedBox(width: 5),
            Text(
              _busy ? 'Generating...' : 'Generate Sheet',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFFE65100),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Edit modal
// ---------------------------------------------------------------------------

class _EditQrModal extends StatefulWidget {
  final QRCodeModel qr;
  final ShopModel? shop;

  const _EditQrModal({required this.qr, required this.shop});

  @override
  State<_EditQrModal> createState() => _EditQrModalState();
}

class _EditQrModalState extends State<_EditQrModal> {
  late final TextEditingController _shopNameCtrl;
  late final TextEditingController _reviewUrlCtrl;
  late final TextEditingController _labelCtrl;
  late final TextEditingController _sheetsUrlCtrl;
  late QRStyle _selectedStyle;

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _shopNameCtrl = TextEditingController(text: widget.shop?.shopName ?? '');
    _reviewUrlCtrl = TextEditingController(
      text: widget.shop?.googleReviewUrl ?? '',
    );
    _labelCtrl = TextEditingController(text: widget.qr.qrLabel);
    _sheetsUrlCtrl = TextEditingController(
      text: widget.shop?.googleSheetsUrl ?? '',
    );
    _selectedStyle = widget.qr.qrStyle;
  }

  @override
  void dispose() {
    _shopNameCtrl.dispose();
    _reviewUrlCtrl.dispose();
    _labelCtrl.dispose();
    _sheetsUrlCtrl.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_shopNameCtrl.text.trim().isEmpty) return 'Shop name is required.';
    if (!Validators.isValidGoogleMapsUrl(_reviewUrlCtrl.text)) {
      return 'Enter a valid Google Maps review link.';
    }
    if (_labelCtrl.text.trim().isEmpty) return 'QR label is required.';
    return null;
  }

  Future<void> _saveChanges() async {
    final error = _validate();
    if (error != null) {
      setState(() => _errorMessage = error);
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final shopProvider = context.read<ShopProvider>();
      final qrProvider = context.read<QrProvider>();

      await shopProvider.saveShop(
        shopName: _shopNameCtrl.text,
        googleReviewUrl: _reviewUrlCtrl.text,
        preferredShopId: widget.shop?.shopId,
        editingShopId: widget.shop?.shopId,
        googleSheetsUrl: _sheetsUrlCtrl.text.trim().isEmpty
            ? null
            : _sheetsUrlCtrl.text.trim(),
      );

      // Update the QR record (same qrId, same shopId — no duplicate).
      final updatedQr = QRCodeModel(
        qrId: widget.qr.qrId,
        shopId: widget.qr.shopId,
        qrContent: widget.qr.qrContent,
        qrLabel: _labelCtrl.text.trim(),
        qrStyle: _selectedStyle,
        createdAt: widget.qr.createdAt,
        updatedAt: DateTime.now(),
        qrCode: widget.qr.qrCode,
      );

      await qrProvider.updateQrCode(updatedQr);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              shopProvider.lastSheetWarning ?? 'QR Code updated successfully.',
            ),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage =
              'Could not save changes. Check your connection and try again.';
        });
      }
    }
  }

  bool get _isUrlValid => Validators.isValidGoogleMapsUrl(_reviewUrlCtrl.text);

  @override
  Widget build(BuildContext context) {
    final config = qrStyleConfigs[_selectedStyle]!;
    final urlHasText = _reviewUrlCtrl.text.isNotEmpty;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.qr.qrCode.isEmpty
                          ? 'Edit QR Code'
                          : 'Edit QR Code · ${widget.qr.qrCode}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Live QR preview
              Center(
                child: Container(
                  width: 130,
                  height: 130,
                  padding: const EdgeInsets.all(12),
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
                        data: widget.qr.qrContent,
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
                      Container(
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.location_on,
                          color: AppColors.primary,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Label pill under preview
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.g_mobiledata_rounded,
                        color: Colors.blue,
                        size: 22,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _labelCtrl.text.isEmpty
                            ? 'Review us on Google'
                            : _labelCtrl.text,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Shop / Business Name
              const FieldLabel('Shop / Business Name'),
              TextField(
                controller: _shopNameCtrl,
                decoration: const InputDecoration(
                  hintText: 'e.g. The Coffee House',
                  prefixIcon: Icon(Icons.storefront_outlined, size: 20),
                ),
              ),
              const SizedBox(height: 18),

              // Google Maps Review Link
              const FieldLabel('Google Maps Review Link'),
              TextField(
                controller: _reviewUrlCtrl,
                keyboardType: TextInputType.url,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'https://g.page/r/xxxxxxx/review',
                  prefixIcon: const Icon(Icons.link_rounded, size: 20),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: !urlHasText
                          ? AppColors.border
                          : (_isUrlValid
                                ? AppColors.primary
                                : AppColors.danger),
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
              const SizedBox(height: 18),

              // QR Code Style
              const FieldLabel('QR Style'),
              QrStyleSelector(
                selected: _selectedStyle,
                onChanged: (s) => setState(() => _selectedStyle = s),
              ),
              const SizedBox(height: 18),

              // Custom QR Label
              const FieldLabel('Add a Label'),
              TextField(
                controller: _labelCtrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'e.g. Review us on Google',
                  prefixIcon: Icon(Icons.text_fields_rounded, size: 20),
                ),
              ),
              const SizedBox(height: 18),

              // Google Sheets URL
              const FieldLabel('Google Sheet Link (optional)'),
              TextField(
                controller: _sheetsUrlCtrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  hintText: 'https://docs.google.com/spreadsheets/d/...',
                  prefixIcon: Icon(Icons.table_chart_outlined, size: 20),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Paste the link to this shop\'s Google Sheet. A "View Google Sheet" button will appear on the QR card.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),

              // Google Form feedback info card
              Container(
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
                            'Low ratings (1–3 stars) are automatically saved to this shop\'s Google Sheet tab. Check the sheet to view negative feedback.',
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
              ),

              // Error message
              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDEDED),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 18,
                        color: AppColors.danger,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.danger,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveChanges,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_rounded, size: 18),
                  label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/foundation.dart';
import '../models/qr_code_model.dart';
import '../services/hive_service.dart';
import '../services/firebase_service.dart';
import '../services/qr_service.dart';

class QrProvider extends ChangeNotifier {
  List<QRCodeModel> _qrCodes = [];
  QRStyle selectedStyle = QRStyle.classic;

  List<QRCodeModel> get qrCodes => List.unmodifiable(_qrCodes);

  void _loadFromHive() {
    _qrCodes = HiveService.getAllQrCodes()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
  }

  /// Primary load: fetch from Firestore and mirror to Hive.
  /// Falls back to Hive if Firestore is unavailable or fails.
  /// Returns true if the list came from Firestore.
  Future<bool> loadQrCodes() async {
    final remote = await FirebaseService.fetchAllQrCodes();
    if (remote != null) {
      await HiveService.replaceQrCodes(remote);
    }
    _loadFromHive();
    return remote != null;
  }

  /// Forgets everything in memory, on sign-out.
  void reset() {
    _qrCodes = [];
    selectedStyle = QRStyle.classic;
    notifyListeners();
  }

  void selectStyle(QRStyle style) {
    selectedStyle = style;
    notifyListeners();
  }

  List<QRCodeModel> qrCodesForShop(String shopId) =>
      _qrCodes.where((q) => q.shopId == shopId).toList();

  /// The next sequential short code ("QR1", "QR2", ...) that would be
  /// assigned to a newly generated QR, based on the highest number already
  /// in use. Exposed so the UI can preview it before saving.
  String get nextQrCode {
    var highest = 0;
    for (final qr in _qrCodes) {
      final match = RegExp(r'^QR(\d+)$').firstMatch(qr.qrCode);
      if (match != null) {
        final n = int.tryParse(match.group(1)!) ?? 0;
        if (n > highest) highest = n;
      }
    }
    return 'QR${highest + 1}';
  }

  /// Builds the review-page URL for [shopId], saves a new QR record to
  /// Hive and Firestore, and returns it.
  Future<QRCodeModel> generateAndSaveQr({
    required String shopId,
    required String qrLabel,
    QRStyle? style,
  }) async {
    final content = QrService.buildReviewPageUrl(shopId);
    final qr = QRCodeModel(
      qrId: QrService.newQrId(),
      shopId: shopId,
      qrContent: content,
      qrLabel: qrLabel.trim().isEmpty ? 'Review us on Google' : qrLabel.trim(),
      qrStyle: style ?? selectedStyle,
      createdAt: DateTime.now(),
      qrCode: nextQrCode,
    );

    // Firebase is primary: write there first, mirror to Hive regardless.
    final synced = await FirebaseService.upsertQrCode(qr);
    await HiveService.saveQrCode(qr);
    await _copyQrCodeToShop(qr);

    // Use _loadFromHive directly so the record we just wrote to Hive is
    // immediately visible. loadQrCodes() would re-fetch from Firebase and could
    // overwrite Hive with a list that doesn't yet include this new record.
    _loadFromHive();
    if (!synced) {
      throw StateError(
        'QR code saved to local backup only — cloud sync failed.',
      );
    }
    return qr;
  }

  /// Updates an existing QR record. Firebase is primary; Hive is always updated as backup.
  Future<void> updateQrCode(QRCodeModel qr) async {
    final synced = await FirebaseService.upsertQrCode(qr);
    await HiveService.saveQrCode(qr);
    await _copyQrCodeToShop(qr);
    _loadFromHive();
    if (!synced) {
      throw StateError(
        'QR code updated in local backup only — cloud sync failed.',
      );
    }
  }

  /// Mirrors the short code onto the shop for the public review page. It only
  /// labels sheet rows, so a failure here must not fail the QR save, and the
  /// backfill after the next login picks up anything missed.
  Future<void> _copyQrCodeToShop(QRCodeModel qr) async {
    if (qr.qrCode.isEmpty) return;
    final shop = HiveService.getShop(qr.shopId);
    if (shop != null) {
      shop.qrCode = qr.qrCode;
      await HiveService.saveShop(shop);
    }
    await FirebaseService.setShopQrCode(qr.shopId, qr.qrCode);
  }

  /// Deletes from Firestore first, then removes from local Hive backup.
  /// If Firestore delete fails, Hive is left intact so the record isn't lost.
  Future<void> deleteQrCode(String qrId) async {
    final deleted = await FirebaseService.deleteQrCode(qrId);
    if (!deleted) {
      throw StateError('Could not delete the QR code from the cloud.');
    }
    await HiveService.deleteQrCode(qrId);
    await loadQrCodes();
  }
}

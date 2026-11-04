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
  Future<void> loadQrCodes() async {
    final remote = await FirebaseService.fetchAllQrCodes();
    if (remote != null) {
      await HiveService.replaceQrCodes(remote);
    }
    _loadFromHive();
  }

  /// Alias kept for call-sites that still call syncFromCloud.
  Future<void> syncFromCloud() => loadQrCodes();

  void selectStyle(QRStyle style) {
    selectedStyle = style;
    notifyListeners();
  }

  List<QRCodeModel> qrCodesForShop(String shopId) =>
      _qrCodes.where((q) => q.shopId == shopId).toList();

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
    );

    // Firebase is primary: write there first, mirror to Hive regardless.
    final synced = await FirebaseService.upsertQrCode(qr);
    await HiveService.saveQrCode(qr);

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
    _loadFromHive();
    if (!synced) {
      throw StateError(
        'QR code updated in local backup only — cloud sync failed.',
      );
    }
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

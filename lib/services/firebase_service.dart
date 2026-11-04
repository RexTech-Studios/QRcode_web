import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../firebase_options.dart';
import '../models/shop_model.dart';
import '../models/qr_code_model.dart';

/// Wraps Firestore access. Designed to fail soft: if Firebase has not been
/// configured with real project credentials yet (see firebase_options.dart),
/// [isAvailable] stays false and every method becomes a no-op, so the app
/// keeps working entirely off Hive until cloud sync is wired up.
class FirebaseService {
  FirebaseService._();

  static bool isAvailable = false;

  static Future<void> init() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      isAvailable = true;
    } catch (e) {
      isAvailable = false;
      debugPrint(
        'FirebaseService: cloud sync disabled (no valid Firebase project configured). $e',
      );
    }
  }

  static CollectionReference<Map<String, dynamic>> get _shopsCollection =>
      FirebaseFirestore.instance.collection('shops');

  static CollectionReference<Map<String, dynamic>> get _qrCodesCollection =>
      FirebaseFirestore.instance.collection('qr_codes');

  static CollectionReference<Map<String, dynamic>> get _feedbackCollection =>
      FirebaseFirestore.instance.collection('feedback');

  /// Returns false if the write failed. The public review page reads shops
  /// from Firestore, so callers must not treat a failed write as saved.
  static Future<bool> upsertShop(ShopModel shop) async {
    if (!isAvailable) return false;
    try {
      await _shopsCollection.doc(shop.shopId).set(shop.toMap());
      return true;
    } catch (e) {
      debugPrint('FirebaseService.upsertShop failed: $e');
      return false;
    }
  }

  static Future<bool> upsertQrCode(QRCodeModel qr) async {
    if (!isAvailable) return false;
    try {
      await _qrCodesCollection.doc(qr.qrId).set(qr.toMap());
      return true;
    } catch (e) {
      debugPrint('FirebaseService.upsertQrCode failed: $e');
      return false;
    }
  }

  static Future<bool> deleteQrCode(String qrId) async {
    if (!isAvailable) return false;
    try {
      await _qrCodesCollection.doc(qrId).delete();
      return true;
    } catch (e) {
      debugPrint('FirebaseService.deleteQrCode failed: $e');
      return false;
    }
  }

  /// Returns null if the fetch failed, so callers can keep their local cache.
  static Future<List<ShopModel>?> fetchAllShops() async {
    if (!isAvailable) return null;
    try {
      final snap = await _shopsCollection.get();
      return snap.docs.map((d) => ShopModel.fromMap(d.data())).toList();
    } catch (e) {
      debugPrint('FirebaseService.fetchAllShops failed: $e');
      return null;
    }
  }

  /// Returns null if the fetch failed, so callers can keep their local cache.
  static Future<List<QRCodeModel>?> fetchAllQrCodes() async {
    if (!isAvailable) return null;
    try {
      final snap = await _qrCodesCollection.get();
      return snap.docs.map((d) => QRCodeModel.fromMap(d.data())).toList();
    } catch (e) {
      debugPrint('FirebaseService.fetchAllQrCodes failed: $e');
      return null;
    }
  }

  static Future<ShopModel?> fetchShop(String shopId) async {
    if (!isAvailable) return null;
    try {
      final doc = await _shopsCollection.doc(shopId).get();
      if (!doc.exists) return null;
      return ShopModel.fromMap(doc.data()!);
    } catch (e) {
      debugPrint('FirebaseService.fetchShop failed: $e');
      return null;
    }
  }

  /// Saves feedback and marks emailNotificationStatus as 'pending' so the
  /// Cloud Function picks it up. Returns true if the write succeeded.
  static Future<bool> submitFeedback({
    required String shopId,
    required int rating,
    String? comment,
  }) async {
    if (!isAvailable) return false;
    try {
      await _feedbackCollection.add({
        'shopId': shopId,
        'rating': rating,
        'comment': comment,
        'createdAt': FieldValue.serverTimestamp(),
        'emailNotificationStatus': 'pending',
      });
      return true;
    } catch (e) {
      debugPrint('FirebaseService.submitFeedback failed: $e');
      return false;
    }
  }
}

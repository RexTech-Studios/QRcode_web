import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import '../models/shop_model.dart';
import '../models/qr_code_model.dart';
import '../utils/app_config.dart';

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
      if (AppConfig.useEmulator) {
        FirebaseFirestore.instance.useFirestoreEmulator(
          AppConfig.emulatorHost,
          AppConfig.firestoreEmulatorPort,
        );
        await FirebaseAuth.instance.useAuthEmulator(
          AppConfig.emulatorHost,
          AppConfig.authEmulatorPort,
        );
        debugPrint(
          'FirebaseService: using the LOCAL EMULATORS, not the live project.',
        );
      }
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
  ///
  /// Merges rather than replaces, so fields this build doesn't know about
  /// survive a save.
  static Future<bool> upsertShop(ShopModel shop) async {
    if (!isAvailable) return false;
    try {
      await _shopsCollection
          .doc(shop.shopId)
          .set(shop.toMap(), SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('FirebaseService.upsertShop failed: $e');
      return false;
    }
  }

  /// Sets the short QR code on an existing shop doc. Uses update(), which
  /// fails on a missing doc, because a merge would create a partial shop
  /// with no name, and [ShopModel.fromMap] can't parse one of those.
  static Future<bool> setShopQrCode(String shopId, String qrCode) async {
    if (!isAvailable) return false;
    try {
      await _shopsCollection.doc(shopId).update({'qrCode': qrCode});
      return true;
    } catch (e) {
      debugPrint('FirebaseService.setShopQrCode failed: $e');
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

  /// Contact fields from the removed email feature, which older shop docs
  /// still hold. Only the manual scrub in Settings touches these.
  static const List<String> legacyContactFields = [
    'notificationEmail',
    'emailNotificationsEnabled',
    'whatsappNumber',
  ];

  /// Ids of shop docs still holding a legacy contact field, or null if the
  /// fetch failed. Reads raw docs, as [ShopModel] no longer has these fields.
  static Future<List<String>?> fetchShopIdsWithLegacyFields() async {
    if (!isAvailable) return null;
    try {
      final snap = await _shopsCollection.get();
      return snap.docs
          .where((d) => legacyContactFields.any(d.data().containsKey))
          .map((d) => d.id)
          .toList();
    } catch (e) {
      debugPrint('FirebaseService.fetchShopIdsWithLegacyFields failed: $e');
      return null;
    }
  }

  /// Deletes the legacy contact fields, and nothing else, from [shopIds].
  /// Returns how many docs were cleaned, which is short of the full list if
  /// a batch failed partway. Safe to run again to finish the rest.
  static Future<int> removeLegacyContactFields(List<String> shopIds) async {
    if (!isAvailable) return 0;
    const batchSize = 400; // Firestore allows at most 500 writes per batch.
    var cleaned = 0;
    try {
      for (var start = 0; start < shopIds.length; start += batchSize) {
        final chunk = shopIds.skip(start).take(batchSize);
        final batch = FirebaseFirestore.instance.batch();
        for (final id in chunk) {
          batch.update(_shopsCollection.doc(id), {
            for (final field in legacyContactFields) field: FieldValue.delete(),
          });
        }
        await batch.commit();
        cleaned += chunk.length;
      }
    } catch (e) {
      debugPrint('FirebaseService.removeLegacyContactFields failed: $e');
    }
    return cleaned;
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

  /// Returns true if the write succeeded.
  ///
  /// Nothing reads emailNotificationStatus any more, but the interim
  /// firestore.rules still require it. Remove the key once the phase 1a rules
  /// are live and confirmed (see DEPLOY_PHASE_1A.md): those treat it as
  /// optional, and sending it keeps both the preview test and a rules
  /// rollback working.
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

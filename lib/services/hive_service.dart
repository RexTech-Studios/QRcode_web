import 'package:hive_flutter/hive_flutter.dart';
import '../models/shop_model.dart';
import '../models/qr_code_model.dart';
import '../models/settings_model.dart';

/// Owns Hive initialization, adapter registration and box access.
/// Call [HiveService.init] once before runApp.
class HiveService {
  HiveService._();

  static const String shopsBoxName = 'shops_box';
  static const String qrCodesBoxName = 'qr_codes_box';
  static const String settingsBoxName = 'settings_box';
  static const String metaBoxName = 'meta_box';

  static late Box<ShopModel> shopsBox;
  static late Box<QRCodeModel> qrCodesBox;
  static late Box<SettingsModel> settingsBox;
  static late Box metaBox;

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;

    await Hive.initFlutter();

    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ShopModelAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(QRStyleAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(QRCodeModelAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(SettingsModelAdapter());
    }

    shopsBox = await Hive.openBox<ShopModel>(shopsBoxName);
    qrCodesBox = await Hive.openBox<QRCodeModel>(qrCodesBoxName);
    settingsBox = await Hive.openBox<SettingsModel>(settingsBoxName);
    metaBox = await Hive.openBox(metaBoxName);

    _initialized = true;
  }

  // ---- Shops ----
  static List<ShopModel> getAllShops() => shopsBox.values.toList();

  static Future<void> saveShop(ShopModel shop) => shopsBox.put(shop.shopId, shop);

  static ShopModel? getShop(String shopId) => shopsBox.get(shopId);

  static Future<void> deleteShop(String shopId) => shopsBox.delete(shopId);

  /// Replaces the local shop cache with [shops] (the Firestore copy).
  static Future<void> replaceShops(List<ShopModel> shops) async {
    await shopsBox.clear();
    await shopsBox.putAll({for (final s in shops) s.shopId: s});
  }

  // ---- QR Codes ----
  static List<QRCodeModel> getAllQrCodes() => qrCodesBox.values.toList();

  static Future<void> saveQrCode(QRCodeModel qr) => qrCodesBox.put(qr.qrId, qr);

  static List<QRCodeModel> getQrCodesForShop(String shopId) =>
      qrCodesBox.values.where((q) => q.shopId == shopId).toList();

  static Future<void> deleteQrCode(String qrId) => qrCodesBox.delete(qrId);

  /// Replaces the local QR cache with [qrCodes] (the Firestore copy).
  static Future<void> replaceQrCodes(List<QRCodeModel> qrCodes) async {
    await qrCodesBox.clear();
    await qrCodesBox.putAll({for (final q in qrCodes) q.qrId: q});
  }

  // ---- Sync flags ----
  // Before cloud sync existed, records lived only in this browser's Hive.
  // The first sync uploads those once; after that Firestore is the source
  // of truth, so a record deleted elsewhere isn't re-uploaded from here.
  static bool isUploaded(String key) =>
      metaBox.get('uploaded_$key', defaultValue: false) as bool;

  static Future<void> markUploaded(String key) =>
      metaBox.put('uploaded_$key', true);

  // ---- Review submission state ----
  // In-memory on purpose: any page load, including a refresh or a new scan,
  // must show the review form again.
  static final Set<String> _reviewSubmittedThisSession = {};

  static bool isReviewSubmitted(String shopId) =>
      _reviewSubmittedThisSession.contains(shopId);

  static Future<void> markReviewSubmitted(String shopId) async {
    _reviewSubmittedThisSession.add(shopId);
  }

  // ---- Settings ----
  static SettingsModel getSettings() {
    if (settingsBox.isEmpty) {
      final defaults = SettingsModel();
      settingsBox.put('settings', defaults);
      return defaults;
    }
    return settingsBox.get('settings') ?? SettingsModel();
  }

  static Future<void> saveSettings(SettingsModel settings) =>
      settingsBox.put('settings', settings);
}

import 'package:flutter/foundation.dart';
import '../models/shop_model.dart';
import '../services/google_sheets_service.dart';
import '../services/hive_service.dart';
import '../services/firebase_service.dart';
import '../services/qr_service.dart';

class ShopProvider extends ChangeNotifier {
  List<ShopModel> _shops = [];
  ShopModel? _selectedShop;

  /// Set by [saveShop] when a new shop was created but its Google Sheet
  /// could not be created. Null when the last save had no sheet problem.
  String? lastSheetWarning;

  List<ShopModel> get shops => List.unmodifiable(_shops);
  ShopModel? get selectedShop => _selectedShop;

  void _loadFromHive() {
    _shops = HiveService.getAllShops()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (_selectedShop == null ||
        !_shops.any((s) => s.shopId == _selectedShop!.shopId)) {
      _selectedShop = _shops.isNotEmpty ? _shops.first : null;
    }
    notifyListeners();
  }

  /// Primary load: fetch from Firestore and mirror to Hive.
  /// Falls back to Hive if Firestore is unavailable or fails.
  /// Returns true if the list came from Firestore.
  Future<bool> loadShops() async {
    final remote = await FirebaseService.fetchAllShops();
    if (remote != null) {
      await HiveService.replaceShops(remote);
    }
    _loadFromHive();
    return remote != null;
  }

  /// Forgets everything in memory, on sign-out.
  void reset() {
    _shops = [];
    _selectedShop = null;
    lastSheetWarning = null;
    notifyListeners();
  }

  /// Creates a new shop, or updates an existing one with the same name,
  /// then persists to Hive (local cache) and Firestore (cloud sync).
  /// Pass [editingShopId] to update that shop even if its name changed.
  Future<ShopModel> saveShop({
    required String shopName,
    required String googleReviewUrl,
    String? shopLogo,
    String? preferredShopId,
    String? editingShopId,
    String? whatsappNumber,
    String? notificationEmail,
    bool? emailNotificationsEnabled,
    String? googleSheetsUrl,
  }) async {
    final editing = _shops.where((s) => s.shopId == editingShopId);
    final existing = editing.isNotEmpty
        ? editing
        : _shops.where(
            (s) => s.shopName.toLowerCase() == shopName.trim().toLowerCase(),
          );
    final previousName = existing.isNotEmpty ? existing.first.shopName : null;

    final shop = existing.isNotEmpty
        ? (existing.first
          ..shopName = shopName.trim()
          ..googleReviewUrl = googleReviewUrl.trim()
          ..shopLogo = shopLogo ?? existing.first.shopLogo
          ..whatsappNumber = whatsappNumber?.trim() ?? existing.first.whatsappNumber
          ..notificationEmail = notificationEmail?.trim() ?? existing.first.notificationEmail
          ..emailNotificationsEnabled = emailNotificationsEnabled ?? existing.first.emailNotificationsEnabled
          ..googleSheetsUrl = googleSheetsUrl ?? existing.first.googleSheetsUrl)
        : ShopModel(
            shopId: preferredShopId ?? QrService.newShopId(),
            shopName: shopName.trim(),
            shopLogo: shopLogo,
            googleReviewUrl: googleReviewUrl.trim(),
            createdAt: DateTime.now(),
            whatsappNumber: whatsappNumber?.trim(),
            notificationEmail: notificationEmail?.trim(),
            emailNotificationsEnabled: emailNotificationsEnabled ?? false,
            googleSheetsUrl: googleSheetsUrl?.trim(),
          );

    // Create a dedicated Google Spreadsheet whenever the shop still lacks one.
    // This covers brand-new shops AND self-heals existing shops whose sheet
    // creation failed earlier (a transient network/Apps Script error used to
    // leave the card permanently without a "View Google Sheet" link).
    lastSheetWarning = null;
    final hasSheet =
        shop.googleSheetsUrl != null && shop.googleSheetsUrl!.trim().isNotEmpty;
    if (!hasSheet) {
      final result = await GoogleSheetsService.createShopSheet(shop.shopName);
      if (result.isSuccess) {
        shop.googleSheetsUrl = result.url;
      } else {
        lastSheetWarning = result.error;
      }
    } else if (previousName != null && previousName != shop.shopName) {
      final renamed = await GoogleSheetsService.renameShopSheet(
        googleSheetsUrl: shop.googleSheetsUrl,
        shopName: shop.shopName,
      );
      if (!renamed) {
        lastSheetWarning =
            'Shop saved, but the Google Sheet title could not be updated.';
      }
    }

    // Firebase is primary: write there first, mirror to Hive regardless.
    final synced = await FirebaseService.upsertShop(shop);
    await HiveService.saveShop(shop);

    // Use _loadFromHive directly so the record we just wrote is immediately
    // visible. loadShops() would re-fetch from Firebase and could overwrite
    // Hive with a list that doesn't yet include this shop.
    _loadFromHive();
    _selectedShop = shop;
    notifyListeners();

    // Warn callers if Firebase write failed; Hive backup is in place.
    if (!synced) {
      throw StateError(
        'Shop saved to local backup only — cloud sync failed. '
        'It will be visible to this device but not to QR scanners until synced.',
      );
    }
    return shop;
  }

  /// Creates and attaches a Google Sheet to a shop that doesn't have one yet
  /// (e.g. Rextech Studios, created when the sheet service was unreachable).
  /// Returns the updated shop on success, or null if creation failed — the
  /// error is left in [lastSheetWarning] for the caller to surface.
  Future<ShopModel?> ensureSheetForShop(ShopModel shop) async {
    final hasSheet =
        shop.googleSheetsUrl != null && shop.googleSheetsUrl!.trim().isNotEmpty;
    if (hasSheet) return shop;

    lastSheetWarning = null;
    final result = await GoogleSheetsService.createShopSheet(shop.shopName);
    if (!result.isSuccess) {
      lastSheetWarning = result.error;
      notifyListeners();
      return null;
    }

    shop.googleSheetsUrl = result.url;
    await FirebaseService.upsertShop(shop);
    await HiveService.saveShop(shop);
    _loadFromHive();
    notifyListeners();
    return shop;
  }
}

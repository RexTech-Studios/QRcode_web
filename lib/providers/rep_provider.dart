import 'package:flutter/foundation.dart';

import '../models/assignment_model.dart';
import '../models/invoice_model.dart';
import '../models/sales_user_model.dart';
import '../models/shop_model.dart';
import '../services/google_sheets_service.dart';
import '../services/sales_repository.dart';
import '../utils/validators.dart';
import 'sales_admin_provider.dart';

/// One QR a sales person holds, with the shop it currently points to.
class RepItem {
  final Assignment assignment;
  final ShopModel? shop;

  const RepItem(this.assignment, this.shop);

  String get shopName => shop?.shopName ?? 'Shop not found';
}

/// Creates a new Google Sheet for a shop name.
typedef CreateSheet = Future<SheetResult> Function(String shopName);

typedef RenameSheet = Future<bool> Function({
  required String? googleSheetsUrl,
  required String shopName,
});

/// What a signed-in sales person sees: only the QR codes the admin assigned to
/// them, each editable once.
class RepProvider extends ChangeNotifier {
  RepProvider(this._repo, {RenameSheet? renameSheet, CreateSheet? createSheet})
    : _renameSheet = renameSheet ?? GoogleSheetsService.renameShopSheet,
      _createSheet = createSheet ?? GoogleSheetsService.createShopSheet;

  final SalesRepository _repo;
  final RenameSheet _renameSheet;
  final CreateSheet _createSheet;

  SalesUser? _user;
  List<RepItem> _items = [];
  Map<String, Invoice> _invoices = {};
  int? _price;
  bool _loading = false;
  String? _loadError;

  SalesUser? get user => _user;
  List<RepItem> get items => List.unmodifiable(_items);
  bool get loading => _loading;
  String? get loadError => _loadError;

  /// The invoice already issued for this QR, if any.
  Invoice? invoiceFor(String shopId) => _invoices[shopId];

  /// The fixed price per QR the admin set, or null if there isn't one yet.
  int? get price => _price;

  /// This sales person's invoices, newest first.
  List<Invoice> get invoices =>
      _invoices.values.toList()..sort((a, b) => b.number.compareTo(a.number));

  int get invoicedCount => _invoices.length;
  int get invoicedTotal => _invoices.values.fold(0, (s, i) => s + i.amount);

  int get doneCount => _items.where((i) => i.assignment.isSold).length;
  int get pendingCount => _items.where((i) => !i.assignment.isSold).length;

  Future<void> load(SalesUser user) async {
    _user = user;
    _loading = true;
    _loadError = null;
    notifyListeners();
    try {
      final assignments = await _repo.fetchAssignmentsFor(user.uid);
      final shops = await Future.wait([
        for (final a in assignments) _repo.fetchShop(a.shopId),
      ]);
      _items = [
        for (var i = 0; i < assignments.length; i++)
          RepItem(assignments[i], shops[i]),
      ];
    } catch (e) {
      debugPrint('RepProvider.load failed: $e');
      _loadError =
          'Could not load your QR codes. Check your connection and try again.';
    }
    // Invoices are separate: if they can't load, the QR list still works.
    try {
      final invoices = await _repo.fetchInvoicesFor(user.uid);
      _invoices = {for (final i in invoices) i.shopId: i};
      _price = await _repo.fetchInvoicePrice();
    } catch (e) {
      debugPrint('RepProvider invoices load failed: $e');
    }
    _loading = false;
    notifyListeners();
  }

  /// Forgets everything in memory, on sign-out.
  void reset() {
    _user = null;
    _items = [];
    _invoices = {};
    _price = null;
    _loading = false;
    _loadError = null;
    notifyListeners();
  }

  /// Firestore words a refusal differently depending on where it surfaces
  /// (a plain write, a transaction, the emulator), so look for all of them.
  static bool _isPermissionDenied(Object e) {
    final text = e.toString().toLowerCase();
    return text.contains('permission-denied') ||
        text.contains('permission_denied') ||
        text.contains('insufficient permissions');
  }

  /// Whether [url] is a Google Sheets link the security rules will accept.
  static bool isSafeSheetUrl(String url) =>
      url.length <= 300 &&
      RegExp(
        r'^https://docs\.google\.com/spreadsheets/d/[A-Za-z0-9_-]+(/[^\s]*)?$',
      ).hasMatch(url);

  /// Returns a message if the name or link can't be saved, otherwise null.
  /// Mirrors what firestore.rules accepts, so a bad value is caught here first.
  static String? validateSetup(String shopName, String reviewUrl) {
    final name = shopName.trim();
    if (name.isEmpty) return 'Enter the shop name.';
    if (name.length > 100) {
      return 'The shop name is too long (100 characters at most).';
    }
    final url = reviewUrl.trim();
    if (url.isEmpty) return 'Paste the Google Maps review link.';
    if (url.length > 2000 ||
        RegExp(r'\s').hasMatch(url) ||
        !Validators.isSafeReviewRedirect(url)) {
      return 'Enter a valid Google Maps review link (it must start with https://).';
    }
    return null;
  }

  /// The sales person's one edit. Throws [SalesException] with a message to
  /// show if it can't be saved.
  Future<void> saveSetup(
    RepItem item, {
    required String shopName,
    required String reviewUrl,
  }) async {
    final problem = validateSetup(shopName, reviewUrl);
    if (problem != null) throw SalesException(problem);
    if (item.assignment.locked) {
      throw const SalesException(
        'This QR is locked. Ask the admin to unlock it.',
      );
    }

    final name = shopName.trim();
    final url = reviewUrl.trim();
    try {
      await _repo.repSaveSetup(
        assignment: item.assignment,
        shopName: name,
        reviewUrl: url,
      );
    } catch (e) {
      if (e is SalesException) rethrow;
      if (_isPermissionDenied(e)) {
        throw const SalesException(
          'This could not be saved. The QR may have just been locked, or your '
          'account may have been turned off. Pull to refresh, or ask the admin.',
        );
      }
      throw const SalesException(
        'Could not save. Check your connection and try again.',
      );
    }

    // The sheet title is cosmetic; the save above is what counts.
    try {
      await _renameSheet(
        googleSheetsUrl: item.shop?.googleSheetsUrl,
        shopName: name,
      );
    } catch (_) {}

    final now = DateTime.now();
    final old = item.shop;
    final updatedShop = old == null
        ? null
        : ShopModel(
            shopId: old.shopId,
            shopName: name,
            shopLogo: old.shopLogo,
            googleReviewUrl: url,
            createdAt: old.createdAt,
            googleSheetsUrl: old.googleSheetsUrl,
            qrCode: old.qrCode,
          );
    final updated = RepItem(
      item.assignment.copyWith(
        locked: true,
        lastEditedAt: now,
        soldAt: item.assignment.soldAt ?? now,
      ),
      updatedShop,
    );
    _items = [
      for (final i in _items)
        i.assignment.shopId == item.assignment.shopId ? updated : i,
    ];
    notifyListeners();
  }

  /// Issues the invoice for a QR the sales person has set up, at the admin's
  /// fixed price, or returns the one it already has. Throws [SalesException]
  /// with a message to show if it can't be done.
  Future<Invoice> createInvoice(
    RepItem item, {
    required String clientName,
    required String clientPhone,
    required String clientAddress,
  }) async {
    final user = _user;
    if (user == null) {
      throw const SalesException('Please sign in again.');
    }
    if (!item.assignment.isSold) {
      throw const SalesException(
        'Set up this QR for your client first, then make the invoice.',
      );
    }
    final existing = _invoices[item.assignment.shopId];
    if (existing != null) return existing;

    final price = _price;
    if (price == null) {
      throw const SalesException(
        'The invoice price has not been set yet. Ask the admin to set it.',
      );
    }
    final problem = SalesAdminProvider.validateInvoice(
      clientName: clientName,
      clientPhone: clientPhone,
      clientAddress: clientAddress,
      price: '$price',
    );
    if (problem != null) throw SalesException(problem);

    final Invoice invoice;
    try {
      invoice = await _repo.createInvoice(
        assignment: item.assignment,
        clientName: clientName.trim(),
        clientPhone: clientPhone.trim(),
        clientAddress: clientAddress.trim(),
        amount: price,
        createdByUid: user.uid,
        createdByName: user.name,
      );
    } catch (e) {
      if (e is SalesException) rethrow;
      if (_isPermissionDenied(e)) {
        throw const SalesException(
          'The invoice could not be made. The price may have just changed, or '
          'your account may have been turned off. Pull to refresh and try again.',
        );
      }
      throw const SalesException(
        'Could not make the invoice. Check your connection and try again.',
      );
    }
    _invoices = {..._invoices, invoice.shopId: invoice};
    notifyListeners();
    return invoice;
  }

  /// Creates the Google Sheet that collects this shop's feedback and attaches
  /// it to the shop, for a QR that has none yet. Returns the updated item.
  /// Throws [SalesException] with a message to show if it can't be done.
  Future<RepItem> generateSheet(RepItem item) async {
    final shop = item.shop;
    if (shop == null) {
      throw const SalesException('This QR\'s shop could not be found.');
    }
    if ((shop.googleSheetsUrl ?? '').trim().isNotEmpty) return item;

    final result = await _createSheet(shop.shopName);
    final url = result.url;
    if (!result.isSuccess || url == null) {
      throw SalesException(
        result.error ?? 'Could not create the Google Sheet. Try again.',
      );
    }
    if (!isSafeSheetUrl(url)) {
      throw const SalesException(
        'The sheet service sent back a link that could not be used. Try again.',
      );
    }

    try {
      await _repo.repSaveSheetUrl(shopId: shop.shopId, sheetUrl: url);
    } catch (e) {
      if (e is SalesException) rethrow;
      if (_isPermissionDenied(e)) {
        throw const SalesException(
          'The sheet could not be attached. Your account may have been turned '
          'off, or this QR may no longer be yours. Pull to refresh, or ask the admin.',
        );
      }
      throw const SalesException(
        'The sheet was made but could not be saved. Check your connection and try again.',
      );
    }

    final updated = RepItem(
      item.assignment,
      ShopModel(
        shopId: shop.shopId,
        shopName: shop.shopName,
        shopLogo: shop.shopLogo,
        googleReviewUrl: shop.googleReviewUrl,
        createdAt: shop.createdAt,
        googleSheetsUrl: url,
        qrCode: shop.qrCode,
      ),
    );
    _items = [
      for (final i in _items)
        i.assignment.shopId == item.assignment.shopId ? updated : i,
    ];
    notifyListeners();
    return updated;
  }
}

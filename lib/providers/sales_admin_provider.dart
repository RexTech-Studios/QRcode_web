import 'package:flutter/foundation.dart';

import '../models/assignment_model.dart';
import '../models/invoice_model.dart';
import '../models/qr_code_model.dart';
import '../models/sales_user_model.dart';
import '../models/shop_model.dart';
import '../services/sales_repository.dart';
import '../utils/app_config.dart';
import '../utils/money_format.dart';
import '../utils/qr_number_parser.dart';
import '../utils/qr_ranges.dart';

/// A QR code that can't be handed to a sales person, and why.
class BlockedQr {
  final String code;
  final String reason;
  const BlockedQr(this.code, this.reason);
}

/// A QR code that moves from one sales person to another.
class MovedQr {
  final String code;
  final String fromName;
  const MovedQr(this.code, this.fromName);
}

/// What an "assign these QR numbers" request would do, worked out before
/// anything is written so the admin can check it first.
class AssignPlan {
  final List<QRCodeModel> toAssign;
  final List<MovedQr> moving;
  final List<String> alreadyWithRep;
  final List<String> notFound;
  final List<BlockedQr> blocked;
  final List<String> parseErrors;

  const AssignPlan({
    required this.toAssign,
    required this.moving,
    required this.alreadyWithRep,
    required this.notFound,
    required this.blocked,
    required this.parseErrors,
  });

  bool get canApply => toAssign.isNotEmpty;
  bool get hasProblems =>
      notFound.isNotEmpty || blocked.isNotEmpty || parseErrors.isNotEmpty;
}

/// The admin's view of the sales team: logins, who holds which QR, and the
/// unlock that lets a sales person edit a QR a second time.
class SalesAdminProvider extends ChangeNotifier {
  SalesAdminProvider(this._repo);

  final SalesRepository _repo;

  List<SalesUser> _users = [];
  List<Assignment> _assignments = [];
  Map<String, Invoice> _invoices = {};
  int? _defaultPrice;
  bool _loading = false;
  String? _loadError;

  List<SalesUser> get users => List.unmodifiable(_users);
  List<Assignment> get assignments => List.unmodifiable(_assignments);
  bool get loading => _loading;
  String? get loadError => _loadError;

  /// The invoice already issued for this QR, if any.
  Invoice? invoiceFor(String shopId) => _invoices[shopId];

  /// Every invoice, newest number first.
  List<Invoice> get invoices =>
      _invoices.values.toList()..sort((a, b) => b.number.compareTo(a.number));

  /// The fixed price per QR, or null until the admin sets it. Sales people
  /// invoice at this price and cannot change it.
  int? get defaultPrice => _defaultPrice;

  Assignment? assignmentFor(String shopId) {
    for (final a in _assignments) {
      if (a.shopId == shopId) return a;
    }
    return null;
  }

  SalesUser? userById(String uid) {
    for (final u in _users) {
      if (u.uid == uid) return u;
    }
    return null;
  }

  int assignedCountFor(String uid) =>
      _assignments.where((a) => a.assignedTo == uid).length;
  int soldCountFor(String uid) =>
      _assignments.where((a) => a.assignedTo == uid && a.isSold).length;
  int pendingCountFor(String uid) =>
      _assignments.where((a) => a.assignedTo == uid && !a.isSold).length;

  /// Loads the team and the assignments. Never throws: a failure is kept in
  /// [loadError] so the rest of the dashboard keeps working without it.
  Future<void> load() async {
    _loading = true;
    _loadError = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _repo.fetchUsers(),
        _repo.fetchAllAssignments(),
      ]);
      _users = results[0] as List<SalesUser>;
      _assignments = results[1] as List<Assignment>;
    } catch (e) {
      debugPrint('SalesAdminProvider.load failed: $e');
      _loadError =
          'Could not load the sales team. Check your connection and try again.';
    }
    // Invoices are separate: if they can't load, the team still shows. A QR
    // that already has an invoice is never billed twice either way, because
    // createInvoice returns the existing one.
    try {
      final invoices = await _repo.fetchInvoices();
      _invoices = {for (final i in invoices) i.shopId: i};
      _defaultPrice = await _repo.fetchInvoicePrice();
    } catch (e) {
      debugPrint('SalesAdminProvider invoices load failed: $e');
    }
    _loading = false;
    notifyListeners();
  }

  /// Forgets everything in memory, on sign-out.
  void reset() {
    _users = [];
    _assignments = [];
    _invoices = {};
    _defaultPrice = null;
    _loading = false;
    _loadError = null;
    notifyListeners();
  }

  // ---- Team ----

  static final RegExp _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  Future<SalesUser> addSalesPerson({
    required String name,
    required String email,
    required String password,
  }) async {
    if (name.trim().isEmpty) {
      throw const SalesException('Enter the sales person\'s name.');
    }
    if (!_email.hasMatch(email.trim())) {
      throw const SalesException('Enter a valid email address.');
    }
    if (password.length < 6) {
      throw const SalesException('The password needs at least 6 characters.');
    }
    final user = await _repo.createSalesAccount(
      name: name,
      email: email,
      password: password,
    );
    _users = [..._users.where((u) => u.uid != user.uid), user]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    notifyListeners();
    return user;
  }

  Future<void> setActive(SalesUser user, bool active) async {
    await _repo.setUserActive(user.uid, active);
    _users = [
      for (final u in _users)
        u.uid == user.uid ? u.copyWith(active: active) : u,
    ];
    notifyListeners();
  }

  Future<void> sendPasswordReset(SalesUser user) =>
      _repo.sendPasswordReset(user.email);

  // ---- Assigning ----

  /// Printed stock still waiting for a sales person: QR codes nobody holds
  /// whose shop is still the "Demo QR###" placeholder. Real client QR codes
  /// are left out so they aren't handed out by mistake; the admin can still
  /// type any number by hand.
  List<int> availableDemoQrNumbers({
    required List<QRCodeModel> qrCodes,
    required List<ShopModel> shops,
  }) {
    final demoShopIds = {
      for (final s in shops)
        if (_demoName.hasMatch(s.shopName.trim())) s.shopId,
    };
    final held = {for (final a in _assignments) a.shopId};
    final numbers = <int>[];
    for (final q in qrCodes) {
      if (!demoShopIds.contains(q.shopId) || held.contains(q.shopId)) continue;
      final n = qrNumberOf(q.qrCode);
      if (n != null) numbers.add(n);
    }
    numbers.sort();
    return numbers;
  }

  static final RegExp _demoName = RegExp(r'^Demo QR\d+$', caseSensitive: false);

  /// Works out what assigning [input] (e.g. "121-140, 145") to [rep] would do.
  AssignPlan planAssignment({
    required String input,
    required List<QRCodeModel> qrCodes,
    required SalesUser rep,
  }) {
    final parsed = parseQrNumbers(input);
    final byCode = {
      for (final q in qrCodes)
        if (q.qrCode.isNotEmpty) q.qrCode.toUpperCase(): q,
    };

    final toAssign = <QRCodeModel>[];
    final moving = <MovedQr>[];
    final alreadyWithRep = <String>[];
    final notFound = <String>[];
    final blocked = <BlockedQr>[];

    for (final code in parsed.codes) {
      final qr = byCode[code];
      if (qr == null) {
        notFound.add(code);
        continue;
      }
      final existing = assignmentFor(qr.shopId);
      if (existing == null) {
        toAssign.add(qr);
      } else if (existing.assignedTo == rep.uid) {
        alreadyWithRep.add(code);
      } else if (existing.isSold) {
        blocked.add(
          BlockedQr(code, 'already sold by ${existing.assignedToName}'),
        );
      } else if (existing.locked) {
        blocked.add(BlockedQr(code, 'locked for ${existing.assignedToName}'));
      } else {
        toAssign.add(qr);
        moving.add(MovedQr(code, existing.assignedToName));
      }
    }

    return AssignPlan(
      toAssign: toAssign,
      moving: moving,
      alreadyWithRep: alreadyWithRep,
      notFound: notFound,
      blocked: blocked,
      parseErrors: parsed.errors,
    );
  }

  /// Writes the plan and returns how many QR codes were assigned.
  Future<int> applyAssignment(AssignPlan plan, SalesUser rep) async {
    if (!plan.canApply) return 0;
    await _repo.assign(plan.toAssign, rep);
    // Re-read so the list shows the server's own timestamps.
    try {
      _assignments = await _repo.fetchAllAssignments();
    } catch (_) {
      final moved = {for (final q in plan.toAssign) q.shopId};
      _assignments = [
        ..._assignments.where((a) => !moved.contains(a.shopId)),
        for (final q in plan.toAssign)
          Assignment(
            shopId: q.shopId,
            qrId: q.qrId,
            qrCode: q.qrCode,
            assignedTo: rep.uid,
            assignedToName: rep.name,
            assignedAt: DateTime.now(),
          ),
      ];
    }
    notifyListeners();
    return plan.toAssign.length;
  }

  /// Takes a QR back from a sales person. Not allowed once it has been sold.
  Future<void> unassign(Assignment assignment) async {
    if (assignment.isSold) {
      throw const SalesException(
        'This QR has been sold, so it can\'t be taken back.',
      );
    }
    await _repo.unassign(assignment.shopId);
    _assignments = _assignments
        .where((a) => a.shopId != assignment.shopId)
        .toList();
    notifyListeners();
  }

  // ---- Invoices ----

  /// Returns a message if the invoice details can't be used, otherwise null.
  static String? validateInvoice({
    required String clientName,
    required String clientPhone,
    required String clientAddress,
    required String price,
  }) {
    final name = clientName.trim();
    if (name.isEmpty) return 'Enter the client\'s name.';
    if (name.length > 100) return 'The client name is too long (100 at most).';
    final phone = clientPhone.trim();
    if (phone.length > 20 || !RegExp(r'^[0-9+\-\s()]*$').hasMatch(phone)) {
      return 'Enter a valid phone number, or leave it empty.';
    }
    if (clientAddress.trim().length > 200) {
      return 'The address is too long (200 at most).';
    }
    final amount = parseRupees(price);
    if (amount == null) return 'Enter the price as a whole number, like 1500.';
    if (amount > 10000000) return 'That price looks too large. Check it.';
    return null;
  }

  /// Issues the invoice for a sold QR, or returns the one it already has.
  Future<Invoice> createInvoice(
    Assignment assignment, {
    required String clientName,
    required String clientPhone,
    required String clientAddress,
    required String price,
  }) async {
    if (!assignment.isSold) {
      throw const SalesException(
        'Only a QR that has been set up for a client can be invoiced.',
      );
    }
    final existing = _invoices[assignment.shopId];
    if (existing != null) return existing;

    final problem = validateInvoice(
      clientName: clientName,
      clientPhone: clientPhone,
      clientAddress: clientAddress,
      price: price,
    );
    if (problem != null) throw SalesException(problem);

    final invoice = await _repo.createInvoice(
      assignment: assignment,
      clientName: clientName.trim(),
      clientPhone: clientPhone.trim(),
      clientAddress: clientAddress.trim(),
      amount: parseRupees(price)!,
      createdByUid: AppConfig.adminUid,
      createdByName: 'Admin',
    );
    _invoices = {..._invoices, invoice.shopId: invoice};
    notifyListeners();
    return invoice;
  }

  /// Returns a message if [price] can't be the fixed price, otherwise null.
  static String? validatePrice(String price) {
    final amount = parseRupees(price);
    if (amount == null) return 'Enter the price as a whole number, like 1500.';
    if (amount > 10000000) return 'That price looks too large. Check it.';
    return null;
  }

  /// Sets the fixed price per QR that sales people invoice at.
  Future<void> setPrice(String price) async {
    final problem = validatePrice(price);
    if (problem != null) throw SalesException(problem);
    final amount = parseRupees(price)!;
    await _repo.setInvoicePrice(amount);
    _defaultPrice = amount;
    notifyListeners();
  }

  /// Lets the sales person edit this QR once more.
  Future<void> unlock(Assignment assignment) async {
    await _repo.setLocked(assignment.shopId, false);
    _assignments = [
      for (final a in _assignments)
        a.shopId == assignment.shopId ? a.copyWith(locked: false) : a,
    ];
    notifyListeners();
  }
}

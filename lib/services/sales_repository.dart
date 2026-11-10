import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../firebase_options.dart';
import '../models/assignment_model.dart';
import '../models/invoice_model.dart';
import '../models/qr_code_model.dart';
import '../models/sales_user_model.dart';
import '../models/shop_model.dart';
import '../utils/app_config.dart';
import 'auth_service.dart';
import 'firebase_service.dart';

/// A failure with a message that is safe and useful to show the person.
class SalesException implements Exception {
  final String message;
  const SalesException(this.message);

  @override
  String toString() => message;
}

/// Everything the sales-team feature reads and writes. The screens and
/// providers only know this interface, so tests can swap in a fake.
abstract class SalesRepository {
  Future<SalesUser?> fetchUser(String uid);
  Future<List<SalesUser>> fetchUsers();

  /// Creates the login and its `users/{uid}` record. The admin stays signed in.
  Future<SalesUser> createSalesAccount({
    required String name,
    required String email,
    required String password,
  });

  Future<void> setUserActive(String uid, bool active);
  Future<void> sendPasswordReset(String email);

  /// Changes the sales person's name, and the name copied onto each of their
  /// assignments ([assignmentShopIds]) so the lists stay consistent.
  Future<void> renameSalesUser({
    required String uid,
    required String name,
    required List<String> assignmentShopIds,
  });

  /// Removes the sales person's record, after removing the assignments in
  /// [unsoldShopIds]. Their login can no longer open anything (the security
  /// rules need the record). Assignments that were sold are left alone, as
  /// the record of the sale.
  Future<void> deleteSalesUser({
    required String uid,
    required List<String> unsoldShopIds,
  });

  Future<List<Assignment>> fetchAllAssignments();
  Future<List<Assignment>> fetchAssignmentsFor(String uid);

  /// Creates (or replaces) one assignment per QR code, for [rep].
  Future<void> assign(List<QRCodeModel> qrCodes, SalesUser rep);
  Future<void> unassign(String shopId);

  /// Takes several QR codes back at once.
  Future<void> unassignMany(List<String> shopIds);

  /// Hands these assignments to [to] (admin fixing a wrong assignment).
  Future<void> reassign(List<Assignment> assignments, SalesUser to);
  Future<void> setLocked(String shopId, bool locked);

  Future<ShopModel?> fetchShop(String shopId);

  /// The sales person's one edit: changes the shop's name and review link and
  /// locks the assignment, in a single write the security rules check.
  Future<void> repSaveSetup({
    required Assignment assignment,
    required String shopName,
    required String reviewUrl,
  });

  /// Attaches a freshly generated Google Sheet to a shop that has none. The
  /// security rules allow this only for the sales person's own QR, only when
  /// the shop has no sheet yet, and only for a Google Sheets link.
  Future<void> repSaveSheetUrl({
    required String shopId,
    required String sheetUrl,
  });

  // ---- Invoices ----

  /// Every invoice (admin only).
  Future<List<Invoice>> fetchInvoices();

  /// Only the invoices for QR codes assigned to [uid]. This is what a sales
  /// person can read; the security rules refuse any other query.
  Future<List<Invoice>> fetchInvoicesFor(String uid);

  /// The fixed price per QR, or null if the admin has not set one yet.
  Future<int?> fetchInvoicePrice();

  /// Sets the fixed price per QR (admin only). Sales people invoice at this
  /// price and cannot change it.
  Future<void> setInvoicePrice(int price);

  /// Issues the invoice for a sold QR. A QR can only be invoiced once: if one
  /// already exists it is returned unchanged and no number is used up.
  /// [createdByUid] / [createdByName] say who is issuing it.
  Future<Invoice> createInvoice({
    required Assignment assignment,
    required String clientName,
    required String clientPhone,
    required String clientAddress,
    required int amount,
    required String createdByUid,
    required String createdByName,
  });
}

class FirestoreSalesRepository implements SalesRepository {
  FirestoreSalesRepository({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final http.Client _http;

  FirebaseFirestore get _db {
    if (!FirebaseService.isAvailable) {
      throw const SalesException('Cloud sync is not available right now.');
    }
    return FirebaseFirestore.instance;
  }

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _assignments =>
      _db.collection('assignments');
  CollectionReference<Map<String, dynamic>> get _shops =>
      _db.collection('shops');

  // ---- Users ----

  @override
  Future<SalesUser?> fetchUser(String uid) async {
    final doc = await _users.doc(uid).get();
    final data = doc.data();
    if (!doc.exists || data == null) return null;
    return SalesUser.fromMap(data, fallbackUid: doc.id);
  }

  @override
  Future<List<SalesUser>> fetchUsers() async {
    final snap = await _users.get();
    final users = [
      for (final doc in snap.docs)
        SalesUser.fromMap(doc.data(), fallbackUid: doc.id),
    ].where((u) => u.isSales).toList();
    users.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return users;
  }

  @override
  Future<SalesUser> createSalesAccount({
    required String name,
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanName = name.trim();
    final uid = await _signUpOrRecover(cleanEmail, password);

    if (uid == AppConfig.adminUid) {
      throw const SalesException('That email belongs to the admin account.');
    }
    final existing = await _users.doc(uid).get();
    if (existing.exists) {
      throw const SalesException(
        'A sales login already exists for this email.',
      );
    }

    await _users.doc(uid).set({
      'uid': uid,
      'name': cleanName,
      'email': cleanEmail,
      'role': SalesUser.salesRole,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return SalesUser(
      uid: uid,
      name: cleanName,
      email: cleanEmail,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<void> setUserActive(String uid, bool active) =>
      _users.doc(uid).update({'active': active});

  @override
  Future<void> sendPasswordReset(String email) =>
      AuthService.sendPasswordReset(email);

  // A batch holds at most 500 writes.
  static const int _chunk = 400;

  @override
  Future<void> renameSalesUser({
    required String uid,
    required String name,
    required List<String> assignmentShopIds,
  }) async {
    await _users.doc(uid).update({'name': name});
    for (var i = 0; i < assignmentShopIds.length; i += _chunk) {
      final batch = _db.batch();
      for (final id in assignmentShopIds.skip(i).take(_chunk)) {
        batch.update(_assignments.doc(id), {'assignedToName': name});
      }
      await batch.commit();
    }
  }

  @override
  Future<void> deleteSalesUser({
    required String uid,
    required List<String> unsoldShopIds,
  }) async {
    // Assignments first: if this stops part-way the person still exists and
    // the delete can simply be tried again.
    await unassignMany(unsoldShopIds);
    await _users.doc(uid).delete();
  }

  // ---- Login creation through the Identity Toolkit REST API ----
  //
  // Signing a new user up with the Firebase SDK would sign the admin out.
  // The REST endpoint creates the account without touching the admin's
  // session. If sign-up is turned off for the project, Firebase says so and
  // the message below tells the admin where to switch it on.

  String get _identityBase => AppConfig.useEmulator
      ? 'http://${AppConfig.emulatorHost}:${AppConfig.authEmulatorPort}/identitytoolkit.googleapis.com/v1'
      : 'https://identitytoolkit.googleapis.com/v1';

  String get _apiKey => DefaultFirebaseOptions.currentPlatform.apiKey;

  Future<String> _signUpOrRecover(String email, String password) async {
    final signUp = await _identityCall('accounts:signUp', {
      'email': email,
      'password': password,
      'returnSecureToken': false,
    });
    final uid = signUp.localId;
    if (uid != null) return uid;

    if (signUp.error == 'EMAIL_EXISTS') {
      // A previous attempt may have created the login but failed before saving
      // the record. If the same password works, pick up where it stopped.
      final signIn = await _identityCall('accounts:signInWithPassword', {
        'email': email,
        'password': password,
        'returnSecureToken': false,
      });
      if (signIn.localId != null) return signIn.localId!;
      throw const SalesException(
        'This email already has a login. Use a different email, or enter the '
        'password that was set the first time.',
      );
    }
    throw SalesException(_friendlySignUpError(signUp.error));
  }

  Future<_IdentityResult> _identityCall(
    String method,
    Map<String, Object?> body,
  ) async {
    final http.Response response;
    try {
      response = await _http.post(
        Uri.parse('$_identityBase/$method?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
    } catch (_) {
      throw const SalesException(
        'Could not reach the login service. Check your connection.',
      );
    }
    Map<String, dynamic> json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const SalesException('The login service sent an unexpected reply.');
    }
    final error =
        (json['error'] as Map<String, dynamic>?)?['message'] as String?;
    return _IdentityResult(localId: json['localId'] as String?, error: error);
  }

  static String _friendlySignUpError(String? code) {
    final key = (code ?? '').split(' ').first;
    switch (key) {
      case 'INVALID_EMAIL':
        return 'That email address is not valid.';
      case 'WEAK_PASSWORD':
        return 'The password is too weak. Use at least 6 characters.';
      case 'TOO_MANY_ATTEMPTS_TRY_LATER':
        return 'Too many attempts. Wait a few minutes and try again.';
      case 'OPERATION_NOT_ALLOWED':
      case 'ADMIN_ONLY_OPERATION':
        return 'Creating logins is switched off for this project. In the Firebase '
            'console, open Authentication > Settings > User actions and turn on '
            '"Enable create (sign-up)".';
      default:
        return 'Could not create the login${code == null ? '' : ' ($code)'}.';
    }
  }

  // ---- Assignments ----

  @override
  Future<List<Assignment>> fetchAllAssignments() async {
    final snap = await _assignments.get();
    return [
      for (final doc in snap.docs)
        Assignment.fromMap(doc.data(), fallbackShopId: doc.id),
    ];
  }

  @override
  Future<List<Assignment>> fetchAssignmentsFor(String uid) async {
    // The security rules only allow this exact filter; an unfiltered list is denied.
    final snap = await _assignments.where('assignedTo', isEqualTo: uid).get();
    final list = [
      for (final doc in snap.docs)
        Assignment.fromMap(doc.data(), fallbackShopId: doc.id),
    ];
    list.sort((a, b) => _codeNumber(a.qrCode).compareTo(_codeNumber(b.qrCode)));
    return list;
  }

  @override
  Future<void> assign(List<QRCodeModel> qrCodes, SalesUser rep) async {
    // A batch holds at most 500 writes.
    const chunk = 400;
    for (var start = 0; start < qrCodes.length; start += chunk) {
      final batch = _db.batch();
      for (final qr in qrCodes.skip(start).take(chunk)) {
        batch.set(_assignments.doc(qr.shopId), {
          'shopId': qr.shopId,
          'qrId': qr.qrId,
          'qrCode': qr.qrCode,
          'assignedTo': rep.uid,
          'assignedToName': rep.name,
          'assignedAt': FieldValue.serverTimestamp(),
          'locked': false,
          // Explicit nulls: the security rules compare these fields.
          'soldAt': null,
          'lastEditedAt': null,
        });
      }
      await batch.commit();
    }
  }

  @override
  Future<void> unassign(String shopId) => _assignments.doc(shopId).delete();

  @override
  Future<void> unassignMany(List<String> shopIds) async {
    for (var i = 0; i < shopIds.length; i += _chunk) {
      final batch = _db.batch();
      for (final id in shopIds.skip(i).take(_chunk)) {
        batch.delete(_assignments.doc(id));
      }
      await batch.commit();
    }
  }

  @override
  Future<void> reassign(List<Assignment> assignments, SalesUser to) async {
    for (var i = 0; i < assignments.length; i += _chunk) {
      final batch = _db.batch();
      for (final a in assignments.skip(i).take(_chunk)) {
        batch.update(_assignments.doc(a.shopId), {
          'assignedTo': to.uid,
          'assignedToName': to.name,
          'assignedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
  }

  @override
  Future<void> setLocked(String shopId, bool locked) =>
      _assignments.doc(shopId).update({'locked': locked});

  // ---- Sales person's own edit ----

  @override
  Future<ShopModel?> fetchShop(String shopId) =>
      FirebaseService.fetchShop(shopId);

  @override
  Future<void> repSaveSetup({
    required Assignment assignment,
    required String shopName,
    required String reviewUrl,
  }) async {
    final batch = _db.batch();
    // Only these two keys: the rules reject any other change to the shop.
    batch.update(_shops.doc(assignment.shopId), {
      'shopName': shopName,
      'googleReviewUrl': reviewUrl,
    });
    final lock = <String, Object?>{
      'locked': true,
      'lastEditedAt': FieldValue.serverTimestamp(),
    };
    // soldAt is set on the first edit only; the rules reject it afterwards.
    if (assignment.soldAt == null) {
      lock['soldAt'] = FieldValue.serverTimestamp();
    }
    batch.update(_assignments.doc(assignment.shopId), lock);
    await batch.commit();
  }

  @override
  Future<void> repSaveSheetUrl({
    required String shopId,
    required String sheetUrl,
  }) => _shops.doc(shopId).update({'googleSheetsUrl': sheetUrl});

  // ---- Invoices ----

  CollectionReference<Map<String, dynamic>> get _invoices =>
      _db.collection('invoices');
  DocumentReference<Map<String, dynamic>> get _invoiceCounter =>
      _db.collection('counters').doc('invoices');
  DocumentReference<Map<String, dynamic>> get _invoiceSettings =>
      _db.collection('settings').doc('invoice');

  @override
  Future<List<Invoice>> fetchInvoices() async {
    final snap = await _invoices.get();
    return [
      for (final doc in snap.docs)
        Invoice.fromMap(doc.data(), fallbackShopId: doc.id),
    ];
  }

  @override
  Future<List<Invoice>> fetchInvoicesFor(String uid) async {
    // The security rules only allow this exact filter.
    final snap = await _invoices.where('soldByUid', isEqualTo: uid).get();
    return [
      for (final doc in snap.docs)
        Invoice.fromMap(doc.data(), fallbackShopId: doc.id),
    ];
  }

  @override
  Future<int?> fetchInvoicePrice() async {
    final doc = await _invoiceSettings.get();
    return (doc.data()?['pricePerQr'] as num?)?.toInt();
  }

  @override
  Future<void> setInvoicePrice(int price) =>
      _invoiceSettings.set({'pricePerQr': price});

  @override
  Future<Invoice> createInvoice({
    required Assignment assignment,
    required String clientName,
    required String clientPhone,
    required String clientAddress,
    required int amount,
    required String createdByUid,
    required String createdByName,
  }) async {
    final invoiceRef = _invoices.doc(assignment.shopId);
    final assignmentRef = _assignments.doc(assignment.shopId);

    // One transaction: check the QR has no invoice yet, take the next number,
    // and write both, so two taps (or two people) can never share a number.
    await _db.runTransaction((tx) async {
      final existing = await tx.get(invoiceRef);
      if (existing.exists) return;

      // The sale date and sales person come from the stored assignment, not
      // from what the screen happened to hold.
      final current = await tx.get(assignmentRef);
      final soldAt = current.data()?['soldAt'];
      if (!current.exists || soldAt == null) {
        throw const SalesException(
          'Only a QR that has been set up for a client can be invoiced.',
        );
      }

      final counter = await tx.get(_invoiceCounter);
      final next = ((counter.data()?['last'] as num?)?.toInt() ?? 0) + 1;

      // lastShopId lets the security rules check that every number taken is
      // used by exactly one new invoice.
      tx.set(_invoiceCounter, {'last': next, 'lastShopId': assignment.shopId});
      tx.set(invoiceRef, {
        'shopId': assignment.shopId,
        'number': next,
        'qrCode': current.data()!['qrCode'],
        'clientName': clientName,
        'clientPhone': clientPhone,
        'clientAddress': clientAddress,
        'amount': amount,
        'issuedAt': FieldValue.serverTimestamp(),
        'soldAt': soldAt,
        'soldByName': current.data()!['assignedToName'],
        'soldByUid': current.data()!['assignedTo'],
        'createdByUid': createdByUid,
        'createdByName': createdByName,
      });
    });

    // Read it back so the server's own issue date is what gets printed.
    final saved = await invoiceRef.get();
    final data = saved.data();
    if (data == null) {
      throw const SalesException('The invoice could not be saved. Try again.');
    }
    return Invoice.fromMap(data, fallbackShopId: assignment.shopId);
  }

  static int _codeNumber(String code) =>
      int.tryParse(code.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1 << 30;
}

class _IdentityResult {
  final String? localId;
  final String? error;
  const _IdentityResult({this.localId, this.error});
}

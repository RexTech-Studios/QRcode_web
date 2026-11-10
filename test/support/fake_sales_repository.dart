import 'package:reviewqr_admin/models/assignment_model.dart';
import 'package:reviewqr_admin/models/invoice_model.dart';
import 'package:reviewqr_admin/models/qr_code_model.dart';
import 'package:reviewqr_admin/models/sales_user_model.dart';
import 'package:reviewqr_admin/models/shop_model.dart';
import 'package:reviewqr_admin/services/sales_repository.dart';

/// An in-memory [SalesRepository] for tests. It records what was written and
/// can be told to fail, so providers and screens run without Firebase.
class FakeSalesRepository implements SalesRepository {
  final List<SalesUser> users;
  final List<Assignment> assignments;
  final Map<String, ShopModel> shops;

  Object? saveError;
  Object? createError;
  Object? manageError;
  int fetchAllAssignmentsCalls = 0;
  final List<String> calls = [];
  List<QRCodeModel> lastAssigned = [];
  ({String name, String url, bool hadSoldAt})? lastSetup;

  FakeSalesRepository({
    List<SalesUser>? users,
    List<Assignment>? assignments,
    Map<String, ShopModel>? shops,
  }) : users = users ?? [],
       assignments = assignments ?? [],
       shops = shops ?? {};

  @override
  Future<SalesUser?> fetchUser(String uid) async {
    for (final u in users) {
      if (u.uid == uid) return u;
    }
    return null;
  }

  @override
  Future<List<SalesUser>> fetchUsers() async => List.of(users);

  @override
  Future<SalesUser> createSalesAccount({
    required String name,
    required String email,
    required String password,
  }) async {
    calls.add('create:$email');
    if (createError != null) throw createError!;
    final user = SalesUser(
      uid: 'uid-${users.length + 1}',
      name: name.trim(),
      email: email.trim(),
    );
    users.add(user);
    return user;
  }

  @override
  Future<void> setUserActive(String uid, bool active) async {
    calls.add('active:$uid:$active');
    final i = users.indexWhere((u) => u.uid == uid);
    if (i >= 0) users[i] = users[i].copyWith(active: active);
  }

  @override
  Future<void> sendPasswordReset(String email) async =>
      calls.add('reset:$email');

  @override
  Future<List<Assignment>> fetchAllAssignments() async {
    fetchAllAssignmentsCalls++;
    return List.of(assignments);
  }

  @override
  Future<List<Assignment>> fetchAssignmentsFor(String uid) async =>
      assignments.where((a) => a.assignedTo == uid).toList();

  @override
  Future<void> assign(List<QRCodeModel> qrCodes, SalesUser rep) async {
    calls.add('assign:${qrCodes.length}');
    lastAssigned = List.of(qrCodes);
    for (final qr in qrCodes) {
      assignments.removeWhere((a) => a.shopId == qr.shopId);
      assignments.add(
        Assignment(
          shopId: qr.shopId,
          qrId: qr.qrId,
          qrCode: qr.qrCode,
          assignedTo: rep.uid,
          assignedToName: rep.name,
          assignedAt: DateTime(2026, 11, 9),
        ),
      );
    }
  }

  @override
  Future<void> unassign(String shopId) async {
    calls.add('unassign:$shopId');
    assignments.removeWhere((a) => a.shopId == shopId);
  }

  @override
  Future<void> unassignMany(List<String> shopIds) async {
    calls.add('unassignMany:${shopIds.join(',')}');
    if (manageError != null) throw manageError!;
    assignments.removeWhere((a) => shopIds.contains(a.shopId));
  }

  @override
  Future<void> reassign(List<Assignment> items, SalesUser to) async {
    calls.add('reassign:${items.map((a) => a.shopId).join(',')}->${to.uid}');
    if (manageError != null) throw manageError!;
    for (final item in items) {
      final i = assignments.indexWhere((a) => a.shopId == item.shopId);
      if (i >= 0) {
        assignments[i] = assignments[i].copyWith(
          assignedTo: to.uid,
          assignedToName: to.name,
        );
      }
    }
  }

  @override
  Future<void> renameSalesUser({
    required String uid,
    required String name,
    required List<String> assignmentShopIds,
  }) async {
    calls.add('rename:$uid:$name:${assignmentShopIds.join(',')}');
    if (manageError != null) throw manageError!;
    final i = users.indexWhere((u) => u.uid == uid);
    if (i >= 0) users[i] = users[i].copyWith(name: name);
    for (var j = 0; j < assignments.length; j++) {
      if (assignments[j].assignedTo == uid) {
        assignments[j] = assignments[j].copyWith(assignedToName: name);
      }
    }
  }

  @override
  Future<void> deleteSalesUser({
    required String uid,
    required List<String> unsoldShopIds,
  }) async {
    calls.add('deleteUser:$uid:${unsoldShopIds.join(',')}');
    if (manageError != null) throw manageError!;
    assignments.removeWhere((a) => unsoldShopIds.contains(a.shopId));
    users.removeWhere((u) => u.uid == uid);
  }

  @override
  Future<void> setLocked(String shopId, bool locked) async {
    calls.add('locked:$shopId:$locked');
    final i = assignments.indexWhere((a) => a.shopId == shopId);
    if (i >= 0) assignments[i] = assignments[i].copyWith(locked: locked);
  }

  @override
  Future<ShopModel?> fetchShop(String shopId) async => shops[shopId];

  @override
  Future<void> repSaveSetup({
    required Assignment assignment,
    required String shopName,
    required String reviewUrl,
  }) async {
    calls.add('setup:${assignment.shopId}');
    if (saveError != null) throw saveError!;
    lastSetup = (
      name: shopName,
      url: reviewUrl,
      hadSoldAt: assignment.soldAt != null,
    );
  }

  Object? sheetSaveError;
  final List<({String shopId, String url})> savedSheets = [];

  @override
  Future<void> repSaveSheetUrl({
    required String shopId,
    required String sheetUrl,
  }) async {
    calls.add('sheet:$shopId');
    if (sheetSaveError != null) throw sheetSaveError!;
    savedSheets.add((shopId: shopId, url: sheetUrl));
  }

  // ---- Invoices ----

  final List<Invoice> invoices = [];
  int? invoicePrice;
  Object? invoiceError;
  ({String uid, String name})? lastInvoiceCreator;

  @override
  Future<List<Invoice>> fetchInvoices() async => List.of(invoices);

  @override
  Future<List<Invoice>> fetchInvoicesFor(String uid) async =>
      invoices.where((i) => i.soldByUid == uid).toList();

  @override
  Future<int?> fetchInvoicePrice() async => invoicePrice;

  @override
  Future<void> setInvoicePrice(int price) async {
    calls.add('price:$price');
    invoicePrice = price;
  }

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
    calls.add('invoice:${assignment.shopId}:$amount');
    lastInvoiceCreator = (uid: createdByUid, name: createdByName);
    if (invoiceError != null) throw invoiceError!;
    for (final i in invoices) {
      if (i.shopId == assignment.shopId) return i;
    }
    final invoice = Invoice(
      shopId: assignment.shopId,
      number: invoices.length + 1,
      qrCode: assignment.qrCode,
      clientName: clientName,
      clientPhone: clientPhone,
      clientAddress: clientAddress,
      amount: amount,
      issuedAt: DateTime(2026, 11, 10),
      soldAt: assignment.soldAt,
      soldByName: assignment.assignedToName,
      soldByUid: assignment.assignedTo,
      createdByUid: createdByUid,
      createdByName: createdByName,
    );
    invoices.add(invoice);
    return invoice;
  }
}

QRCodeModel qrFor(int number) => QRCodeModel(
  qrId: 'qr-id-$number',
  shopId: 'shop-$number',
  qrContent: 'https://example.test/#/review/shop-$number',
  qrLabel: 'Review us on Google',
  qrStyle: QRStyle.classic,
  createdAt: DateTime(2026, 11, 1),
  qrCode: 'QR$number',
);

ShopModel shopFor(int number, {String? sheetsUrl}) => ShopModel(
  shopId: 'shop-$number',
  shopName: 'Demo QR$number',
  googleReviewUrl: 'https://www.google.com/maps/place/Rextech',
  createdAt: DateTime(2026, 11, 1),
  googleSheetsUrl: sheetsUrl,
  qrCode: 'QR$number',
);

Assignment assignmentFor(
  int number, {
  String uid = 'u1',
  String name = 'Ravi',
  bool locked = false,
  DateTime? soldAt,
}) => Assignment(
  shopId: 'shop-$number',
  qrId: 'qr-id-$number',
  qrCode: 'QR$number',
  assignedTo: uid,
  assignedToName: name,
  assignedAt: DateTime(2026, 11, 2),
  locked: locked,
  soldAt: soldAt,
);

const ravi = SalesUser(uid: 'u1', name: 'Ravi', email: 'ravi@example.com');
const anu = SalesUser(uid: 'u2', name: 'Anu', email: 'anu@example.com');

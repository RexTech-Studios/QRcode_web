import '../utils/date_parse.dart';

/// The invoice for one sold QR, stored at `invoices/{shopId}`. The doc id is
/// the shop id, so a QR can only ever be invoiced once. The admin can see all
/// of them; a sales person can see and create only the ones for QR codes
/// assigned to them. Visitors have no access.
class Invoice {
  final String shopId;

  /// Running number, 1, 2, 3... shown as "FSQ-0001".
  final int number;
  final String qrCode;
  final String clientName;
  final String clientPhone;
  final String clientAddress;

  /// Whole rupees.
  final int amount;
  final DateTime? issuedAt;
  final DateTime? soldAt;
  final String soldByName;

  /// The sales person the QR was assigned to (empty on early invoices).
  final String soldByUid;

  /// Who made the invoice: the admin, or the sales person themselves.
  final String createdByUid;
  final String createdByName;

  const Invoice({
    required this.shopId,
    required this.number,
    required this.qrCode,
    required this.clientName,
    this.clientPhone = '',
    this.clientAddress = '',
    required this.amount,
    this.issuedAt,
    this.soldAt,
    this.soldByName = '',
    this.soldByUid = '',
    this.createdByUid = '',
    this.createdByName = '',
  });

  /// True when the sales person issued this invoice themselves. Anything else
  /// (including invoices from before this was recorded) came from the admin.
  bool get createdByRep => createdByUid.isNotEmpty && createdByUid == soldByUid;

  /// "Admin" or the sales person's name, for lists and the CSV.
  String get createdByLabel =>
      createdByRep ? (createdByName.isEmpty ? soldByName : createdByName) : 'Admin';

  String get numberText => formatInvoiceNumber(number);

  factory Invoice.fromMap(Map<String, dynamic> map, {String? fallbackShopId}) {
    return Invoice(
      shopId: (map['shopId'] as String?) ?? fallbackShopId ?? '',
      number: (map['number'] as num?)?.toInt() ?? 0,
      qrCode: (map['qrCode'] as String?) ?? '',
      clientName: (map['clientName'] as String?) ?? '',
      clientPhone: (map['clientPhone'] as String?) ?? '',
      clientAddress: (map['clientAddress'] as String?) ?? '',
      amount: (map['amount'] as num?)?.toInt() ?? 0,
      issuedAt: parseDate(map['issuedAt']),
      soldAt: parseDate(map['soldAt']),
      soldByName: (map['soldByName'] as String?) ?? '',
      soldByUid: (map['soldByUid'] as String?) ?? '',
      createdByUid: (map['createdByUid'] as String?) ?? '',
      createdByName: (map['createdByName'] as String?) ?? '',
    );
  }
}

/// 1 -> "FSQ-0001". Numbers past 9999 simply get longer.
String formatInvoiceNumber(int number) =>
    'FSQ-${number.toString().padLeft(4, '0')}';

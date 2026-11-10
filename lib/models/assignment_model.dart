import '../utils/date_parse.dart';

/// Which sales person holds one shop's QR sticker, stored at
/// `assignments/{shopId}` (the doc id is the shop id).
///
/// A sales person may edit the shop once. Saving sets [locked]; only the admin
/// can unlock it again. [soldAt] is set on the first save and never changes,
/// so "sold" means [soldAt] is not null.
class Assignment {
  final String shopId;
  final String qrId;
  final String qrCode;
  final String assignedTo;
  final String assignedToName;
  final DateTime? assignedAt;
  final bool locked;
  final DateTime? soldAt;
  final DateTime? lastEditedAt;

  const Assignment({
    required this.shopId,
    required this.qrId,
    required this.qrCode,
    required this.assignedTo,
    required this.assignedToName,
    this.assignedAt,
    this.locked = false,
    this.soldAt,
    this.lastEditedAt,
  });

  bool get isSold => soldAt != null;

  /// What the sales person can do with it right now.
  bool get repCanEdit => !locked;

  factory Assignment.fromMap(
    Map<String, dynamic> map, {
    String? fallbackShopId,
  }) {
    return Assignment(
      shopId: (map['shopId'] as String?) ?? fallbackShopId ?? '',
      qrId: (map['qrId'] as String?) ?? '',
      qrCode: (map['qrCode'] as String?) ?? '',
      assignedTo: (map['assignedTo'] as String?) ?? '',
      assignedToName: (map['assignedToName'] as String?) ?? '',
      assignedAt: parseDate(map['assignedAt']),
      // Fail closed: only an explicit false means the person may still edit.
      locked: map['locked'] != false,
      soldAt: parseDate(map['soldAt']),
      lastEditedAt: parseDate(map['lastEditedAt']),
    );
  }

  Assignment copyWith({
    bool? locked,
    DateTime? soldAt,
    DateTime? lastEditedAt,
    String? assignedTo,
    String? assignedToName,
    DateTime? assignedAt,
  }) => Assignment(
    shopId: shopId,
    qrId: qrId,
    qrCode: qrCode,
    assignedTo: assignedTo ?? this.assignedTo,
    assignedToName: assignedToName ?? this.assignedToName,
    assignedAt: assignedAt ?? this.assignedAt,
    locked: locked ?? this.locked,
    soldAt: soldAt ?? this.soldAt,
    lastEditedAt: lastEditedAt ?? this.lastEditedAt,
  );
}

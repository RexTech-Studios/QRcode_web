import 'package:hive/hive.dart';

part 'qr_code_model.g.dart';

@HiveType(typeId: 1)
enum QRStyle {
  @HiveField(0)
  classic,
  @HiveField(1)
  rounded,
  @HiveField(2)
  dotsGreen,
  @HiveField(3)
  minimal,
}

@HiveType(typeId: 2)
class QRCodeModel extends HiveObject {
  @HiveField(0)
  String qrId;

  @HiveField(1)
  String shopId;

  @HiveField(2)
  String qrContent;

  @HiveField(3)
  String qrLabel;

  @HiveField(4)
  QRStyle qrStyle;

  @HiveField(5)
  DateTime createdAt;

  @HiveField(6)
  DateTime? updatedAt;

  /// Short human-readable identifier (e.g. "QR1", "QR2") so a printed QR
  /// sticker can be identified without reading the full UUID. Assigned once
  /// when the QR is created and never changes, even if the shop it points
  /// to is later edited.
  @HiveField(7)
  String qrCode;

  QRCodeModel({
    required this.qrId,
    required this.shopId,
    required this.qrContent,
    required this.qrLabel,
    required this.qrStyle,
    required this.createdAt,
    this.updatedAt,
    required this.qrCode,
  });

  Map<String, dynamic> toMap() {
    return {
      'qrId': qrId,
      'shopId': shopId,
      'qrContent': qrContent,
      'qrLabel': qrLabel,
      'qrStyle': qrStyle.name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'qrCode': qrCode,
    };
  }

  factory QRCodeModel.fromMap(Map<String, dynamic> map) {
    return QRCodeModel(
      qrId: map['qrId'] as String,
      shopId: map['shopId'] as String,
      qrContent: map['qrContent'] as String,
      qrLabel: map['qrLabel'] as String,
      qrStyle: QRStyle.values.firstWhere(
        (s) => s.name == map['qrStyle'],
        orElse: () => QRStyle.classic,
      ),
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'] as String)
          : null,
      qrCode: (map['qrCode'] as String?) ?? '',
    );
  }
}

import 'package:hive/hive.dart';

part 'shop_model.g.dart';

@HiveType(typeId: 0)
class ShopModel extends HiveObject {
  @HiveField(0)
  String shopId;

  @HiveField(1)
  String shopName;

  @HiveField(2)
  String? shopLogo;

  @HiveField(3)
  String googleReviewUrl;

  @HiveField(4)
  DateTime createdAt;

  @HiveField(5)
  String? whatsappNumber;

  @HiveField(6)
  String? notificationEmail;

  @HiveField(7)
  bool emailNotificationsEnabled;

  @HiveField(8)
  String? googleSheetsUrl;

  ShopModel({
    required this.shopId,
    required this.shopName,
    this.shopLogo,
    required this.googleReviewUrl,
    required this.createdAt,
    this.whatsappNumber,
    this.notificationEmail,
    this.emailNotificationsEnabled = false,
    this.googleSheetsUrl,
  });

  Map<String, dynamic> toMap() {
    return {
      'shopId': shopId,
      'shopName': shopName,
      'shopLogo': shopLogo,
      'googleReviewUrl': googleReviewUrl,
      'createdAt': createdAt.toIso8601String(),
      'whatsappNumber': whatsappNumber,
      'notificationEmail': notificationEmail,
      'emailNotificationsEnabled': emailNotificationsEnabled,
      'googleSheetsUrl': googleSheetsUrl,
    };
  }

  factory ShopModel.fromMap(Map<String, dynamic> map) {
    return ShopModel(
      shopId: map['shopId'] as String,
      shopName: map['shopName'] as String,
      shopLogo: map['shopLogo'] as String?,
      googleReviewUrl: map['googleReviewUrl'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      whatsappNumber: map['whatsappNumber'] as String?,
      notificationEmail: map['notificationEmail'] as String?,
      emailNotificationsEnabled:
          (map['emailNotificationsEnabled'] as bool?) ?? false,
      googleSheetsUrl: map['googleSheetsUrl'] as String?,
    );
  }
}

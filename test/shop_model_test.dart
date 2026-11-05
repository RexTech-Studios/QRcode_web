import 'package:flutter_test/flutter_test.dart';
import 'package:reviewqr_admin/models/shop_model.dart';

void main() {
  ShopModel shop({String? qrCode}) => ShopModel(
    shopId: 's1',
    shopName: 'Shop',
    googleReviewUrl: 'https://g.page/r/abc/review',
    createdAt: DateTime(2026, 1, 1),
    qrCode: qrCode,
  );

  group('ShopModel qrCode', () {
    test('round-trips through the Firestore map', () {
      final restored = ShopModel.fromMap(shop(qrCode: 'QR7').toMap());
      expect(restored.qrCode, 'QR7');
    });

    test('a doc from before the field existed still parses', () {
      final map = shop().toMap()..remove('qrCode');
      expect(ShopModel.fromMap(map).qrCode, isNull);
    });

    test('an unset code is left out, so a merged save cannot erase it', () {
      expect(shop().toMap().containsKey('qrCode'), isFalse);
    });
  });
}

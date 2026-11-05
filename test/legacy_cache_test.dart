import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:reviewqr_admin/models/qr_code_model.dart';
import 'package:reviewqr_admin/models/shop_model.dart';

/// Writes a shop exactly as the adapter did before fields 5, 6 and 7 were
/// removed and field 9 was added, so these bytes match what an existing
/// browser has on disk.
class _LegacyShopAdapter extends TypeAdapter<ShopModel> {
  @override
  final int typeId = 0;

  @override
  ShopModel read(BinaryReader reader) => throw UnimplementedError();

  @override
  void write(BinaryWriter writer, ShopModel obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.shopId)
      ..writeByte(1)
      ..write(obj.shopName)
      ..writeByte(2)
      ..write(obj.shopLogo)
      ..writeByte(3)
      ..write(obj.googleReviewUrl)
      ..writeByte(4)
      ..write(obj.createdAt)
      ..writeByte(5)
      ..write('whatsapp-placeholder')
      ..writeByte(6)
      ..write('contact-placeholder')
      ..writeByte(7)
      ..write(true)
      ..writeByte(8)
      ..write(obj.googleSheetsUrl);
  }
}

/// Writes a QR as the adapter did before field 7 (qrCode) existed.
class _LegacyQrAdapter extends TypeAdapter<QRCodeModel> {
  @override
  final int typeId = 2;

  @override
  QRCodeModel read(BinaryReader reader) => throw UnimplementedError();

  @override
  void write(BinaryWriter writer, QRCodeModel obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.qrId)
      ..writeByte(1)
      ..write(obj.shopId)
      ..writeByte(2)
      ..write(obj.qrContent)
      ..writeByte(3)
      ..write(obj.qrLabel)
      ..writeByte(4)
      ..write(obj.qrStyle)
      ..writeByte(5)
      ..write(obj.createdAt)
      ..writeByte(6)
      ..write(obj.updatedAt);
  }
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_legacy_test');
    Hive.init(dir.path);
    Hive.registerAdapter(QRStyleAdapter(), override: true);
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('a shop cached by the old build opens and reads with the new adapter', () async {
    Hive.registerAdapter<ShopModel>(_LegacyShopAdapter(), override: true);
    final oldBox = await Hive.openBox<ShopModel>('shops');
    await oldBox.put(
      's1',
      ShopModel(
        shopId: 's1',
        shopName: 'Old Shop',
        googleReviewUrl: 'https://g.page/r/abc/review',
        createdAt: DateTime(2026, 1, 1),
        googleSheetsUrl: 'https://docs.google.com/spreadsheets/d/abc',
      ),
    );
    await oldBox.close();

    Hive.registerAdapter<ShopModel>(ShopModelAdapter(), override: true);
    final box = await Hive.openBox<ShopModel>('shops');
    final shop = box.get('s1')!;

    expect(shop.shopName, 'Old Shop');
    expect(shop.googleSheetsUrl, 'https://docs.google.com/spreadsheets/d/abc');
    expect(shop.qrCode, isNull);

    // Re-saving drops the retired fields and adds the new one cleanly.
    shop.qrCode = 'QR1';
    await box.put('s1', shop);
    await box.close();
    final reopened = await Hive.openBox<ShopModel>('shops');
    expect(reopened.get('s1')!.qrCode, 'QR1');
  });

  test('a QR cached before the qrCode field existed opens with an empty code', () async {
    Hive.registerAdapter<QRCodeModel>(_LegacyQrAdapter(), override: true);
    final oldBox = await Hive.openBox<QRCodeModel>('qrs');
    await oldBox.put(
      'q1',
      QRCodeModel(
        qrId: 'q1',
        shopId: 's1',
        qrContent: 'https://qrcode-16b68.web.app/#/review/s1',
        qrLabel: 'Label',
        qrStyle: QRStyle.classic,
        createdAt: DateTime(2026, 1, 1),
        qrCode: 'ignored by the legacy adapter',
      ),
    );
    await oldBox.close();

    Hive.registerAdapter<QRCodeModel>(QRCodeModelAdapter(), override: true);
    final box = await Hive.openBox<QRCodeModel>('qrs');
    expect(box.get('q1')!.qrCode, '');
  });
}

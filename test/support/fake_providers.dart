import 'package:reviewqr_admin/models/qr_code_model.dart';
import 'package:reviewqr_admin/models/shop_model.dart';
import 'package:reviewqr_admin/providers/qr_provider.dart';
import 'package:reviewqr_admin/providers/shop_provider.dart';

/// A [QrProvider] that serves a fixed list, so screens can be tested without
/// Hive or Firebase.
class FakeQrProvider extends QrProvider {
  FakeQrProvider(this._qrs);
  final List<QRCodeModel> _qrs;

  @override
  List<QRCodeModel> get qrCodes => List.unmodifiable(_qrs);
}

/// A [ShopProvider] that serves a fixed list.
class FakeShopProvider extends ShopProvider {
  FakeShopProvider(this._shops);
  final List<ShopModel> _shops;

  @override
  List<ShopModel> get shops => List.unmodifiable(_shops);
}

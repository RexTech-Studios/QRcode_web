import 'package:uuid/uuid.dart';

/// Generates unique ids and builds the deep-link content encoded in each
/// shop's QR code. Scanning the code opens the customer-facing review page
/// at `/#/review/{shopId}` for this same web app.
class QrService {
  QrService._();

  static const Uuid _uuid = Uuid();

  static String newShopId() => _uuid.v4();

  static String newQrId() => _uuid.v4();

  /// Builds an absolute URL to the customer review page for [shopId],
  /// based on the app's own current origin (works for any deployment host).
  static String buildReviewPageUrl(String shopId, {String? baseOrigin}) {
    final origin = baseOrigin ?? _currentOrigin();
    return '$origin/#/review/$shopId';
  }

  static String _currentOrigin() {
    return 'https://qrcode-16b68.web.app';
  }
}

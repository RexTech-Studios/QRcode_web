import 'package:uuid/uuid.dart';

import '../utils/app_config.dart';

/// Generates unique ids and builds the deep-link content encoded in each
/// shop's QR code. Scanning the code opens the customer-facing review page
/// at `/#/review/{shopId}` for this same web app.
class QrService {
  QrService._();

  static const Uuid _uuid = Uuid();

  static String newShopId() => _uuid.v4();

  static String newQrId() => _uuid.v4();

  /// Builds an absolute URL to the customer review page for [shopId].
  static String buildReviewPageUrl(String shopId) => AppConfig.reviewUrl(shopId);
}

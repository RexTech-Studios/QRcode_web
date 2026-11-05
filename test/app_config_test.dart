import 'package:flutter_test/flutter_test.dart';
import 'package:reviewqr_admin/services/qr_service.dart';
import 'package:reviewqr_admin/utils/app_config.dart';

void main() {
  test('QR URL is byte-for-byte what printed stickers already encode', () {
    expect(
      QrService.buildReviewPageUrl('abc-123'),
      'https://qrcode-16b68.web.app/#/review/abc-123',
    );
  });

  test('isAdmin only accepts the configured uid', () {
    expect(AppConfig.isAdmin(AppConfig.adminUid), isTrue);
    expect(AppConfig.isAdmin('someone-else'), isFalse);
    expect(AppConfig.isAdmin(''), isFalse);
    expect(AppConfig.isAdmin(null), isFalse);
  });
}

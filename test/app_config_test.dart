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

  test('the new domain is switched off', () {
    expect(AppConfig.useNewDomain, isFalse);
  });

  test('reviewUrl gives today\'s URL with the switch off', () {
    expect(
      AppConfig.reviewUrl('abc-123', newDomain: false),
      'https://qrcode-16b68.web.app/#/review/abc-123',
    );
  });

  test('reviewUrl gives the short link with the switch on', () {
    expect(
      AppConfig.reviewUrl('abc-123', newDomain: true),
      'https://fullstarqr.com/r/abc-123',
    );
  });

  test('isAdmin only accepts the configured uid', () {
    expect(AppConfig.isAdmin(AppConfig.adminUid), isTrue);
    expect(AppConfig.isAdmin('someone-else'), isFalse);
    expect(AppConfig.isAdmin(''), isFalse);
    expect(AppConfig.isAdmin(null), isFalse);
  });
}

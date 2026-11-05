import 'package:flutter_test/flutter_test.dart';
import 'package:reviewqr_admin/utils/app_routes.dart';

void main() {
  group('reviewShopId', () {
    test('accepts a well-formed review route', () {
      expect(reviewShopId('/review/abc-123'), 'abc-123');
    });

    test('ignores a query string', () {
      expect(reviewShopId('/review/abc-123?utm=x'), 'abc-123');
    });

    test('rejects malformed review routes', () {
      expect(reviewShopId('/review'), isNull);
      expect(reviewShopId('/review/'), isNull);
      expect(reviewShopId('/review/a/b'), isNull);
    });

    test('rejects everything else', () {
      expect(reviewShopId('/'), isNull);
      expect(reviewShopId('/settings'), isNull);
    });
  });

  group('isReviewPath sends malformed links to "Link not found"', () {
    test('is true for every /review route', () {
      expect(isReviewPath('/review'), isTrue);
      expect(isReviewPath('/review/'), isTrue);
      expect(isReviewPath('/review/a/b'), isTrue);
      expect(isReviewPath('/review/abc'), isTrue);
    });

    test('is false for the admin fallback routes', () {
      expect(isReviewPath('/'), isFalse);
      expect(isReviewPath('/reviews'), isFalse);
      expect(isReviewPath('/typo'), isFalse);
    });
  });

  group('isReviewLocation', () {
    test('detects a hash review URL, as encoded in printed QR codes', () {
      expect(
        isReviewLocation(Uri.parse('https://qrcode-16b68.web.app/#/review/abc')),
        isTrue,
      );
    });

    test('still detects it under a base path', () {
      expect(
        isReviewLocation(Uri.parse('https://example.test/app/#/review/abc')),
        isTrue,
      );
    });

    test('is false for the dashboard', () {
      expect(isReviewLocation(Uri.parse('https://qrcode-16b68.web.app/')), isFalse);
      expect(isReviewLocation(Uri.parse('https://qrcode-16b68.web.app/#/')), isFalse);
    });
  });
}

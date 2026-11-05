import 'package:flutter_test/flutter_test.dart';
import 'package:reviewqr_admin/utils/validators.dart';

void main() {
  group('Validators.isSafeReviewRedirect', () {
    test('accepts the https links the Generate QR form accepts', () {
      for (final url in [
        'https://g.page/r/abc/review',
        'https://maps.app.goo.gl/abc123',
        'https://goo.gl/maps/abc',
        'https://www.google.com/maps/place/Some+Shop',
        'https://maps.google.com/?cid=123',
        'https://search.google.com/local/writereview?placeid=abc',
      ]) {
        expect(Validators.isSafeReviewRedirect(url), isTrue, reason: url);
      }
    });

    test('ignores surrounding whitespace, like the form check', () {
      expect(Validators.isSafeReviewRedirect('  https://g.page/r/abc/review '), isTrue);
    });

    test('rejects http even on an allowed host', () {
      expect(Validators.isValidGoogleMapsUrl('http://g.page/r/abc/review'), isTrue);
      expect(Validators.isSafeReviewRedirect('http://g.page/r/abc/review'), isFalse);
    });

    test('rejects hosts that are not Google', () {
      for (final url in [
        'https://evil.example/phish',
        'https://g.page.evil.example/r/abc',
        'https://evilg.page/r/abc',
        'https://notgoogle.com/maps',
        'https://google.com.evil.example/maps',
      ]) {
        expect(Validators.isSafeReviewRedirect(url), isFalse, reason: url);
      }
    });

    test('is not fooled by userinfo that looks like an allowed host', () {
      expect(Validators.isSafeReviewRedirect('https://g.page@evil.example/x'), isFalse);
      expect(Validators.isSafeReviewRedirect('https://google.com:x@evil.example/'), isFalse);
    });

    test('rejects other schemes and junk without throwing', () {
      for (final url in [
        '',
        '   ',
        'not a url',
        'javascript:alert(1)',
        'data:text/html,hi',
        '//g.page/r/abc',
        'g.page/r/abc',
        'https://',
        'https://[bad',
      ]) {
        expect(Validators.isSafeReviewRedirect(url), isFalse, reason: url);
      }
    });

    test('never accepts what the form check rejects', () {
      for (final url in ['https://example.com', 'ftp://g.page/x', 'https://evil.example']) {
        expect(Validators.isValidGoogleMapsUrl(url), isFalse, reason: url);
        expect(Validators.isSafeReviewRedirect(url), isFalse, reason: url);
      }
    });

    test('documents a limit shared with the form: fragments are rejected', () {
      const url = 'https://www.google.com/search?q=shop#lrd=0x1,3';
      expect(Validators.isValidGoogleMapsUrl(url), isFalse);
      expect(Validators.isSafeReviewRedirect(url), isFalse);
    });
  });
}

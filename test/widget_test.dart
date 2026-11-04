// Basic sanity test. A full widget test for ReviewQrAdminApp requires
// Hive/Firebase to be initialized first (see main()), so it's covered by
// manual/integration testing for now.

import 'package:flutter_test/flutter_test.dart';
import 'package:reviewqr_admin/utils/validators.dart';

void main() {
  test('Validators accepts known Google Maps review link hosts', () {
    expect(Validators.isValidGoogleMapsUrl('https://g.page/r/RextechCafe/review'), isTrue);
    expect(Validators.isValidGoogleMapsUrl('https://maps.app.goo.gl/abc123'), isTrue);
    expect(Validators.isValidGoogleMapsUrl('not a url'), isFalse);
    expect(Validators.isValidGoogleMapsUrl('https://example.com'), isFalse);
  });
}

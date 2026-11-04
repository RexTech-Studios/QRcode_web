import 'dart:typed_data';

void downloadBytes(Uint8List bytes, String fileName) {
  // No-op on non-web platforms; downloading a generated QR PNG is a
  // Flutter Web feature for this admin dashboard.
}

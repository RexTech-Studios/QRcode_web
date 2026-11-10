import 'package:flutter/foundation.dart';

/// Used where there is no browser to download into (tests, mobile builds).
void downloadCsv({required String content, required String fileName}) {
  debugPrint('downloadCsv: only supported on web ($fileName)');
}

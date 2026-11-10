/// Turns what the admin types ("121-140, 145, QR150") into QR codes
/// ("QR121" ... "QR140", "QR145", "QR150"). Order is kept and duplicates are
/// dropped. Anything that can't be read is reported in [errors] rather than
/// silently skipped.
class QrNumberParseResult {
  final List<String> codes;
  final List<String> errors;

  const QrNumberParseResult(this.codes, this.errors);

  bool get isEmpty => codes.isEmpty && errors.isEmpty;
}

final RegExp _token = RegExp(
  r'^(?:qr)?(\d+)(?:-(?:qr)?(\d+))?$',
  caseSensitive: false,
);

QrNumberParseResult parseQrNumbers(String input, {int maxCodes = 500}) {
  final normalized = input
      .trim()
      .replaceAll(RegExp(r'\s*[-–—]\s*'), '-')
      .replaceAll(RegExp(r'qr\s+(?=\d)', caseSensitive: false), 'qr');
  if (normalized.isEmpty) return const QrNumberParseResult([], []);

  final codes = <String>[];
  final seen = <String>{};
  final errors = <String>[];

  void add(int number) {
    final code = 'QR$number';
    if (seen.add(code)) codes.add(code);
  }

  for (final raw in normalized.split(RegExp(r'[\s,;]+'))) {
    if (raw.isEmpty) continue;
    final match = _token.firstMatch(raw);
    if (match == null) {
      errors.add('"$raw" is not a QR number.');
      continue;
    }
    final start = int.parse(match.group(1)!);
    final endText = match.group(2);
    if (endText == null) {
      add(start);
      continue;
    }
    final end = int.parse(endText);
    if (end < start) {
      errors.add('"$raw" is backwards. Write the smaller number first.');
      continue;
    }
    if (end - start + 1 > maxCodes) {
      errors.add('"$raw" covers more than $maxCodes QR codes.');
      continue;
    }
    for (var n = start; n <= end; n++) {
      add(n);
    }
  }

  if (codes.length > maxCodes) {
    errors.add('That is more than $maxCodes QR codes at once. Split it up.');
    return QrNumberParseResult(codes.sublist(0, maxCodes), errors);
  }
  return QrNumberParseResult(codes, errors);
}

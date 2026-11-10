import 'package:flutter_test/flutter_test.dart';
import 'package:reviewqr_admin/utils/qr_number_parser.dart';

void main() {
  test('reads single numbers with or without the QR prefix', () {
    final r = parseQrNumbers('121, QR122 qr123');
    expect(r.codes, ['QR121', 'QR122', 'QR123']);
    expect(r.errors, isEmpty);
  });

  test('expands ranges, with spaces and en dashes', () {
    expect(parseQrNumbers('121-124').codes, [
      'QR121',
      'QR122',
      'QR123',
      'QR124',
    ]);
    expect(parseQrNumbers('QR121 - QR123').codes, ['QR121', 'QR122', 'QR123']);
    expect(parseQrNumbers('121–122').codes, ['QR121', 'QR122']);
  });

  test('mixes ranges and singles, keeps order, drops duplicates', () {
    final r = parseQrNumbers('130, 121-123, 122, 130');
    expect(r.codes, ['QR130', 'QR121', 'QR122', 'QR123']);
  });

  test('accepts commas, semicolons, spaces and new lines as separators', () {
    expect(parseQrNumbers('1,2;3 4\n5').codes, [
      'QR1',
      'QR2',
      'QR3',
      'QR4',
      'QR5',
    ]);
  });

  test('normalises leading zeros so QR007 and 7 are the same code', () {
    expect(parseQrNumbers('007').codes, ['QR7']);
  });

  test('reports what it cannot read instead of skipping it silently', () {
    final r = parseQrNumbers('121, abc, 12x');
    expect(r.codes, ['QR121']);
    expect(r.errors, hasLength(2));
    expect(r.errors.first, contains('abc'));
  });

  test('rejects a backwards range', () {
    final r = parseQrNumbers('140-121');
    expect(r.codes, isEmpty);
    expect(r.errors.single, contains('backwards'));
  });

  test('caps how many codes one entry can create', () {
    final r = parseQrNumbers('1-5000', maxCodes: 500);
    expect(r.codes, isEmpty);
    expect(r.errors, isNotEmpty);

    final many = parseQrNumbers('1-300, 301-600', maxCodes: 500);
    expect(many.codes, hasLength(500));
    expect(many.errors, isNotEmpty);
  });

  test('empty input gives an empty result, not an error', () {
    final r = parseQrNumbers('   ');
    expect(r.isEmpty, isTrue);
  });
}

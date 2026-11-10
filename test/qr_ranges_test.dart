import 'package:flutter_test/flutter_test.dart';
import 'package:reviewqr_admin/utils/qr_ranges.dart';

void main() {
  group('toQrRanges', () {
    test('groups consecutive numbers and keeps gaps apart', () {
      expect(
        toQrRanges([121, 122, 123, 125, 130, 131]),
        [const QrRange(121, 123), const QrRange(125, 125), const QrRange(130, 131)],
      );
    });

    test('ignores order and duplicates', () {
      expect(
        toQrRanges([3, 1, 2, 2, 1]),
        [const QrRange(1, 3)],
      );
    });

    test('empty in, empty out', () {
      expect(toQrRanges([]), isEmpty);
    });
  });

  group('QrRange text', () {
    test('input text is what the assign box understands', () {
      expect(const QrRange(121, 140).inputText, '121-140');
      expect(const QrRange(145, 145).inputText, '145');
      expect(
        qrRangesInputText([const QrRange(121, 140), const QrRange(145, 145)]),
        '121-140, 145',
      );
    });

    test('labels and counts', () {
      expect(const QrRange(121, 140).label, 'QR121 - QR140');
      expect(const QrRange(145, 145).label, 'QR145');
      expect(const QrRange(121, 140).count, 20);
    });
  });

  group('takeFirstQrNumbers', () {
    final ranges = [const QrRange(121, 125), const QrRange(130, 139)];

    test('stops inside a range when the count runs out', () {
      expect(takeFirstQrNumbers(ranges, 3), [const QrRange(121, 123)]);
    });

    test('spans several ranges', () {
      expect(takeFirstQrNumbers(ranges, 8), [
        const QrRange(121, 125),
        const QrRange(130, 132),
      ]);
    });

    test('asking for more than there is returns everything', () {
      expect(takeFirstQrNumbers(ranges, 500), ranges);
    });

    test('zero returns nothing', () {
      expect(takeFirstQrNumbers(ranges, 0), isEmpty);
    });
  });

  group('qrNumberOf', () {
    test('reads QR codes and rejects anything else', () {
      expect(qrNumberOf('QR121'), 121);
      expect(qrNumberOf('qr7'), 7);
      expect(qrNumberOf(''), isNull);
      expect(qrNumberOf('Demo QR121'), isNull);
    });
  });
}

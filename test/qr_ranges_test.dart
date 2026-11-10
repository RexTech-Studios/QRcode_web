import 'package:flutter_test/flutter_test.dart';
import 'package:reviewqr_admin/utils/qr_ranges.dart';

void main() {
  filterTests();
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

void filterTests() {
  group('filterQrNumbers', () {
    final free = [121, 122, 130, 131, 150, 151, 160, 215, 334];

    test('empty returns everything', () {
      expect(filterQrNumbers(free, ''), free);
      expect(filterQrNumbers(free, '   '), free);
    });

    test('digits match numbers that start with them', () {
      expect(filterQrNumbers(free, '13'), [130, 131]);
      expect(filterQrNumbers(free, '15'), [150, 151]);
      expect(filterQrNumbers(free, '2'), [215]);
      expect(filterQrNumbers(free, '334'), [334]);
    });

    test('a QR prefix and capitals are fine', () {
      expect(filterQrNumbers(free, 'QR13'), [130, 131]);
      expect(filterQrNumbers(free, 'qr 150'), [150]);
    });

    test('a range keeps the numbers inside it, either way round', () {
      expect(filterQrNumbers(free, '130-151'), [130, 131, 150, 151]);
      expect(filterQrNumbers(free, '151-130'), [130, 131, 150, 151]);
      expect(filterQrNumbers(free, '130 - 131'), [130, 131]);
    });

    test('nothing matches for text that is not a number or a range', () {
      expect(filterQrNumbers(free, 'abc'), isEmpty);
      expect(filterQrNumbers(free, '12x'), isEmpty);
      expect(filterQrNumbers(free, '999'), isEmpty);
    });
  });
}

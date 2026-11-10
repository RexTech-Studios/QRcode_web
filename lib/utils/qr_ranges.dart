/// Helpers for showing QR numbers as ranges ("121-140, 145") instead of one
/// long list, in the same form the admin can type into the assign box.
library;

/// A run of consecutive QR numbers, [start] to [end] inclusive.
class QrRange {
  final int start;
  final int end;
  const QrRange(this.start, this.end);

  int get count => end - start + 1;

  /// What to type into the assign box: "121-140" or "145".
  String get inputText => start == end ? '$start' : '$start-$end';

  /// What to show on a chip: "QR121 - QR140" or "QR145".
  String get label => start == end ? 'QR$start' : 'QR$start - QR$end';

  @override
  bool operator ==(Object other) =>
      other is QrRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'QrRange($inputText)';
}

/// The number in a code like "QR121", or null if it isn't one.
int? qrNumberOf(String code) {
  final match = RegExp(r'^QR(\d+)$', caseSensitive: false).firstMatch(code.trim());
  return match == null ? null : int.parse(match.group(1)!);
}

/// Groups [numbers] into runs of consecutive values. Order and duplicates in
/// the input don't matter.
List<QrRange> toQrRanges(Iterable<int> numbers) {
  final sorted = numbers.toSet().toList()..sort();
  final ranges = <QrRange>[];
  for (final n in sorted) {
    if (ranges.isNotEmpty && ranges.last.end == n - 1) {
      ranges[ranges.length - 1] = QrRange(ranges.last.start, n);
    } else {
      ranges.add(QrRange(n, n));
    }
  }
  return ranges;
}

/// The assign-box text for [ranges], e.g. "121-140, 145".
String qrRangesInputText(Iterable<QrRange> ranges) =>
    ranges.map((r) => r.inputText).join(', ');

/// The first [count] numbers of [ranges], still grouped into ranges.
List<QrRange> takeFirstQrNumbers(List<QrRange> ranges, int count) {
  final taken = <QrRange>[];
  var left = count;
  for (final r in ranges) {
    if (left <= 0) break;
    if (r.count <= left) {
      taken.add(r);
      left -= r.count;
    } else {
      taken.add(QrRange(r.start, r.start + left - 1));
      left = 0;
    }
  }
  return taken;
}

/// Narrows [numbers] to what a "find a QR" box asks for:
///  - empty: everything;
///  - digits ("15", or "QR15"): numbers that start with them (15, 150-159);
///  - a range ("150-170"): numbers inside it.
/// Anything else matches nothing.
List<int> filterQrNumbers(List<int> numbers, String query) {
  final q = query.trim().toUpperCase().replaceAll('QR', '').trim();
  if (q.isEmpty) return numbers;

  final range = RegExp(r'^(\d+)\s*[-\u2013]\s*(\d+)$').firstMatch(q);
  if (range != null) {
    final a = int.parse(range.group(1)!);
    final b = int.parse(range.group(2)!);
    final lo = a < b ? a : b;
    final hi = a < b ? b : a;
    return [for (final n in numbers) if (n >= lo && n <= hi) n];
  }
  if (RegExp(r'^\d+$').hasMatch(q)) {
    return [for (final n in numbers) if ('$n'.startsWith(q)) n];
  }
  return const [];
}

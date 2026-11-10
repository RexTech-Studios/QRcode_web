import '../models/assignment_model.dart';
import '../models/sales_user_model.dart';

/// One sales person's line in the report.
class RepSummary {
  final String uid;
  final String name;

  /// Assigned to them within the date range.
  final int assignedInRange;

  /// Sold (first edit) within the date range. This drives commission.
  final int soldInRange;

  /// Still waiting to be set up for a client, right now (ignores the range).
  final int pendingNow;

  const RepSummary({
    required this.uid,
    required this.name,
    required this.assignedInRange,
    required this.soldInRange,
    required this.pendingNow,
  });
}

/// One sale: a QR that a sales person set up for a real client.
class SoldRow {
  final String qrCode;
  final String shopName;
  final String repName;
  final DateTime? assignedAt;
  final DateTime soldAt;

  const SoldRow({
    required this.qrCode,
    required this.shopName,
    required this.repName,
    required this.assignedAt,
    required this.soldAt,
  });
}

/// Who sold what between two dates. Dates are whole local days, both inclusive;
/// a null bound leaves that side open.
class SalesReport {
  final DateTime? from;
  final DateTime? to;
  final List<RepSummary> summaries;
  final List<SoldRow> soldRows;

  const SalesReport({
    required this.from,
    required this.to,
    required this.summaries,
    required this.soldRows,
  });

  int get totalSold => soldRows.length;

  static SalesReport build({
    required List<Assignment> assignments,
    required List<SalesUser> users,
    required Map<String, String> shopNames,
    DateTime? from,
    DateTime? to,
  }) {
    final start = from == null
        ? null
        : DateTime(from.year, from.month, from.day);
    final endExclusive = to == null
        ? null
        : DateTime(to.year, to.month, to.day).add(const Duration(days: 1));

    bool inRange(DateTime? when) {
      if (when == null) return false;
      final local = when.toLocal();
      if (start != null && local.isBefore(start)) return false;
      if (endExclusive != null && !local.isBefore(endExclusive)) return false;
      return true;
    }

    // Every sales person is listed, even with nothing assigned; anyone who only
    // appears on an assignment (e.g. an account removed since) is added too.
    final names = <String, String>{for (final u in users) u.uid: u.name};
    for (final a in assignments) {
      names.putIfAbsent(a.assignedTo, () => a.assignedToName);
    }

    final summaries = <RepSummary>[];
    for (final entry in names.entries) {
      final mine = assignments.where((a) => a.assignedTo == entry.key).toList();
      summaries.add(
        RepSummary(
          uid: entry.key,
          name: entry.value,
          assignedInRange: mine.where((a) => inRange(a.assignedAt)).length,
          soldInRange: mine.where((a) => inRange(a.soldAt)).length,
          pendingNow: mine.where((a) => !a.isSold).length,
        ),
      );
    }
    summaries.sort((a, b) {
      final bySold = b.soldInRange.compareTo(a.soldInRange);
      return bySold != 0
          ? bySold
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    final soldRows = [
      for (final a in assignments)
        if (inRange(a.soldAt))
          SoldRow(
            qrCode: a.qrCode,
            shopName: shopNames[a.shopId] ?? '',
            repName: names[a.assignedTo] ?? a.assignedToName,
            assignedAt: a.assignedAt,
            soldAt: a.soldAt!,
          ),
    ]..sort((a, b) => b.soldAt.compareTo(a.soldAt));

    return SalesReport(
      from: from,
      to: to,
      summaries: summaries,
      soldRows: soldRows,
    );
  }

  String get rangeLabel {
    if (from == null && to == null) return 'All time';
    final f = from == null ? 'start' : formatDate(from!);
    final t = to == null ? 'today' : formatDate(to!);
    return '$f to $t';
  }

  String summaryCsv() {
    final rows = <List<String>>[
      ['Sales person', 'Assigned in range', 'Sold in range', 'Pending now'],
      for (final s in summaries)
        [s.name, '${s.assignedInRange}', '${s.soldInRange}', '${s.pendingNow}'],
    ];
    return _toCsv(rows);
  }

  String soldCsv() {
    final rows = <List<String>>[
      ['Sales person', 'QR number', 'Shop name', 'Assigned on', 'Sold on'],
      for (final r in soldRows)
        [
          r.repName,
          r.qrCode,
          r.shopName,
          r.assignedAt == null ? '' : formatDate(r.assignedAt!),
          formatDate(r.soldAt),
        ],
    ];
    return _toCsv(rows);
  }

  static String formatDate(DateTime date) {
    final d = date.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  /// A spreadsheet reads a cell starting with = + - @ as a formula, and shop
  /// names are typed by sales people, so those get a leading apostrophe.
  static String _cell(String value) {
    var text = value;
    if (text.isNotEmpty && '=+-@\t\r'.contains(text[0])) text = "'$text";
    if (text.contains(',') ||
        text.contains('"') ||
        text.contains('\n') ||
        text.contains('\r')) {
      text = '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }

  /// Turns rows into CSV text that is safe to open in a spreadsheet.
  static String toCsv(List<List<String>> rows) => _toCsv(rows);

  static String _toCsv(List<List<String>> rows) =>
      '${rows.map((row) => row.map(_cell).join(',')).join('\r\n')}\r\n';
}

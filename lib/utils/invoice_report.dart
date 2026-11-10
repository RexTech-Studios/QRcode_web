import '../models/invoice_model.dart';
import 'sales_report.dart';

/// One sales person's invoices added up.
class RepInvoiceTotal {
  final String uid;
  final String name;
  final int count;

  /// Whole rupees.
  final int amount;

  /// How many of those the sales person issued themselves.
  final int byRep;

  const RepInvoiceTotal({
    required this.uid,
    required this.name,
    required this.count,
    required this.amount,
    required this.byRep,
  });
}

/// Totals and exports for the admin's invoice tracker.
class InvoiceReport {
  const InvoiceReport._();

  static int totalAmount(Iterable<Invoice> invoices) =>
      invoices.fold(0, (sum, i) => sum + i.amount);

  /// Per sales person, biggest total first. An invoice with no sales person
  /// recorded (very early ones) is grouped under its sold-by name.
  static List<RepInvoiceTotal> perRep(Iterable<Invoice> invoices) {
    final groups = <String, List<Invoice>>{};
    for (final i in invoices) {
      final key = i.soldByUid.isNotEmpty ? i.soldByUid : 'name:${i.soldByName}';
      groups.putIfAbsent(key, () => []).add(i);
    }
    final totals = [
      for (final entry in groups.entries)
        RepInvoiceTotal(
          uid: entry.value.first.soldByUid,
          name: entry.value.first.soldByName.isEmpty
              ? 'Unknown'
              : entry.value.first.soldByName,
          count: entry.value.length,
          amount: totalAmount(entry.value),
          byRep: entry.value.where((i) => i.createdByRep).length,
        ),
    ];
    totals.sort((a, b) {
      final byAmount = b.amount.compareTo(a.amount);
      return byAmount != 0
          ? byAmount
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return totals;
  }

  static String csv(Iterable<Invoice> invoices) {
    final rows = <List<String>>[
      [
        'Invoice',
        'Date',
        'QR number',
        'Client',
        'Phone',
        'Address',
        'Amount (Rs.)',
        'Sales person',
        'Created by',
      ],
      for (final i in invoices)
        [
          i.numberText,
          i.issuedAt == null ? '' : SalesReport.formatDate(i.issuedAt!),
          i.qrCode,
          i.clientName,
          i.clientPhone,
          i.clientAddress,
          '${i.amount}',
          i.soldByName,
          i.createdByLabel,
        ],
    ];
    return SalesReport.toCsv(rows);
  }
}

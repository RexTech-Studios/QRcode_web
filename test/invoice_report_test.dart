import 'package:flutter_test/flutter_test.dart';
import 'package:reviewqr_admin/models/invoice_model.dart';
import 'package:reviewqr_admin/utils/invoice_report.dart';

Invoice inv(
  int number, {
  String uid = 'u1',
  String name = 'Ravi',
  int amount = 1500,
  bool byRep = false,
  String client = 'Client',
  String qr = 'QR1',
  DateTime? issued,
}) => Invoice(
  shopId: 'shop-$number',
  number: number,
  qrCode: qr,
  clientName: client,
  amount: amount,
  issuedAt: issued,
  soldByUid: uid,
  soldByName: name,
  createdByUid: byRep ? uid : 'admin-uid',
  createdByName: byRep ? name : 'Admin',
);

void main() {
  group('totals', () {
    test('adds up the amounts', () {
      expect(
        InvoiceReport.totalAmount([inv(1), inv(2, amount: 2500)]),
        4000,
      );
      expect(InvoiceReport.totalAmount(const []), 0);
    });

    test('groups by sales person, biggest total first, counting their own', () {
      final totals = InvoiceReport.perRep([
        inv(1),
        inv(2, byRep: true),
        inv(3, uid: 'u2', name: 'Anu', amount: 9000, byRep: true),
        inv(4, uid: 'u1'),
      ]);

      expect(totals.map((t) => t.name), ['Anu', 'Ravi']);
      expect(totals[0].count, 1);
      expect(totals[0].amount, 9000);
      expect(totals[0].byRep, 1);
      expect(totals[1].count, 3);
      expect(totals[1].amount, 4500);
      expect(totals[1].byRep, 1);
    });

    test('an early invoice with no sales person id is grouped by name', () {
      final totals = InvoiceReport.perRep([
        const Invoice(
          shopId: 's1',
          number: 1,
          qrCode: 'QR1',
          clientName: 'C',
          amount: 100,
          soldByName: 'Ravi',
        ),
        const Invoice(
          shopId: 's2',
          number: 2,
          qrCode: 'QR2',
          clientName: 'C',
          amount: 200,
          soldByName: 'Ravi',
        ),
      ]);
      expect(totals.single.name, 'Ravi');
      expect(totals.single.count, 2);
      expect(totals.single.amount, 300);
    });
  });

  group('CSV', () {
    test('has a header and one row per invoice, saying who made it', () {
      final csv = InvoiceReport.csv([
        inv(
          7,
          byRep: true,
          client: 'Sunrise Bakery',
          qr: 'QR122',
          issued: DateTime(2026, 11, 10, 12),
        ),
        inv(8, name: 'Anu', uid: 'u2', qr: 'QR123'),
      ]);
      final lines = csv.trim().split('\r\n');

      expect(
        lines.first,
        'Invoice,Date,QR number,Client,Phone,Address,Amount (Rs.),Sales person,Created by',
      );
      expect(lines[1], 'FSQ-0007,2026-11-10,QR122,Sunrise Bakery,,,1500,Ravi,Ravi');
      expect(lines[2], 'FSQ-0008,,QR123,Client,,,1500,Anu,Admin');
    });

    test('client names that could act as spreadsheet formulas are defused', () {
      final csv = InvoiceReport.csv([inv(1, client: '=HYPERLINK("x")')]);
      expect(csv, contains("\"'=HYPERLINK(\"\"x\"\")\""));
    });
  });
}

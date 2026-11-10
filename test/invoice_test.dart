import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reviewqr_admin/models/invoice_model.dart';
import 'package:reviewqr_admin/providers/sales_admin_provider.dart';
import 'package:reviewqr_admin/services/invoice_pdf.dart';
import 'package:reviewqr_admin/services/sales_repository.dart';
import 'package:reviewqr_admin/utils/money_format.dart';

import 'support/fake_sales_repository.dart';

void main() {
  group('formatRupees', () {
    test('uses Indian grouping', () {
      expect(formatRupees(0), '0');
      expect(formatRupees(999), '999');
      expect(formatRupees(1500), '1,500');
      expect(formatRupees(25000), '25,000');
      expect(formatRupees(150000), '1,50,000');
      expect(formatRupees(12345678), '1,23,45,678');
    });
  });

  group('parseRupees', () {
    test('reads the ways people type a price', () {
      expect(parseRupees('1500'), 1500);
      expect(parseRupees('1,500'), 1500);
      expect(parseRupees(' Rs. 1500 '), 1500);
      expect(parseRupees('₹1,500/-'), 1500);
    });

    test('refuses anything that is not a whole positive amount', () {
      expect(parseRupees(''), isNull);
      expect(parseRupees('abc'), isNull);
      expect(parseRupees('0'), isNull);
      expect(parseRupees('-5'), isNull);
      expect(parseRupees('15.50'), isNull);
    });
  });

  group('invoice numbers', () {
    test('are padded to four digits and grow past 9999', () {
      expect(formatInvoiceNumber(1), 'FSQ-0001');
      expect(formatInvoiceNumber(42), 'FSQ-0042');
      expect(formatInvoiceNumber(12345), 'FSQ-12345');
    });
  });

  group('invoice PDF', () {
    const invoice = Invoice(
      shopId: 'shop-123',
      number: 7,
      qrCode: 'QR123',
      clientName: 'Sunrise Bakery',
      clientPhone: '98765 43210',
      clientAddress: 'MG Road, Kochi',
      amount: 1500,
    );

    test('is a real PDF', () async {
      final bytes = await buildInvoicePdf(invoice);
      expect(bytes.length, greaterThan(1000));
      expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    });

    test('still builds with no phone, no address and a very long name', () async {
      final bytes = await buildInvoicePdf(
        Invoice(
          shopId: 's',
          number: 1,
          qrCode: 'QR1',
          clientName: 'A' * 100,
          amount: 10000000,
        ),
      );
      expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    });

    test('file name is safe and says which invoice it is', () {
      expect(invoiceFileName(invoice), 'Invoice-FSQ-0007-Sunrise-Bakery.pdf');
      const odd = Invoice(
        shopId: 's',
        number: 8,
        qrCode: 'QR1',
        clientName: '  ../../Café & Co!  ',
        amount: 1,
      );
      expect(invoiceFileName(odd), 'Invoice-FSQ-0008-Caf-Co.pdf');
    });

    test('describes the one thing sold', () {
      expect(invoiceDescription(invoice), contains('QR123'));
    });
  });

  group('SalesAdminProvider invoices', () {
    FakeSalesRepository repo() => FakeSalesRepository(
      assignments: [
        assignmentFor(121), // not set up yet
        assignmentFor(122, locked: true, soldAt: DateTime(2026, 11, 9)),
        assignmentFor(123, uid: 'u2', name: 'Anu', soldAt: DateTime(2026, 11, 9)),
      ],
    );

    Future<SalesAdminProvider> loaded(FakeSalesRepository r) async {
      final p = SalesAdminProvider(r);
      await p.load();
      return p;
    }

    test('creates an invoice for a sold QR, made by the admin', () async {
      final r = repo();
      final p = await loaded(r);

      final invoice = await p.createInvoice(
        p.assignments.firstWhere((a) => a.qrCode == 'QR122'),
        clientName: '  Sunrise Bakery ',
        clientPhone: '98765 43210',
        clientAddress: '',
        price: '1,500',
      );

      expect(invoice.numberText, 'FSQ-0001');
      expect(invoice.clientName, 'Sunrise Bakery');
      expect(invoice.amount, 1500);
      expect(invoice.soldByName, 'Ravi');
      expect(invoice.soldByUid, 'u1');
      expect(invoice.createdByRep, isFalse);
      expect(invoice.createdByLabel, 'Admin');
      expect(r.lastInvoiceCreator?.name, 'Admin');
      expect(p.invoiceFor('shop-122')?.number, 1);
      expect(
        p.defaultPrice,
        isNull,
        reason: 'the fixed price changes only when the admin sets it',
      );
    });

    test('the fixed price is saved only when it is valid', () async {
      final r = repo();
      final p = await loaded(r);

      await expectLater(p.setPrice(''), throwsA(isA<SalesException>()));
      await expectLater(p.setPrice('12.5'), throwsA(isA<SalesException>()));
      await expectLater(p.setPrice('99999999'), throwsA(isA<SalesException>()));
      expect(r.calls.where((c) => c.startsWith('price:')), isEmpty);

      await p.setPrice('1,800');
      expect(p.defaultPrice, 1800);
      expect(r.invoicePrice, 1800);
    });

    test('invoices list newest number first', () async {
      final p = await loaded(repo());
      Future<Invoice> make(String code) => p.createInvoice(
        p.assignments.firstWhere((a) => a.qrCode == code),
        clientName: 'C',
        clientPhone: '',
        clientAddress: '',
        price: '1500',
      );
      await make('QR122');
      await make('QR123');
      expect(p.invoices.map((i) => i.numberText), ['FSQ-0002', 'FSQ-0001']);
    });

    test('a QR that is not set up yet cannot be invoiced', () async {
      final r = repo();
      final p = await loaded(r);

      await expectLater(
        p.createInvoice(
          p.assignments.firstWhere((a) => a.qrCode == 'QR121'),
          clientName: 'X',
          clientPhone: '',
          clientAddress: '',
          price: '1500',
        ),
        throwsA(isA<SalesException>()),
      );
      expect(r.calls.where((c) => c.startsWith('invoice:')), isEmpty);
    });

    test('invoicing the same QR again returns the same invoice and writes nothing', () async {
      final r = repo();
      final p = await loaded(r);
      final a = p.assignments.firstWhere((a) => a.qrCode == 'QR122');

      final first = await p.createInvoice(
        a,
        clientName: 'Sunrise Bakery',
        clientPhone: '',
        clientAddress: '',
        price: '1500',
      );
      final second = await p.createInvoice(
        a,
        clientName: 'Someone Else',
        clientPhone: '',
        clientAddress: '',
        price: '999',
      );

      expect(second.number, first.number);
      expect(second.clientName, 'Sunrise Bakery');
      expect(r.calls.where((c) => c.startsWith('invoice:')).length, 1);
    });

    test('numbers run in order across QRs', () async {
      final p = await loaded(repo());
      final a = p.assignments.firstWhere((a) => a.qrCode == 'QR122');
      final b = p.assignments.firstWhere((a) => a.qrCode == 'QR123');
      Future<Invoice> make(a) => p.createInvoice(
        a,
        clientName: 'C',
        clientPhone: '',
        clientAddress: '',
        price: '1500',
      );
      expect((await make(a)).numberText, 'FSQ-0001');
      expect((await make(b)).numberText, 'FSQ-0002');
    });

    test('bad details are refused before anything is written', () async {
      final r = repo();
      final p = await loaded(r);
      final a = p.assignments.firstWhere((a) => a.qrCode == 'QR122');

      for (final bad in [
        (name: '', phone: '', price: '1500'),
        (name: 'X', phone: 'call me', price: '1500'),
        (name: 'X', phone: '', price: ''),
        (name: 'X', phone: '', price: '12.5'),
        (name: 'X', phone: '', price: '99999999'),
      ]) {
        await expectLater(
          p.createInvoice(
            a,
            clientName: bad.name,
            clientPhone: bad.phone,
            clientAddress: '',
            price: bad.price,
          ),
          throwsA(isA<SalesException>()),
          reason: '$bad',
        );
      }
      expect(r.calls.where((c) => c.startsWith('invoice:')), isEmpty);
    });

    test('a failed write is not remembered', () async {
      final r = repo()..invoiceError = Exception('network down');
      final p = await loaded(r);
      final a = p.assignments.firstWhere((a) => a.qrCode == 'QR122');

      await expectLater(
        p.createInvoice(
          a,
          clientName: 'C',
          clientPhone: '',
          clientAddress: '',
          price: '1500',
        ),
        throwsA(isA<Exception>()),
      );
      expect(p.invoiceFor('shop-122'), isNull);
      expect(p.defaultPrice, isNull);
    });

    test('load brings in existing invoices and the last price; reset forgets them', () async {
      final r = repo()
        ..invoicePrice = 1800
        ..invoices.add(
          const Invoice(
            shopId: 'shop-122',
            number: 3,
            qrCode: 'QR122',
            clientName: 'Old Client',
            amount: 1800,
          ),
        );
      final p = await loaded(r);
      expect(p.invoiceFor('shop-122')?.clientName, 'Old Client');
      expect(p.defaultPrice, 1800);

      p.reset();
      expect(p.invoiceFor('shop-122'), isNull);
      expect(p.defaultPrice, isNull);
    });
  });

  group('Invoice creator', () {
    test('an invoice the sales person made themselves says so', () {
      const byRep = Invoice(
        shopId: 's',
        number: 1,
        qrCode: 'QR1',
        clientName: 'C',
        amount: 1,
        soldByName: 'Ravi',
        soldByUid: 'u1',
        createdByUid: 'u1',
        createdByName: 'Ravi',
      );
      expect(byRep.createdByRep, isTrue);
      expect(byRep.createdByLabel, 'Ravi');
    });

    test('an admin invoice, and an early one with no creator, both say Admin', () {
      const byAdmin = Invoice(
        shopId: 's',
        number: 1,
        qrCode: 'QR1',
        clientName: 'C',
        amount: 1,
        soldByName: 'Ravi',
        soldByUid: 'u1',
        createdByUid: 'admin-uid',
        createdByName: 'Admin',
      );
      const early = Invoice(
        shopId: 's',
        number: 2,
        qrCode: 'QR2',
        clientName: 'C',
        amount: 1,
        soldByName: 'Ravi',
      );
      expect(byAdmin.createdByRep, isFalse);
      expect(byAdmin.createdByLabel, 'Admin');
      expect(early.createdByRep, isFalse);
      expect(early.createdByLabel, 'Admin');
    });

    test('fromMap reads the new fields and tolerates old documents', () {
      final fresh = Invoice.fromMap({
        'shopId': 's',
        'number': 3,
        'soldByUid': 'u1',
        'createdByUid': 'u1',
        'createdByName': 'Ravi',
      });
      expect(fresh.createdByRep, isTrue);
      final old = Invoice.fromMap({'shopId': 's', 'number': 3});
      expect(old.soldByUid, '');
      expect(old.createdByRep, isFalse);
    });
  });
}

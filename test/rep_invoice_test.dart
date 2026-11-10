import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:reviewqr_admin/models/invoice_model.dart';
import 'package:reviewqr_admin/providers/rep_provider.dart';
import 'package:reviewqr_admin/screens/sales/rep_home_screen.dart';
import 'package:reviewqr_admin/services/invoice_pdf.dart';
import 'package:reviewqr_admin/services/sales_repository.dart';

import 'support/fake_sales_repository.dart';

FakeSalesRepository repoFor({int? price = 1500}) => FakeSalesRepository(
  users: [ravi, anu],
  assignments: [
    assignmentFor(121), // Ravi, not set up yet
    assignmentFor(122, locked: true, soldAt: DateTime(2026, 11, 5)), // Ravi, sold
    assignmentFor(123, uid: 'u2', name: 'Anu', soldAt: DateTime(2026, 11, 5)),
  ],
  shops: {
    'shop-121': shopFor(121),
    'shop-122': shopFor(122),
    'shop-123': shopFor(123),
  },
)..invoicePrice = price;

RepProvider providerFor(FakeSalesRepository repo) => RepProvider(
  repo,
  renameSheet: ({required googleSheetsUrl, required shopName}) async => true,
);

void main() {
  group('RepProvider invoices', () {
    Future<RepProvider> loaded(FakeSalesRepository repo) async {
      final p = providerFor(repo);
      await p.load(ravi);
      return p;
    }

    test('load brings in my invoices and the fixed price, not other people\'s', () async {
      final repo = repoFor()
        ..invoices.addAll(const [
          Invoice(
            shopId: 'shop-122',
            number: 1,
            qrCode: 'QR122',
            clientName: 'Mine',
            amount: 1500,
            soldByUid: 'u1',
            soldByName: 'Ravi',
          ),
          Invoice(
            shopId: 'shop-123',
            number: 2,
            qrCode: 'QR123',
            clientName: 'Anus',
            amount: 1500,
            soldByUid: 'u2',
            soldByName: 'Anu',
          ),
        ]);
      final p = await loaded(repo);

      expect(p.price, 1500);
      expect(p.invoices.map((i) => i.clientName), ['Mine']);
      expect(p.invoiceFor('shop-123'), isNull);
      expect(p.invoicedCount, 1);
      expect(p.invoicedTotal, 1500);
    });

    test('a failed invoice load does not break the QR list', () async {
      final p = RepProvider(_InvoicesDown(), renameSheet: _noRename);
      await p.load(ravi);
      expect(p.items.length, 2);
      expect(p.loadError, isNull);
      expect(p.price, isNull);
    });

    test('makes the invoice at the fixed price, in my name', () async {
      final repo = repoFor(price: 1800);
      final p = await loaded(repo);
      final item = p.items.firstWhere((i) => i.assignment.qrCode == 'QR122');

      final invoice = await p.createInvoice(
        item,
        clientName: '  Sunrise Bakery ',
        clientPhone: '98765 43210',
        clientAddress: '',
      );

      expect(invoice.numberText, 'FSQ-0001');
      expect(invoice.amount, 1800, reason: 'the price is never typed by the rep');
      expect(invoice.clientName, 'Sunrise Bakery');
      expect(invoice.createdByRep, isTrue);
      expect(repo.lastInvoiceCreator, (uid: 'u1', name: 'Ravi'));
      expect(p.invoiceFor('shop-122')?.number, 1);
      expect(p.invoicedCount, 1);
    });

    test('refuses when the admin has not set a price, and writes nothing', () async {
      final repo = repoFor(price: null);
      final p = await loaded(repo);
      final item = p.items.firstWhere((i) => i.assignment.qrCode == 'QR122');

      await expectLater(
        p.createInvoice(item, clientName: 'X', clientPhone: '', clientAddress: ''),
        throwsA(
          isA<SalesException>().having((e) => e.message, 'message', contains('price')),
        ),
      );
      expect(repo.calls.where((c) => c.startsWith('invoice:')), isEmpty);
    });

    test('a QR that is not set up yet cannot be invoiced', () async {
      final repo = repoFor();
      final p = await loaded(repo);
      final item = p.items.firstWhere((i) => i.assignment.qrCode == 'QR121');

      await expectLater(
        p.createInvoice(item, clientName: 'X', clientPhone: '', clientAddress: ''),
        throwsA(isA<SalesException>()),
      );
      expect(repo.calls.where((c) => c.startsWith('invoice:')), isEmpty);
    });

    test('bad details are refused before anything is written', () async {
      final repo = repoFor();
      final p = await loaded(repo);
      final item = p.items.firstWhere((i) => i.assignment.qrCode == 'QR122');

      for (final bad in [
        (name: '', phone: ''),
        (name: 'X', phone: 'call me'),
        (name: 'A' * 101, phone: ''),
      ]) {
        await expectLater(
          p.createInvoice(
            item,
            clientName: bad.name,
            clientPhone: bad.phone,
            clientAddress: '',
          ),
          throwsA(isA<SalesException>()),
          reason: '$bad',
        );
      }
      expect(repo.calls.where((c) => c.startsWith('invoice:')), isEmpty);
    });

    test('invoicing the same QR twice returns the first invoice', () async {
      final repo = repoFor();
      final p = await loaded(repo);
      final item = p.items.firstWhere((i) => i.assignment.qrCode == 'QR122');

      final first = await p.createInvoice(
        item,
        clientName: 'Sunrise Bakery',
        clientPhone: '',
        clientAddress: '',
      );
      final second = await p.createInvoice(
        item,
        clientName: 'Someone Else',
        clientPhone: '',
        clientAddress: '',
      );

      expect(second.number, first.number);
      expect(second.clientName, 'Sunrise Bakery');
      expect(repo.calls.where((c) => c.startsWith('invoice:')).length, 1);
    });

    test('a refused write explains it and is not remembered', () async {
      final repo = repoFor()
        ..invoiceError = Exception('[cloud_firestore/permission-denied] no');
      final p = await loaded(repo);
      final item = p.items.firstWhere((i) => i.assignment.qrCode == 'QR122');

      await expectLater(
        p.createInvoice(item, clientName: 'X', clientPhone: '', clientAddress: ''),
        throwsA(
          isA<SalesException>().having(
            (e) => e.message,
            'message',
            contains('price may have just changed'),
          ),
        ),
      );
      expect(p.invoiceFor('shop-122'), isNull);
    });

    test('a refusal worded the web way is still explained as a refusal', () async {
      final repo = repoFor()
        ..invoiceError = Exception('Missing or insufficient permissions.');
      final p = await loaded(repo);
      final item = p.items.firstWhere((i) => i.assignment.qrCode == 'QR122');

      await expectLater(
        p.createInvoice(item, clientName: 'X', clientPhone: '', clientAddress: ''),
        throwsA(
          isA<SalesException>().having(
            (e) => e.message,
            'message',
            contains('price may have just changed'),
          ),
        ),
      );
    });

    test('an offline write says to check the connection', () async {
      final repo = repoFor()..invoiceError = Exception('network down');
      final p = await loaded(repo);
      final item = p.items.firstWhere((i) => i.assignment.qrCode == 'QR122');

      await expectLater(
        p.createInvoice(item, clientName: 'X', clientPhone: '', clientAddress: ''),
        throwsA(
          isA<SalesException>().having(
            (e) => e.message,
            'message',
            contains('connection'),
          ),
        ),
      );
    });

    test('reset forgets invoices and the price', () async {
      final p = await loaded(repoFor());
      final item = p.items.firstWhere((i) => i.assignment.qrCode == 'QR122');
      await p.createInvoice(item, clientName: 'X', clientPhone: '', clientAddress: '');

      p.reset();
      expect(p.invoices, isEmpty);
      expect(p.price, isNull);
    });
  });

  group('My QR codes screen', () {
    late List<String> downloaded;
    late InvoiceDownloader original;

    setUp(() {
      downloaded = [];
      original = invoiceDownloader;
      invoiceDownloader = (invoice) async => downloaded.add(invoice.numberText);
    });
    tearDown(() => invoiceDownloader = original);

    Future<RepProvider> pump(
      WidgetTester tester,
      FakeSalesRepository repo, {
      Size size = const Size(800, 1600),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final provider = providerFor(repo);
      await provider.load(ravi);
      await tester.pumpWidget(
        ChangeNotifierProvider<RepProvider>.value(
          value: provider,
          child: const MaterialApp(home: RepHomeScreen()),
        ),
      );
      await tester.pump();
      return provider;
    }

    Finder inDialog(Finder f) =>
        find.descendant(of: find.byType(AlertDialog), matching: f);

    testWidgets('only a QR that is set up offers an invoice', (tester) async {
      await pump(tester, repoFor());

      // QR121 is not set up; QR122 is.
      expect(find.text('Create invoice'), findsOneWidget);
    });

    testWidgets('makes the invoice at the fixed price, which cannot be edited', (
      tester,
    ) async {
      final repo = repoFor(price: 1800);
      await pump(tester, repo);

      await tester.tap(find.text('Create invoice'));
      await tester.pumpAndSettle();
      expect(find.text('Invoice for QR122'), findsOneWidget);

      final fields = inDialog(find.byType(TextField));
      final price = tester.widget<TextField>(fields.at(3));
      expect(price.controller!.text, '1800');
      expect(price.enabled, isFalse);

      // Missing name: refused, nothing written.
      await tester.tap(inDialog(find.widgetWithText(ElevatedButton, 'Create invoice')));
      await tester.pump();
      expect(find.text("Enter the client's name."), findsOneWidget);
      expect(repo.invoices, isEmpty);

      await tester.enterText(fields.at(0), 'Sunrise Bakery');
      await tester.tap(inDialog(find.widgetWithText(ElevatedButton, 'Create invoice')));
      await tester.pumpAndSettle();

      expect(repo.invoices.single.amount, 1800);
      expect(repo.invoices.single.createdByRep, isTrue);
      expect(downloaded, ['FSQ-0001']);
      expect(find.text('Invoice FSQ-0001'), findsOneWidget);
      expect(find.textContaining('Invoiced FSQ-0001'), findsOneWidget);
      expect(find.textContaining('Invoiced: 1'), findsOneWidget);

      // The same button downloads it again, with no new number.
      await tester.tap(find.text('Invoice FSQ-0001'));
      await tester.pumpAndSettle();
      expect(downloaded, ['FSQ-0001', 'FSQ-0001']);
      expect(repo.invoices.length, 1);
    });

    testWidgets('with no price set it says so instead of opening the form', (
      tester,
    ) async {
      final repo = repoFor(price: null);
      await pump(tester, repo);

      await tester.tap(find.text('Create invoice'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('price has not been set'), findsOneWidget);
      expect(repo.invoices, isEmpty);
    });

    testWidgets('fits a 320px phone without overflow', (tester) async {
      final repo = repoFor()
        ..invoices.add(
          const Invoice(
            shopId: 'shop-122',
            number: 1,
            qrCode: 'QR122',
            clientName: 'A Very Long Client Name Pvt Ltd Trading As Something',
            amount: 12345678,
            soldByUid: 'u1',
            soldByName: 'Ravi',
          ),
        );
      await pump(tester, repo, size: const Size(320, 900));
      expect(tester.takeException(), isNull);
    });
  });
}

typedef InvoiceDownloader = Future<void> Function(Invoice invoice);

Future<bool> _noRename({
  required String? googleSheetsUrl,
  required String shopName,
}) async => true;

class _InvoicesDown extends FakeSalesRepository {
  _InvoicesDown()
    : super(assignments: [assignmentFor(121), assignmentFor(122)]);

  @override
  Future<List<Invoice>> fetchInvoicesFor(String uid) =>
      throw Exception('permission-denied');
}

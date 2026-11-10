import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:reviewqr_admin/models/invoice_model.dart';
import 'package:reviewqr_admin/models/sales_user_model.dart';
import 'package:reviewqr_admin/providers/qr_provider.dart';
import 'package:reviewqr_admin/providers/sales_admin_provider.dart';
import 'package:reviewqr_admin/providers/shop_provider.dart';
import 'package:reviewqr_admin/screens/sales/sales_team_screen.dart';
import 'package:reviewqr_admin/services/invoice_pdf.dart';

import 'support/fake_providers.dart';
import 'support/fake_sales_repository.dart';

const turnedOff = SalesUser(
  uid: 'u3',
  name: 'Old Joe',
  email: 'joe@example.com',
  active: false,
);

Future<SalesAdminProvider> pumpTeam(
  WidgetTester tester,
  FakeSalesRepository repo,
) async {
  tester.view.physicalSize = const Size(1100, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final sales = SalesAdminProvider(repo);
  await sales.load();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SalesAdminProvider>.value(value: sales),
        ChangeNotifierProvider<QrProvider>.value(
          value: FakeQrProvider([for (var n = 121; n <= 130; n++) qrFor(n)]),
        ),
        ChangeNotifierProvider<ShopProvider>.value(
          value: FakeShopProvider([for (var n = 121; n <= 130; n++) shopFor(n)]),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: SalesTeamScreen())),
    ),
  );
  await tester.pump();
  return sales;
}

FakeSalesRepository teamRepo() => FakeSalesRepository(
  users: [ravi, anu, turnedOff],
  assignments: [
    assignmentFor(121), // Ravi, not set up yet
    assignmentFor(122, locked: true, soldAt: DateTime.now()), // Ravi, edited
    assignmentFor(
      123,
      uid: 'u2',
      name: 'Anu',
      soldAt: DateTime.now(),
    ), // Anu, unlocked after a sale
  ],
);

typedef InvoiceDownloaderFn = Future<void> Function(Invoice invoice);

Finder inDialog(Finder f) => find.descendant(of: find.byType(AlertDialog), matching: f);

void main() {
  group('Team tab', () {
    testWidgets('lists everyone with their counts and status', (tester) async {
      await pumpTeam(tester, teamRepo());

      expect(find.text('Ravi'), findsOneWidget);
      expect(find.text('Anu'), findsOneWidget);
      expect(find.text('Old Joe'), findsOneWidget);
      expect(find.text('3 sales people'), findsOneWidget);
      expect(find.text('Active'), findsNWidgets(2));
      expect(find.text('Turned off'), findsOneWidget);
    });

    testWidgets('cannot assign QR codes to someone who is turned off', (tester) async {
      await pumpTeam(tester, teamRepo());
      final buttons = tester.widgetList<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Assign QRs'),
      );
      expect(buttons.map((b) => b.onPressed == null), [false, false, true]);
    });

    testWidgets('says so when there is nobody yet', (tester) async {
      await pumpTeam(tester, FakeSalesRepository());
      expect(find.textContaining('No sales people yet'), findsOneWidget);
    });

    testWidgets('adding a person creates the login and shows what to send', (tester) async {
      final repo = FakeSalesRepository();
      await pumpTeam(tester, repo);

      await tester.tap(find.text('Add sales person'));
      await tester.pumpAndSettle();
      final fields = inDialog(find.byType(TextField));
      await tester.enterText(fields.at(0), 'Priya Nair');
      await tester.enterText(fields.at(1), 'Priya@Example.com');
      await tester.enterText(fields.at(2), 'secret123');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create login'));
      await tester.pumpAndSettle();

      expect(repo.calls, ['create:Priya@Example.com']);
      expect(find.text('Login created'), findsOneWidget);
      expect(find.text('Priya Nair can now sign in. Send them these details:'), findsOneWidget);
      expect(inDialog(find.text('secret123')), findsOneWidget);
      expect(inDialog(find.text('Priya@Example.com')), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('1 sales person'), findsOneWidget);
    });

    testWidgets('a bad email is refused and nothing is created', (tester) async {
      final repo = FakeSalesRepository();
      await pumpTeam(tester, repo);

      await tester.tap(find.text('Add sales person'));
      await tester.pumpAndSettle();
      final fields = inDialog(find.byType(TextField));
      await tester.enterText(fields.at(0), 'Priya');
      await tester.enterText(fields.at(1), 'not-an-email');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create login'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(repo.calls, isEmpty);
    });

    testWidgets('turning someone off asks first, then does it', (tester) async {
      final repo = teamRepo();
      final sales = await pumpTeam(tester, repo);

      await tester.tap(find.text('Turn off').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('will not be able to sign in'), findsOneWidget);
      expect(repo.calls, isEmpty, reason: 'nothing until confirmed');

      await tester.tap(find.widgetWithText(ElevatedButton, 'Turn off'));
      await tester.pumpAndSettle();
      expect(repo.calls, ['active:u1:false']);
      expect(sales.userById('u1')?.active, isFalse);
    });

    testWidgets('assigning a mix of good and bad numbers previews before writing', (tester) async {
      final repo = teamRepo();
      await pumpTeam(tester, repo);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Assign QRs').first);
      await tester.pumpAndSettle();
      await tester.enterText(inDialog(find.byType(TextField)), '124-126, 999');
      await tester.pump();

      expect(find.textContaining('Will assign 3 QR codes'), findsOneWidget);
      expect(find.textContaining('No such QR number: QR999'), findsOneWidget);
      expect(repo.calls, isEmpty, reason: 'preview only');

      await tester.tap(find.widgetWithText(ElevatedButton, 'Assign 3'));
      await tester.pumpAndSettle();

      expect(repo.lastAssigned.map((q) => q.qrCode), ['QR124', 'QR125', 'QR126']);
      expect(find.text('Assigned 3 QR codes to Ravi.'), findsOneWidget);
    });

    testWidgets('lists the free QR numbers and a tap fills the box', (tester) async {
      final repo = teamRepo();
      await pumpTeam(tester, repo);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Assign QRs').first);
      await tester.pumpAndSettle();

      // 121-123 are already held, so 124-130 are free.
      expect(find.text('Available to assign: 7'), findsOneWidget);
      await tester.tap(find.text('QR124 - QR130  (7)'));
      await tester.pump();

      final box = tester.widget<TextField>(inDialog(find.byType(TextField)));
      expect(box.controller!.text, '124-130');
      expect(find.textContaining('Will assign 7 QR codes'), findsOneWidget);
    });

    testWidgets('a second tap adds to what is already typed', (tester) async {
      await pumpTeam(tester, teamRepo());

      await tester.tap(find.widgetWithText(ElevatedButton, 'Assign QRs').first);
      await tester.pumpAndSettle();
      await tester.enterText(inDialog(find.byType(TextField)), '125,');
      await tester.pump();
      await tester.tap(find.text('QR124 - QR130  (7)'));
      await tester.pump();

      final box = tester.widget<TextField>(inDialog(find.byType(TextField)));
      expect(box.controller!.text, '125, 124-130');
    });

    testWidgets('a QR that is already sold cannot be assigned again', (tester) async {
      await pumpTeam(tester, teamRepo());

      // QR123 was sold by Anu; try to give it to Ravi.
      await tester.tap(find.widgetWithText(ElevatedButton, 'Assign QRs').first);
      await tester.pumpAndSettle();
      await tester.enterText(inDialog(find.byType(TextField)), '123');
      await tester.pump();

      expect(find.textContaining("Can't assign"), findsOneWidget);
      expect(find.textContaining('already sold by Anu'), findsOneWidget);
      final assign = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Assign'));
      expect(assign.onPressed, isNull);
    });
  });

  group('Assigned QRs tab', () {
    Future<void> openAssigned(WidgetTester tester) async {
      await tester.tap(find.text('Assigned QRs'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows each QR with its status and only the actions that apply', (tester) async {
      await pumpTeam(tester, teamRepo());
      await openAssigned(tester);

      expect(find.text('Not set up yet'), findsOneWidget);
      expect(find.text('Edited - locked'), findsOneWidget);
      expect(find.text('Unlocked for another edit'), findsOneWidget);
      // QR121 can be taken back; the sold ones cannot. Only QR122 is locked.
      expect(find.text('Take back'), findsOneWidget);
      expect(find.text('Allow edit again'), findsOneWidget);
    });

    testWidgets('a sold QR can be invoiced once, then the same button downloads it', (tester) async {
      final downloaded = <String>[];
      final original = invoiceDownloader;
      invoiceDownloader = (invoice) async => downloaded.add(invoice.numberText);
      addTearDown(() => invoiceDownloader = original);

      final repo = teamRepo();
      await pumpTeam(tester, repo);
      await openAssigned(tester);

      // Two of the three QRs are sold (122 by Ravi, 123 by Anu); 121 is not.
      expect(find.text('Create invoice'), findsNWidgets(2));

      await tester.tap(find.text('Create invoice').first);
      await tester.pumpAndSettle();
      expect(find.text('Invoice for QR122'), findsOneWidget);

      // Missing details are refused and nothing is written.
      await tester.tap(inDialog(find.widgetWithText(ElevatedButton, 'Create invoice')));
      await tester.pump();
      expect(find.text("Enter the client's name."), findsOneWidget);
      expect(repo.invoices, isEmpty);

      final fields = inDialog(find.byType(TextField));
      await tester.enterText(fields.at(0), 'Sunrise Bakery');
      await tester.enterText(fields.at(3), '1500');
      await tester.tap(inDialog(find.widgetWithText(ElevatedButton, 'Create invoice')));
      await tester.pumpAndSettle();

      expect(repo.invoices.single.numberText, 'FSQ-0001');
      expect(repo.invoices.single.amount, 1500);
      expect(downloaded, ['FSQ-0001']);
      expect(find.text('Invoice FSQ-0001'), findsOneWidget);
      expect(find.textContaining('Invoiced FSQ-0001'), findsOneWidget);
      expect(find.text('Create invoice'), findsOneWidget, reason: 'QR123 still needs one');

      // Tapping the invoice button again re-downloads without a new number.
      await tester.tap(find.text('Invoice FSQ-0001'));
      await tester.pumpAndSettle();
      expect(downloaded, ['FSQ-0001', 'FSQ-0001']);
      expect(repo.invoices.length, 1);
    });

    testWidgets('the invoice price starts at the fixed price the admin set', (tester) async {
      final repo = teamRepo()..invoicePrice = 1800;
      await pumpTeam(tester, repo);
      await openAssigned(tester);

      await tester.tap(find.text('Create invoice').first);
      await tester.pumpAndSettle();

      final price = tester.widget<TextField>(inDialog(find.byType(TextField)).at(3));
      expect(price.controller!.text, '1800');
    });

    testWidgets('allowing another edit asks first, then unlocks', (tester) async {
      final repo = teamRepo();
      await pumpTeam(tester, repo);
      await openAssigned(tester);

      await tester.tap(find.text('Allow edit again'));
      await tester.pumpAndSettle();
      expect(find.text('Allow another edit?'), findsOneWidget);
      expect(repo.calls, isEmpty);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Allow edit'));
      await tester.pumpAndSettle();

      expect(repo.calls, ['locked:shop-122:false']);
      expect(find.text('Allow edit again'), findsNothing);
      expect(find.text('Unlocked for another edit'), findsNWidgets(2));
    });

    testWidgets('taking a QR back removes it from the list', (tester) async {
      final repo = teamRepo();
      final sales = await pumpTeam(tester, repo);
      await openAssigned(tester);

      await tester.tap(find.text('Take back'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Take back'));
      await tester.pumpAndSettle();

      expect(repo.calls, ['unassign:shop-121']);
      expect(sales.assignmentFor('shop-121'), isNull);
    });

    testWidgets('filters by search and by status', (tester) async {
      await pumpTeam(tester, teamRepo());
      await openAssigned(tester);

      await tester.enterText(find.byType(TextField).first, '122');
      await tester.pump();
      expect(find.text('1 of 3 assigned QR codes'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump();
      expect(find.text('3 of 3 assigned QR codes'), findsOneWidget);
    });

    testWidgets('says so when nothing is assigned', (tester) async {
      await pumpTeam(tester, FakeSalesRepository(users: [ravi]));
      await openAssigned(tester);
      expect(find.textContaining('No QR codes are assigned yet'), findsOneWidget);
    });
  });

  testWidgets('the invoice price can be set from any tab, not just Invoices', (tester) async {
    final repo = teamRepo();
    await pumpTeam(tester, repo);

    for (final tab in ['Team', 'Assigned QRs', 'Report']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(find.text('Set price').evaluate().length + find.text('Change').evaluate().length, 1, reason: tab);
    }

    // From the Report tab.
    await tester.tap(find.text('Set price'));
    await tester.pumpAndSettle();
    await tester.enterText(inDialog(find.byType(TextField)), '750');
    await tester.tap(find.text('Save price'));
    await tester.pumpAndSettle();

    expect(repo.invoicePrice, 750);
    for (final tab in ['Team', 'Assigned QRs', 'Invoices']) {
      await tester.tap(find.text(tab).first);
      await tester.pumpAndSettle();
      expect(find.text('Invoice price: Rs. 750 per QR'), findsOneWidget, reason: tab);
    }
  });

  group('Invoices tab', () {
    final downloaded = <String>[];
    late InvoiceDownloaderFn original;

    setUp(() {
      downloaded.clear();
      original = invoiceDownloader;
      invoiceDownloader = (invoice) async => downloaded.add(invoice.numberText);
    });
    tearDown(() => invoiceDownloader = original);

    Future<void> openInvoices(WidgetTester tester) async {
      await tester.tap(find.text('Invoices'));
      await tester.pumpAndSettle();
    }

    FakeSalesRepository withInvoices() => teamRepo()
      ..invoicePrice = 1500
      ..invoices.addAll(const [
        Invoice(
          shopId: 'shop-122',
          number: 1,
          qrCode: 'QR122',
          clientName: 'Sunrise Bakery',
          amount: 1500,
          soldByUid: 'u1',
          soldByName: 'Ravi',
          createdByUid: 'u1',
          createdByName: 'Ravi',
        ),
        Invoice(
          shopId: 'shop-123',
          number: 2,
          qrCode: 'QR123',
          clientName: 'Moonlight Cafe',
          amount: 1500,
          soldByUid: 'u2',
          soldByName: 'Anu',
          createdByUid: 'admin-uid',
          createdByName: 'Admin',
        ),
      ]);

    testWidgets('with nothing yet it says so, asks for a price, and counts what is waiting', (
      tester,
    ) async {
      await pumpTeam(tester, teamRepo());
      await openInvoices(tester);

      expect(find.text('Invoice price not set'), findsOneWidget);
      expect(find.text('Set price'), findsOneWidget);
      expect(find.textContaining('No invoices yet'), findsOneWidget);
      // QR122 and QR123 are sold and have no invoice.
      expect(find.text('Sold, not invoiced'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('lists every invoice with who sold it and who made it, plus totals', (
      tester,
    ) async {
      await pumpTeam(tester, withInvoices());
      await openInvoices(tester);

      expect(find.text('Invoice price: Rs. 1,500 per QR'), findsOneWidget);
      expect(find.text('Rs. 3,000'), findsOneWidget, reason: 'total billed');
      expect(find.text('FSQ-0002'), findsOneWidget);
      expect(find.text('FSQ-0001'), findsOneWidget);
      expect(find.text('Sunrise Bakery'), findsOneWidget);
      expect(find.textContaining('Sold by Ravi  -  Made by Ravi'), findsOneWidget);
      expect(find.textContaining('Sold by Anu  -  Made by Admin'), findsOneWidget);
      // The by-sales-person summary.
      expect(find.textContaining('1 invoice (1 made by them)'), findsOneWidget);
      expect(find.text('2 of 2 invoices'), findsOneWidget);
    });

    testWidgets('search and the made-by filter narrow the list', (tester) async {
      await pumpTeam(tester, withInvoices());
      await openInvoices(tester);

      await tester.enterText(find.byType(TextField).first, 'moon');
      await tester.pump();
      expect(find.text('Moonlight Cafe'), findsOneWidget);
      expect(find.text('Sunrise Bakery'), findsNothing);
      expect(find.text('1 of 2 invoices'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'nobody');
      await tester.pump();
      expect(find.text('No invoices match.'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump();
      await tester.tap(find.text('Made by anyone'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Made by sales person').last);
      await tester.pumpAndSettle();
      expect(find.text('Sunrise Bakery'), findsOneWidget);
      expect(find.text('Moonlight Cafe'), findsNothing);
    });

    testWidgets('an invoice can be downloaded again from the list', (tester) async {
      await pumpTeam(tester, withInvoices());
      await openInvoices(tester);

      await tester.tap(find.text('Download FSQ-0002'));
      await tester.pumpAndSettle();
      expect(downloaded, ['FSQ-0002']);
    });

    testWidgets('setting the price refuses a bad one, then saves a good one', (
      tester,
    ) async {
      final repo = teamRepo();
      await pumpTeam(tester, repo);
      await openInvoices(tester);

      await tester.tap(find.text('Set price'));
      await tester.pumpAndSettle();
      expect(find.text('Invoice price per QR'), findsOneWidget);

      await tester.enterText(inDialog(find.byType(TextField)), '12.5');
      await tester.tap(find.text('Save price'));
      await tester.pumpAndSettle();
      expect(find.textContaining('whole number'), findsOneWidget);
      expect(repo.invoicePrice, isNull);

      await tester.enterText(inDialog(find.byType(TextField)), '1800');
      await tester.tap(find.text('Save price'));
      await tester.pumpAndSettle();

      expect(repo.invoicePrice, 1800);
      expect(find.text('Invoice price: Rs. 1,800 per QR'), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
    });
  });

  group('Report tab', () {
    testWidgets('counts sales for the chosen dates and offers both downloads', (tester) async {
      await pumpTeam(tester, teamRepo());
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All time'));
      await tester.pumpAndSettle();

      expect(find.textContaining('2 sold'), findsWidgets);
      expect(find.text('Sold in this range (2)'), findsOneWidget);
      for (final label in ['Download summary (CSV)', 'Download sold list (CSV)']) {
        final button = find.widgetWithText(OutlinedButton, label);
        expect(button, findsOneWidget, reason: label);
        expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
      }
    });

    testWidgets('a range with no sales says so and disables the sold-list download', (tester) async {
      await pumpTeam(
        tester,
        FakeSalesRepository(users: [ravi], assignments: [assignmentFor(121)]),
      );
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Nothing sold in this date range'), findsOneWidget);
      final soldList = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Download sold list (CSV)'),
      );
      expect(soldList.onPressed, isNull);
    });
  });
}

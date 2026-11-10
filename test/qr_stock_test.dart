import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:reviewqr_admin/models/assignment_model.dart';
import 'package:reviewqr_admin/models/shop_model.dart';
import 'package:reviewqr_admin/providers/navigation_provider.dart';
import 'package:reviewqr_admin/providers/qr_provider.dart';
import 'package:reviewqr_admin/providers/sales_admin_provider.dart';
import 'package:reviewqr_admin/providers/shop_provider.dart';
import 'package:reviewqr_admin/screens/my_qr_codes/my_qr_codes_screen.dart';
import 'package:reviewqr_admin/utils/qr_stock.dart';

import 'support/fake_providers.dart';
import 'support/fake_sales_repository.dart';

void main() {
  group('isDemoShopName', () {
    test('only the Demo QR placeholder counts', () {
      expect(isDemoShopName('Demo QR123'), isTrue);
      expect(isDemoShopName('  demo qr7 '), isTrue);
      expect(isDemoShopName('D Squad'), isFalse);
      expect(isDemoShopName('Demo QR123 Bakery'), isFalse);
      expect(isDemoShopName('Demo QR'), isFalse);
      expect(isDemoShopName(''), isFalse);
    });
  });

  group('qrStockOf', () {
    final demo = shopFor(121);
    final client = shopFor(122)..shopName = 'D Squad';
    final held = assignmentFor(121);
    final sold = assignmentFor(121, locked: true, soldAt: DateTime(2026, 11, 5));

    test('an unassigned demo QR is free', () {
      expect(qrStockOf(shop: demo, assignment: null), QrStock.free);
    });

    test('an unsold QR held by a sales person is with them', () {
      expect(qrStockOf(shop: demo, assignment: held), QrStock.withSalesPerson);
    });

    test('a QR a sales person set up is sold', () {
      expect(qrStockOf(shop: demo, assignment: sold), QrStock.sold);
      // Even if its shop name was later reset.
      expect(qrStockOf(shop: client, assignment: sold), QrStock.sold);
    });

    test('a QR whose shop already has a client name is sold, held or not', () {
      expect(qrStockOf(shop: client, assignment: null), QrStock.sold);
      expect(qrStockOf(shop: client, assignment: held), QrStock.sold);
    });

    test('a QR with no shop cannot be told', () {
      expect(qrStockOf(shop: null, assignment: null), QrStock.unknown);
      expect(qrStockOf(shop: null, assignment: held), QrStock.unknown);
      // A sale on record still counts, shop or not.
      expect(qrStockOf(shop: null, assignment: sold), QrStock.sold);
    });
  });

  group('QrStockCounts', () {
    test('adds each state up, and works out what is left to sell', () {
      final c = QrStockCounts.of([
        QrStock.sold,
        QrStock.sold,
        QrStock.withSalesPerson,
        QrStock.free,
        QrStock.free,
        QrStock.free,
        QrStock.unknown,
      ]);
      expect(c.sold, 2);
      expect(c.withSalesPerson, 1);
      expect(c.free, 3);
      expect(c.unknown, 1);
      expect(c.notSold, 4);
      expect(c.total, 7);
    });

    test('nothing is zero everywhere', () {
      final c = QrStockCounts.of(const []);
      expect([c.sold, c.notSold, c.total], [0, 0, 0]);
    });
  });

  group('My QR Codes screen', () {
    // 121 free, 122 with Ravi, 123 sold by Anu, 124 a real client (no rep),
    // 125 free, 126 with Anu.
    FakeSalesRepository repo() => FakeSalesRepository(
      users: [ravi, anu],
      assignments: [
        assignmentFor(122),
        assignmentFor(123, uid: 'u2', name: 'Anu', locked: true, soldAt: DateTime(2026, 11, 5)),
        assignmentFor(126, uid: 'u2', name: 'Anu'),
      ],
    );

    List<ShopModel> shops() => [
      for (var n = 121; n <= 126; n++) n == 124 ? (shopFor(n)..shopName = 'D Squad') : shopFor(n),
    ];

    Future<SalesAdminProvider> pump(
      WidgetTester tester, {
      FakeSalesRepository? sales,
    }) async {
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final provider = SalesAdminProvider(sales ?? repo());
      await provider.load();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => NavigationProvider()),
            ChangeNotifierProvider<SalesAdminProvider>.value(value: provider),
            ChangeNotifierProvider<QrProvider>.value(
              value: FakeQrProvider([for (var n = 121; n <= 126; n++) qrFor(n)]),
            ),
            ChangeNotifierProvider<ShopProvider>.value(value: FakeShopProvider(shops())),
          ],
          child: const MaterialApp(home: Scaffold(body: MyQrCodesScreen())),
        ),
      );
      await tester.pump();
      return provider;
    }

    Set<String> shownCodes(WidgetTester tester) => {
      for (var n = 121; n <= 126; n++)
        if (find.text('QR$n').evaluate().isNotEmpty) 'QR$n',
    };

    testWidgets('says how many are sold and how many are left to sell', (tester) async {
      await pump(tester);

      expect(
        find.text('2 sold  -  4 left to sell (2 with sales people, 2 free)'),
        findsOneWidget,
      );
      expect(find.text('All (6)'), findsOneWidget);
      expect(find.text('Sold (2)'), findsOneWidget);
      expect(find.text('Not sold (4)'), findsOneWidget);
      expect(find.text('With a sales person (2)'), findsOneWidget);
      expect(find.text('Free to assign (2)'), findsOneWidget);
    });

    testWidgets('every filter lists exactly the right QR codes', (tester) async {
      await pump(tester);
      expect(shownCodes(tester), {'QR121', 'QR122', 'QR123', 'QR124', 'QR125', 'QR126'});

      await tester.tap(find.text('Sold (2)'));
      await tester.pumpAndSettle();
      expect(shownCodes(tester), {'QR123', 'QR124'});
      expect(find.text('2 of 6 QR codes match.'), findsOneWidget);

      await tester.tap(find.text('Not sold (4)'));
      await tester.pumpAndSettle();
      expect(shownCodes(tester), {'QR121', 'QR122', 'QR125', 'QR126'});

      await tester.tap(find.text('With a sales person (2)'));
      await tester.pumpAndSettle();
      expect(shownCodes(tester), {'QR122', 'QR126'});

      await tester.tap(find.text('Free to assign (2)'));
      await tester.pumpAndSettle();
      expect(shownCodes(tester), {'QR121', 'QR125'});

      await tester.tap(find.text('All (6)'));
      await tester.pumpAndSettle();
      expect(shownCodes(tester).length, 6);
      expect(find.text('6 saved QR codes.'), findsOneWidget);
    });

    testWidgets('each card says where it stands', (tester) async {
      await pump(tester);

      expect(find.text('Not sold - free to assign'), findsNWidgets(2)); // 121, 125
      expect(find.text('Not sold - with Ravi'), findsOneWidget); // 122
      expect(find.text('Not sold - with Anu'), findsOneWidget); // 126
      expect(find.textContaining('Sold by Anu on'), findsOneWidget); // 123
      expect(find.text('Sold - set up for a client'), findsOneWidget); // 124
    });

    testWidgets('the filter and the search work together', (tester) async {
      await pump(tester);

      await tester.tap(find.text('Not sold (4)'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Anu');
      await tester.pumpAndSettle();
      expect(shownCodes(tester), {'QR126'}, reason: 'not sold, and held by Anu');

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No QR codes match.'), findsOneWidget);
    });

    testWidgets('warns when the sales team could not be loaded', (tester) async {
      await pump(tester, sales: _SalesDown());
      expect(find.textContaining('could not be loaded'), findsOneWidget);
    });
  });
}

class _SalesDown extends FakeSalesRepository {
  @override
  Future<List<Assignment>> fetchAllAssignments() => throw Exception('offline');
}

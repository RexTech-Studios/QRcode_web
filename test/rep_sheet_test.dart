import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:reviewqr_admin/providers/rep_provider.dart';
import 'package:reviewqr_admin/screens/sales/rep_home_screen.dart';
import 'package:reviewqr_admin/services/google_sheets_service.dart';
import 'package:reviewqr_admin/services/sales_repository.dart';

import 'support/fake_sales_repository.dart';

const goodSheet = 'https://docs.google.com/spreadsheets/d/1AbC-dEf_123/edit';

FakeSalesRepository repoFor() => FakeSalesRepository(
  users: [ravi],
  assignments: [
    assignmentFor(121), // no sheet yet
    assignmentFor(122, locked: true, soldAt: DateTime(2026, 11, 5)), // has a sheet
  ],
  shops: {
    'shop-121': shopFor(121),
    'shop-122': shopFor(122, sheetsUrl: goodSheet),
  },
);

RepProvider providerFor(
  FakeSalesRepository repo, {
  Future<SheetResult> Function(String)? createSheet,
  List<String>? asked,
}) => RepProvider(
  repo,
  renameSheet: ({required googleSheetsUrl, required shopName}) async => true,
  createSheet:
      createSheet ??
      (name) async {
        asked?.add(name);
        return const SheetResult(url: goodSheet);
      },
);

void main() {
  group('isSafeSheetUrl', () {
    test('accepts Google Sheets links', () {
      expect(RepProvider.isSafeSheetUrl(goodSheet), isTrue);
      expect(
        RepProvider.isSafeSheetUrl('https://docs.google.com/spreadsheets/d/abc123'),
        isTrue,
      );
    });

    test('refuses anything else', () {
      for (final bad in [
        '',
        'http://docs.google.com/spreadsheets/d/abc',
        'https://evil.example/spreadsheets/d/abc',
        'https://docs.google.com.evil.example/spreadsheets/d/abc',
        'https://docs.google.com/document/d/abc',
        'https://docs.google.com/spreadsheets/d/',
        'https://docs.google.com/spreadsheets/d/abc def',
        'javascript:alert(1)',
        'https://docs.google.com/spreadsheets/d/${'a' * 300}',
      ]) {
        expect(RepProvider.isSafeSheetUrl(bad), isFalse, reason: bad);
      }
    });
  });

  group('generateSheet', () {
    Future<RepProvider> loaded(FakeSalesRepository repo, RepProvider p) async {
      await p.load(ravi);
      return p;
    }

    RepItem itemFor(RepProvider p, String code) =>
        p.items.firstWhere((i) => i.assignment.qrCode == code);

    test('creates a sheet named for the shop and attaches it', () async {
      final repo = repoFor();
      final asked = <String>[];
      final p = await loaded(repo, providerFor(repo, asked: asked));

      final updated = await p.generateSheet(itemFor(p, 'QR121'));

      expect(asked, ['Demo QR121']);
      expect(repo.savedSheets.single, (shopId: 'shop-121', url: goodSheet));
      expect(updated.shop?.googleSheetsUrl, goodSheet);
      expect(itemFor(p, 'QR121').shop?.googleSheetsUrl, goodSheet);
      expect(itemFor(p, 'QR121').shop?.shopName, 'Demo QR121');
    });

    test('does nothing when the shop already has a sheet', () async {
      final repo = repoFor();
      final asked = <String>[];
      final p = await loaded(repo, providerFor(repo, asked: asked));

      await p.generateSheet(itemFor(p, 'QR122'));

      expect(asked, isEmpty);
      expect(repo.savedSheets, isEmpty);
    });

    test('a service failure is explained and nothing is saved', () async {
      final repo = repoFor();
      final p = await loaded(
        repo,
        providerFor(
          repo,
          createSheet: (_) async =>
              const SheetResult(error: 'Could not reach the sheet service: x'),
        ),
      );

      await expectLater(
        p.generateSheet(itemFor(p, 'QR121')),
        throwsA(
          isA<SalesException>().having(
            (e) => e.message,
            'message',
            contains('sheet service'),
          ),
        ),
      );
      expect(repo.savedSheets, isEmpty);
      expect(itemFor(p, 'QR121').shop?.googleSheetsUrl, isNull);
    });

    test('a link that is not a Google Sheet is never saved', () async {
      final repo = repoFor();
      final p = await loaded(
        repo,
        providerFor(
          repo,
          createSheet: (_) async =>
              const SheetResult(url: 'https://evil.example/x'),
        ),
      );

      await expectLater(
        p.generateSheet(itemFor(p, 'QR121')),
        throwsA(isA<SalesException>()),
      );
      expect(repo.calls.where((c) => c.startsWith('sheet:')), isEmpty);
    });

    test('a refused save explains it and the shop stays without a sheet', () async {
      final repo = repoFor()
        ..sheetSaveError = Exception('Missing or insufficient permissions.');
      final p = await loaded(repo, providerFor(repo));

      await expectLater(
        p.generateSheet(itemFor(p, 'QR121')),
        throwsA(
          isA<SalesException>().having(
            (e) => e.message,
            'message',
            contains('could not be attached'),
          ),
        ),
      );
      expect(itemFor(p, 'QR121').shop?.googleSheetsUrl, isNull);
    });

    test('an offline save says to check the connection', () async {
      final repo = repoFor()..sheetSaveError = Exception('network down');
      final p = await loaded(repo, providerFor(repo));

      await expectLater(
        p.generateSheet(itemFor(p, 'QR121')),
        throwsA(
          isA<SalesException>().having(
            (e) => e.message,
            'message',
            contains('connection'),
          ),
        ),
      );
    });

    test('a QR whose shop cannot be found is refused', () async {
      final repo = FakeSalesRepository(
        users: [ravi],
        assignments: [assignmentFor(121)],
      );
      final p = await loaded(repo, providerFor(repo));

      await expectLater(
        p.generateSheet(itemFor(p, 'QR121')),
        throwsA(isA<SalesException>()),
      );
    });
  });

  group('My QR codes screen', () {
    Future<(RepProvider, FakeSalesRepository)> pump(
      WidgetTester tester, {
      Future<SheetResult> Function(String)? createSheet,
      Size size = const Size(800, 1600),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = repoFor();
      final provider = providerFor(repo, createSheet: createSheet);
      await provider.load(ravi);
      await tester.pumpWidget(
        ChangeNotifierProvider<RepProvider>.value(
          value: provider,
          child: const MaterialApp(home: RepHomeScreen()),
        ),
      );
      await tester.pump();
      return (provider, repo);
    }

    testWidgets('a shop with a sheet offers to open it, one without offers to generate', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('Open sheet'), findsOneWidget);
      expect(find.text('Generate sheet'), findsOneWidget);
    });

    testWidgets('generating attaches the sheet and the button becomes Open sheet', (
      tester,
    ) async {
      final (_, repo) = await pump(tester);

      await tester.tap(find.text('Generate sheet'));
      await tester.pumpAndSettle();

      expect(repo.savedSheets.single.shopId, 'shop-121');
      expect(find.text('Generate sheet'), findsNothing);
      expect(find.text('Open sheet'), findsNWidgets(2));
      expect(find.text('Google Sheet created for this shop.'), findsOneWidget);
    });

    testWidgets('a failure is shown and the button stays available to retry', (
      tester,
    ) async {
      final (_, repo) = await pump(
        tester,
        createSheet: (_) async => const SheetResult(error: 'Sheet service is down.'),
      );

      await tester.tap(find.text('Generate sheet'));
      await tester.pumpAndSettle();

      expect(find.text('Sheet service is down.'), findsOneWidget);
      expect(find.text('Generate sheet'), findsOneWidget);
      expect(repo.savedSheets, isEmpty);
    });

    testWidgets('fits a 320px phone without overflow', (tester) async {
      await pump(tester, size: const Size(320, 900));
      expect(tester.takeException(), isNull);
    });
  });
}

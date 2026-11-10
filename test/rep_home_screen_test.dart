import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:reviewqr_admin/providers/rep_provider.dart';
import 'package:reviewqr_admin/screens/sales/rep_home_screen.dart';

import 'support/fake_sales_repository.dart';

const goodUrl = 'https://g.page/r/CcMyClient/review';

Future<RepProvider> pumpRepHome(
  WidgetTester tester,
  FakeSalesRepository repo, {
  Size size = const Size(800, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final provider = RepProvider(
    repo,
    renameSheet: ({required googleSheetsUrl, required shopName}) async => true,
  );
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

/// The two fields inside the open dialog. The page's own search box is still
/// in the tree behind it, so a bare find.byType(TextField) would hit that.
Finder dialogFields() => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.byType(TextField),
);

FakeSalesRepository repoWithTwoOfMine() => FakeSalesRepository(
  users: [ravi, anu],
  assignments: [
    assignmentFor(121),
    assignmentFor(122, locked: true, soldAt: DateTime(2026, 11, 5)),
    assignmentFor(123, uid: 'u2', name: 'Anu'),
  ],
  shops: {
    'shop-121': shopFor(121),
    'shop-122': shopFor(122),
    'shop-123': shopFor(123),
  },
);

void main() {
  testWidgets('shows only my QR codes, with counts and the right status', (
    tester,
  ) async {
    await pumpRepHome(tester, repoWithTwoOfMine());

    expect(find.text('QR121'), findsOneWidget);
    expect(find.text('QR122'), findsOneWidget);
    expect(find.text('QR123'), findsNothing, reason: "that one is Anu's");
    expect(find.text('Ready to set up'), findsOneWidget);
    expect(find.text('Saved - locked'), findsOneWidget);
    expect(find.text('Set up for client'), findsOneWidget);
    expect(
      find.textContaining('ask the admin to unlock'),
      findsOneWidget,
      reason: 'a locked QR explains how to change it',
    );
  });

  testWidgets('search narrows the list, and says so when nothing matches', (
    tester,
  ) async {
    await pumpRepHome(tester, repoWithTwoOfMine());

    await tester.enterText(find.byType(TextField).first, '122');
    await tester.pump();
    expect(find.text('QR122'), findsOneWidget);
    expect(find.text('QR121'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '999');
    await tester.pump();
    expect(find.textContaining('None of your QR codes match'), findsOneWidget);
  });

  testWidgets('says so when the admin has not assigned anything yet', (
    tester,
  ) async {
    await pumpRepHome(tester, FakeSalesRepository(users: [ravi]));
    expect(find.textContaining('No QR codes have been assigned'), findsOneWidget);
  });

  testWidgets('fits a 320px phone without overflow', (tester) async {
    await pumpRepHome(tester, repoWithTwoOfMine(), size: const Size(320, 640));
    expect(tester.takeException(), isNull);
    expect(find.text('QR121'), findsOneWidget);
  });

  group('set up for client', () {
    Future<void> openSetup(WidgetTester tester) async {
      await tester.tap(find.text('Set up for client'));
      await tester.pumpAndSettle();
    }

    testWidgets('opens pre-filled with the current name and says it is one-time', (
      tester,
    ) async {
      await pumpRepHome(tester, repoWithTwoOfMine());
      await openSetup(tester);

      expect(find.text('Demo QR121'), findsWidgets);
      expect(find.textContaining('only once'), findsOneWidget);
    });

    testWidgets('an invalid link is refused before anything is saved', (
      tester,
    ) async {
      final repo = repoWithTwoOfMine();
      await pumpRepHome(tester, repo);
      await openSetup(tester);

      final fields = dialogFields();
      await tester.enterText(fields.at(0), 'Cafe Aroma');
      await tester.enterText(fields.at(1), 'http://evil.example/x');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.textContaining('valid Google Maps review link'), findsOneWidget);
      expect(find.text('Save and lock?'), findsNothing);
      expect(repo.calls, isEmpty);
    });

    testWidgets('going back from the confirmation saves nothing', (tester) async {
      final repo = repoWithTwoOfMine();
      await pumpRepHome(tester, repo);
      await openSetup(tester);

      final fields = dialogFields();
      await tester.enterText(fields.at(0), 'Cafe Aroma');
      await tester.enterText(fields.at(1), goodUrl);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Save and lock?'), findsOneWidget);

      await tester.tap(find.text('Go back'));
      await tester.pumpAndSettle();
      expect(repo.calls, isEmpty);
      expect(find.text('Set up for client'), findsWidgets);
    });

    testWidgets('confirming saves once and locks the QR', (tester) async {
      final repo = repoWithTwoOfMine();
      final provider = await pumpRepHome(tester, repo);
      await openSetup(tester);

      final fields = dialogFields();
      await tester.enterText(fields.at(0), 'Cafe Aroma');
      await tester.enterText(fields.at(1), goodUrl);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save and lock'));
      await tester.pumpAndSettle();

      expect(repo.calls, ['setup:shop-121']);
      expect(repo.lastSetup?.name, 'Cafe Aroma');
      expect(repo.lastSetup?.url, goodUrl);
      final item = provider.items.firstWhere(
        (i) => i.assignment.qrCode == 'QR121',
      );
      expect(item.assignment.locked, isTrue);
      expect(find.text('Cafe Aroma'), findsOneWidget);
      expect(find.text('Set up for client'), findsNothing);
      expect(find.text('Saved - locked'), findsNWidgets(2));
    });

    testWidgets('a failed save shows the reason and keeps the QR editable', (
      tester,
    ) async {
      final repo = repoWithTwoOfMine()
        ..saveError = Exception('[cloud_firestore/permission-denied] nope');
      final provider = await pumpRepHome(tester, repo);
      await openSetup(tester);

      final fields = dialogFields();
      await tester.enterText(fields.at(0), 'Cafe Aroma');
      await tester.enterText(fields.at(1), goodUrl);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save and lock'));
      await tester.pumpAndSettle();

      expect(find.textContaining('locked'), findsWidgets);
      expect(
        provider.items.firstWhere((i) => i.assignment.qrCode == 'QR121').assignment.locked,
        isFalse,
      );
      expect(find.widgetWithText(ElevatedButton, 'Save'), findsOneWidget);
    });
  });
}

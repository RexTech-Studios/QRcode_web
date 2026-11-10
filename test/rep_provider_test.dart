import 'package:flutter_test/flutter_test.dart';
import 'package:reviewqr_admin/models/assignment_model.dart';
import 'package:reviewqr_admin/providers/rep_provider.dart';
import 'package:reviewqr_admin/services/sales_repository.dart';

import 'support/fake_sales_repository.dart';

void main() {
  const goodUrl =
      'https://www.google.com/maps/place/Rextech+Studios/@10.0,76.3,858m/data=!3m1?entry=ttu';

  FakeSalesRepository repoWithTwoOfMine() => FakeSalesRepository(
    users: [ravi, anu],
    assignments: [
      assignmentFor(121),
      assignmentFor(122, locked: true, soldAt: DateTime(2026, 11, 5)),
      assignmentFor(123, uid: 'u2', name: 'Anu'),
    ],
    shops: {
      'shop-121': shopFor(
        121,
        sheetsUrl: 'https://docs.google.com/spreadsheets/d/abc/edit',
      ),
      'shop-122': shopFor(122),
      'shop-123': shopFor(123),
    },
  );

  group('load', () {
    test(
      'shows only the QR codes assigned to this sales person, with their shops',
      () async {
        final p = RepProvider(repoWithTwoOfMine(), renameSheet: _noRename);
        await p.load(ravi);
        expect(p.items.map((i) => i.assignment.qrCode), ['QR121', 'QR122']);
        expect(p.items.first.shopName, 'Demo QR121');
        expect(p.pendingCount, 1);
        expect(p.doneCount, 1);
      },
    );

    test('a shop that cannot be read still lists, with a clear name', () async {
      final repo = FakeSalesRepository(assignments: [assignmentFor(121)]);
      final p = RepProvider(repo, renameSheet: _noRename);
      await p.load(ravi);
      expect(p.items.single.shopName, 'Shop not found');
    });

    test('a failed load is a message, not a crash', () async {
      final p = RepProvider(_FailingRepo(), renameSheet: _noRename);
      await p.load(ravi);
      expect(p.loadError, isNotNull);
      expect(p.items, isEmpty);
    });
  });

  group('validateSetup', () {
    test('accepts a normal name and Google Maps links', () {
      expect(RepProvider.validateSetup('Cafe Aroma', goodUrl), isNull);
      expect(
        RepProvider.validateSetup('Cafe', 'https://g.page/r/abc/review'),
        isNull,
      );
      expect(
        RepProvider.validateSetup('Cafe', 'https://maps.app.goo.gl/AbCd123'),
        isNull,
      );
    });

    test('rejects an empty name and an over-long name', () {
      expect(RepProvider.validateSetup('   ', goodUrl), isNotNull);
      expect(RepProvider.validateSetup('x' * 101, goodUrl), isNotNull);
      expect(RepProvider.validateSetup('x' * 100, goodUrl), isNull);
    });

    test('rejects links that are not an https Google link', () {
      for (final bad in [
        '',
        'not a link',
        'http://www.google.com/maps/place/x',
        'https://example.com/maps',
        'https://google.com.evil.com/maps',
        'https://evilgoogle.com/maps',
        'https://google.com@evil.com/maps',
        'javascript:alert(1)',
        'https://www.google.com/maps/place/two words',
      ]) {
        expect(RepProvider.validateSetup('Cafe', bad), isNotNull, reason: bad);
      }
    });

    test('rejects a link longer than the rules allow', () {
      final long = 'https://www.google.com/maps/place/${'a' * 2000}';
      expect(RepProvider.validateSetup('Cafe', long), isNotNull);
    });
  });

  group('saveSetup', () {
    test(
      'saves the trimmed values, locks the QR and records the sale',
      () async {
        final repo = repoWithTwoOfMine();
        String? renamedTo;
        String? renamedSheet;
        final p = RepProvider(
          repo,
          renameSheet: ({required googleSheetsUrl, required shopName}) async {
            renamedTo = shopName;
            renamedSheet = googleSheetsUrl;
            return true;
          },
        );
        await p.load(ravi);
        final item = p.items.first;

        await p.saveSetup(
          item,
          shopName: '  Cafe Aroma  ',
          reviewUrl: ' $goodUrl ',
        );

        expect(repo.lastSetup?.name, 'Cafe Aroma');
        expect(repo.lastSetup?.url, goodUrl);
        expect(
          repo.lastSetup?.hadSoldAt,
          isFalse,
          reason: 'first edit records the sale',
        );
        final updated = p.items.first;
        expect(updated.assignment.locked, isTrue);
        expect(updated.assignment.soldAt, isNotNull);
        expect(updated.shopName, 'Cafe Aroma');
        expect(renamedTo, 'Cafe Aroma');
        expect(renamedSheet, 'https://docs.google.com/spreadsheets/d/abc/edit');
      },
    );

    test('a second save is blocked, and nothing is sent', () async {
      final repo = repoWithTwoOfMine();
      final p = RepProvider(repo, renameSheet: _noRename);
      await p.load(ravi);
      await p.saveSetup(
        p.items.first,
        shopName: 'Cafe Aroma',
        reviewUrl: goodUrl,
      );
      repo.calls.clear();

      await expectLater(
        p.saveSetup(p.items.first, shopName: 'Another', reviewUrl: goodUrl),
        throwsA(isA<SalesException>()),
      );
      expect(repo.calls, isEmpty);
    });

    test('an already-locked QR cannot be edited', () async {
      final repo = repoWithTwoOfMine();
      final p = RepProvider(repo, renameSheet: _noRename);
      await p.load(ravi);
      final locked = p.items.firstWhere((i) => i.assignment.qrCode == 'QR122');
      await expectLater(
        p.saveSetup(locked, shopName: 'Cafe', reviewUrl: goodUrl),
        throwsA(isA<SalesException>()),
      );
      expect(repo.calls, isEmpty);
    });

    test(
      'after the admin unlocks it, the sale date is kept and not re-recorded',
      () async {
        final sold = DateTime(2026, 11, 5);
        final repo = FakeSalesRepository(
          assignments: [assignmentFor(122, locked: false, soldAt: sold)],
          shops: {'shop-122': shopFor(122)},
        );
        final p = RepProvider(repo, renameSheet: _noRename);
        await p.load(ravi);

        await p.saveSetup(
          p.items.single,
          shopName: 'Cafe Two',
          reviewUrl: goodUrl,
        );

        expect(
          repo.lastSetup?.hadSoldAt,
          isTrue,
          reason: 'soldAt must not be sent again',
        );
        expect(p.items.single.assignment.soldAt, sold);
        expect(p.items.single.assignment.locked, isTrue);
      },
    );

    test('an invalid link is rejected before anything is sent', () async {
      final repo = repoWithTwoOfMine();
      final p = RepProvider(repo, renameSheet: _noRename);
      await p.load(ravi);
      await expectLater(
        p.saveSetup(
          p.items.first,
          shopName: 'Cafe',
          reviewUrl: 'https://evil.example/x',
        ),
        throwsA(isA<SalesException>()),
      );
      expect(repo.calls, isEmpty);
      expect(p.items.first.assignment.locked, isFalse);
    });

    test('a permission error leaves the QR unlocked and explains it', () async {
      final repo = repoWithTwoOfMine()
        ..saveError = Exception(
          '[cloud_firestore/permission-denied] Missing permissions',
        );
      final p = RepProvider(repo, renameSheet: _noRename);
      await p.load(ravi);
      Object? caught;
      try {
        await p.saveSetup(p.items.first, shopName: 'Cafe', reviewUrl: goodUrl);
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<SalesException>());
      expect((caught as SalesException).message, contains('locked'));
      expect(p.items.first.assignment.locked, isFalse);
    });

    test('a network error is reported without leaking the raw error', () async {
      final repo = repoWithTwoOfMine()
        ..saveError = Exception('socket exploded 10.0.0.1');
      final p = RepProvider(repo, renameSheet: _noRename);
      await p.load(ravi);
      Object? caught;
      try {
        await p.saveSetup(p.items.first, shopName: 'Cafe', reviewUrl: goodUrl);
      } catch (e) {
        caught = e;
      }
      expect((caught as SalesException).message, isNot(contains('10.0.0.1')));
    });

    test('a failed sheet rename does not undo the save', () async {
      final repo = repoWithTwoOfMine();
      final p = RepProvider(
        repo,
        renameSheet: ({required googleSheetsUrl, required shopName}) async =>
            throw Exception('apps script down'),
      );
      await p.load(ravi);
      await p.saveSetup(p.items.first, shopName: 'Cafe', reviewUrl: goodUrl);
      expect(p.items.first.assignment.locked, isTrue);
    });
  });
}

Future<bool> _noRename({
  required String? googleSheetsUrl,
  required String shopName,
}) async => true;

class _FailingRepo extends FakeSalesRepository {
  @override
  Future<List<Assignment>> fetchAssignmentsFor(String uid) async =>
      throw Exception('network down');
}

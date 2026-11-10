import 'package:flutter_test/flutter_test.dart';
import 'package:reviewqr_admin/models/sales_user_model.dart';
import 'package:reviewqr_admin/providers/sales_admin_provider.dart';
import 'package:reviewqr_admin/services/sales_repository.dart';

import 'support/fake_sales_repository.dart';

void main() {
  final qrCodes = [for (var n = 121; n <= 130; n++) qrFor(n)];

  SalesAdminProvider providerWith(FakeSalesRepository repo) =>
      SalesAdminProvider(repo);

  group('addSalesPerson', () {
    test('rejects an empty name, a bad email and a short password before calling Firebase', () async {
      final repo = FakeSalesRepository();
      final p = providerWith(repo);
      await expectLater(
        p.addSalesPerson(name: ' ', email: 'a@b.co', password: 'secret1'),
        throwsA(isA<SalesException>()),
      );
      await expectLater(
        p.addSalesPerson(
          name: 'Ravi',
          email: 'not-an-email',
          password: 'secret1',
        ),
        throwsA(isA<SalesException>()),
      );
      await expectLater(
        p.addSalesPerson(name: 'Ravi', email: 'a@b.co', password: '12345'),
        throwsA(isA<SalesException>()),
      );
      expect(repo.calls, isEmpty);
    });

    test('creates the account and lists people alphabetically', () async {
      final repo = FakeSalesRepository();
      final p = providerWith(repo);
      await p.addSalesPerson(
        name: 'Zed',
        email: 'zed@x.com',
        password: 'secret1',
      );
      await p.addSalesPerson(
        name: 'amy',
        email: 'amy@x.com',
        password: 'secret1',
      );
      expect(p.users.map((u) => u.name), ['amy', 'Zed']);
      expect(repo.calls, ['create:zed@x.com', 'create:amy@x.com']);
    });

    test(
      'a failure from Firebase reaches the caller and adds nobody',
      () async {
        final repo = FakeSalesRepository()
          ..createError = const SalesException('Email taken');
        final p = providerWith(repo);
        await expectLater(
          p.addSalesPerson(name: 'Ravi', email: 'r@x.com', password: 'secret1'),
          throwsA(isA<SalesException>()),
        );
        expect(p.users, isEmpty);
      },
    );
  });

  group('availableDemoQrNumbers', () {
    test('lists demo QR numbers nobody holds, in order', () async {
      final repo = FakeSalesRepository(
        assignments: [assignmentFor(121), assignmentFor(125, uid: 'u2', name: 'Anu')],
      );
      final p = providerWith(repo);
      await p.load();

      final free = p.availableDemoQrNumbers(
        qrCodes: qrCodes.reversed.toList(),
        shops: [for (var n = 121; n <= 130; n++) shopFor(n)],
      );
      expect(free, [122, 123, 124, 126, 127, 128, 129, 130]);
    });

    test('leaves out real client shops and QR codes with no number', () async {
      final p = providerWith(FakeSalesRepository());
      await p.load();

      final realClient = shopFor(122)..shopName = 'Sunrise Bakery';
      final free = p.availableDemoQrNumbers(
        qrCodes: [qrFor(121), qrFor(122), qrFor(123)..qrCode = ''],
        shops: [shopFor(121), realClient, shopFor(123)],
      );
      expect(free, [121]);
    });
  });

  group('planAssignment', () {
    test('a free QR is assigned', () {
      final p = providerWith(FakeSalesRepository());
      final plan = p.planAssignment(
        input: '121-123',
        qrCodes: qrCodes,
        rep: ravi,
      );
      expect(plan.toAssign.map((q) => q.qrCode), ['QR121', 'QR122', 'QR123']);
      expect(plan.hasProblems, isFalse);
      expect(plan.canApply, isTrue);
    });

    test('numbers that do not exist are reported, not ignored', () {
      final p = providerWith(FakeSalesRepository());
      final plan = p.planAssignment(
        input: '129-132',
        qrCodes: qrCodes,
        rep: ravi,
      );
      expect(plan.toAssign.map((q) => q.qrCode), ['QR129', 'QR130']);
      expect(plan.notFound, ['QR131', 'QR132']);
    });

    test('a QR already with this sales person is skipped', () async {
      final repo = FakeSalesRepository(assignments: [assignmentFor(121)]);
      final p = providerWith(repo);
      await p.load();
      final plan = p.planAssignment(
        input: '121-122',
        qrCodes: qrCodes,
        rep: ravi,
      );
      expect(plan.alreadyWithRep, ['QR121']);
      expect(plan.toAssign.map((q) => q.qrCode), ['QR122']);
    });

    test(
      'a pending QR held by someone else can be moved, and says so',
      () async {
        final repo = FakeSalesRepository(
          assignments: [assignmentFor(121, uid: 'u2', name: 'Anu')],
        );
        final p = providerWith(repo);
        await p.load();
        final plan = p.planAssignment(
          input: '121',
          qrCodes: qrCodes,
          rep: ravi,
        );
        expect(plan.toAssign.map((q) => q.qrCode), ['QR121']);
        expect(plan.moving.single.fromName, 'Anu');
      },
    );

    test('a sold QR is never reassigned', () async {
      final repo = FakeSalesRepository(
        assignments: [
          assignmentFor(
            121,
            uid: 'u2',
            name: 'Anu',
            locked: true,
            soldAt: DateTime(2026, 11, 5),
          ),
        ],
      );
      final p = providerWith(repo);
      await p.load();
      final plan = p.planAssignment(input: '121', qrCodes: qrCodes, rep: ravi);
      expect(plan.toAssign, isEmpty);
      expect(plan.blocked.single.reason, contains('sold'));
      expect(plan.canApply, isFalse);
    });

    test('a locked QR is never silently reassigned either', () async {
      final repo = FakeSalesRepository(
        assignments: [assignmentFor(121, uid: 'u2', name: 'Anu', locked: true)],
      );
      final p = providerWith(repo);
      await p.load();
      final plan = p.planAssignment(input: '121', qrCodes: qrCodes, rep: ravi);
      expect(plan.toAssign, isEmpty);
      expect(plan.blocked.single.reason, contains('locked'));
    });

    test('unreadable input is passed through as errors', () {
      final p = providerWith(FakeSalesRepository());
      final plan = p.planAssignment(
        input: '121, xyz',
        qrCodes: qrCodes,
        rep: ravi,
      );
      expect(plan.parseErrors, isNotEmpty);
      expect(plan.toAssign, hasLength(1));
    });
  });

  group('applyAssignment', () {
    test('writes the plan and refreshes the list', () async {
      final repo = FakeSalesRepository();
      final p = providerWith(repo);
      final plan = p.planAssignment(
        input: '121-123',
        qrCodes: qrCodes,
        rep: ravi,
      );
      final count = await p.applyAssignment(plan, ravi);
      expect(count, 3);
      expect(repo.lastAssigned, hasLength(3));
      expect(p.assignedCountFor('u1'), 3);
      expect(p.assignmentFor('shop-121')?.assignedToName, 'Ravi');
    });

    test('writes nothing when there is nothing to assign', () async {
      final repo = FakeSalesRepository();
      final p = providerWith(repo);
      final plan = p.planAssignment(input: '900', qrCodes: qrCodes, rep: ravi);
      expect(await p.applyAssignment(plan, ravi), 0);
      expect(repo.calls, isEmpty);
    });
  });

  group('unassign and unlock', () {
    test('a pending QR can be taken back', () async {
      final repo = FakeSalesRepository(assignments: [assignmentFor(121)]);
      final p = providerWith(repo);
      await p.load();
      await p.unassign(p.assignmentFor('shop-121')!);
      expect(p.assignmentFor('shop-121'), isNull);
      expect(repo.calls, contains('unassign:shop-121'));
    });

    test('a sold QR cannot be taken back', () async {
      final repo = FakeSalesRepository(
        assignments: [
          assignmentFor(121, locked: true, soldAt: DateTime(2026, 11, 5)),
        ],
      );
      final p = providerWith(repo);
      await p.load();
      await expectLater(
        p.unassign(p.assignmentFor('shop-121')!),
        throwsA(isA<SalesException>()),
      );
      expect(repo.calls, isEmpty);
    });

    test(
      'unlocking lets the sales person edit again and keeps the sale date',
      () async {
        final sold = DateTime(2026, 11, 5);
        final repo = FakeSalesRepository(
          assignments: [assignmentFor(121, locked: true, soldAt: sold)],
        );
        final p = providerWith(repo);
        await p.load();
        await p.unlock(p.assignmentFor('shop-121')!);
        final a = p.assignmentFor('shop-121')!;
        expect(a.locked, isFalse);
        expect(a.soldAt, sold);
        expect(repo.calls, contains('locked:shop-121:false'));
      },
    );
  });

  group('team', () {
    test('turning someone off keeps them listed but inactive', () async {
      final repo = FakeSalesRepository(users: [ravi]);
      final p = providerWith(repo);
      await p.load();
      await p.setActive(ravi, false);
      expect(p.userById('u1')?.active, isFalse);
      await p.setActive(p.userById('u1')!, true);
      expect(p.userById('u1')?.active, isTrue);
    });

    test('counts assigned, sold and pending', () async {
      final repo = FakeSalesRepository(
        users: [ravi, anu],
        assignments: [
          assignmentFor(121, locked: true, soldAt: DateTime(2026, 11, 5)),
          assignmentFor(122),
          assignmentFor(123, uid: 'u2', name: 'Anu'),
        ],
      );
      final p = providerWith(repo);
      await p.load();
      expect(p.assignedCountFor('u1'), 2);
      expect(p.soldCountFor('u1'), 1);
      expect(p.pendingCountFor('u1'), 1);
      expect(p.assignedCountFor('u2'), 1);
    });

    test('a failed load is kept as a message and does not throw', () async {
      final p = SalesAdminProvider(_FailingRepo());
      await p.load();
      expect(p.loadError, isNotNull);
      expect(p.loading, isFalse);
    });

    test('reset forgets everything', () async {
      final repo = FakeSalesRepository(
        users: [ravi],
        assignments: [assignmentFor(121)],
      );
      final p = providerWith(repo);
      await p.load();
      p.reset();
      expect(p.users, isEmpty);
      expect(p.assignments, isEmpty);
    });
  });
}

class _FailingRepo extends FakeSalesRepository {
  @override
  Future<List<SalesUser>> fetchUsers() async => throw Exception('network down');
}

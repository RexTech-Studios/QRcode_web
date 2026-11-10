import 'package:flutter_test/flutter_test.dart';
import 'package:reviewqr_admin/models/sales_user_model.dart';
import 'package:reviewqr_admin/providers/sales_admin_provider.dart';
import 'package:reviewqr_admin/services/sales_repository.dart';

import 'support/fake_sales_repository.dart';

void main() {
  final qrCodes = [for (var n = 121; n <= 130; n++) qrFor(n)];
  final shops = [for (var n = 121; n <= 130; n++) shopFor(n)];

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
        qrCodes: qrCodes, shops: shops,
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
        qrCodes: qrCodes, shops: shops,
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
        qrCodes: qrCodes, shops: shops,
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
          qrCodes: qrCodes, shops: shops,
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
      final plan = p.planAssignment(input: '121', qrCodes: qrCodes, shops: shops, rep: ravi);
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
      final plan = p.planAssignment(input: '121', qrCodes: qrCodes, shops: shops, rep: ravi);
      expect(plan.toAssign, isEmpty);
      expect(plan.blocked.single.reason, contains('locked'));
    });

    test('a QR whose shop is already a real client is never assigned, however it is typed', () {
      final p = providerWith(FakeSalesRepository());
      final withClient = [
        for (var n = 121; n <= 130; n++)
          n == 124 ? (shopFor(n)..shopName = 'D Squad') : shopFor(n),
      ];

      final typed = p.planAssignment(
        input: '124',
        qrCodes: qrCodes,
        shops: withClient,
        rep: ravi,
      );
      expect(typed.toAssign, isEmpty);
      expect(typed.blocked.single.code, 'QR124');
      expect(typed.blocked.single.reason, contains('D Squad'));
      expect(typed.canApply, isFalse);

      // In a range, only that one is held back.
      final range = p.planAssignment(
        input: '122-126',
        qrCodes: qrCodes,
        shops: withClient,
        rep: ravi,
      );
      expect(range.toAssign.map((q) => q.qrCode), ['QR122', 'QR123', 'QR125', 'QR126']);
      expect(range.blocked.map((b) => b.code), ['QR124']);
      expect(range.canApply, isTrue);
    });

    test('a QR whose shop cannot be found is not assigned either', () {
      final p = providerWith(FakeSalesRepository());
      final plan = p.planAssignment(
        input: '121-122',
        qrCodes: qrCodes,
        shops: [shopFor(121)],
        rep: ravi,
      );
      expect(plan.toAssign.map((q) => q.qrCode), ['QR121']);
      expect(plan.blocked.single.code, 'QR122');
    });

    test('a placeholder name with different capitals or spaces still counts as free', () {
      final p = providerWith(FakeSalesRepository());
      final plan = p.planAssignment(
        input: '121',
        qrCodes: qrCodes,
        shops: [shopFor(121)..shopName = '  demo qr121 '],
        rep: ravi,
      );
      expect(plan.toAssign.map((q) => q.qrCode), ['QR121']);
    });

    test('unreadable input is passed through as errors', () {
      final p = providerWith(FakeSalesRepository());
      final plan = p.planAssignment(
        input: '121, xyz',
        qrCodes: qrCodes,
        shops: shops,
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
        qrCodes: qrCodes, shops: shops,
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
      final plan = p.planAssignment(input: '900', qrCodes: qrCodes, shops: shops, rep: ravi);
      expect(await p.applyAssignment(plan, ravi), 0);
      expect(repo.calls, isEmpty);
    });
  });

  group('fixing mistakes', () {
    FakeSalesRepository repo() => FakeSalesRepository(
      users: [ravi, anu, const SalesUser(uid: 'u3', name: 'Old Joe', email: 'j@x.com', active: false)],
      assignments: [
        assignmentFor(121), // Ravi, not set up
        assignmentFor(122), // Ravi, not set up
        assignmentFor(123, locked: true, soldAt: DateTime(2026, 11, 5)), // Ravi, sold
        assignmentFor(124, uid: 'u2', name: 'Anu'), // Anu, not set up
      ],
    );

    Future<SalesAdminProvider> loaded(FakeSalesRepository r) async {
      final p = providerWith(r);
      await p.load();
      return p;
    }

    group('rename', () {
      test('refuses an empty or very long name before writing', () async {
        final r = repo();
        final p = await loaded(r);
        await expectLater(p.renameSalesPerson(ravi, '  '), throwsA(isA<SalesException>()));
        await expectLater(p.renameSalesPerson(ravi, 'x' * 101), throwsA(isA<SalesException>()));
        expect(r.calls, isEmpty);
      });

      test('an unchanged name writes nothing', () async {
        final r = repo();
        final p = await loaded(r);
        await p.renameSalesPerson(ravi, ' Ravi ');
        expect(r.calls, isEmpty);
      });

      test('changes the name everywhere it is shown', () async {
        final r = repo();
        final p = await loaded(r);
        await p.renameSalesPerson(ravi, 'Ravindran');

        expect(r.calls.single, 'rename:u1:Ravindran:shop-121,shop-122,shop-123');
        expect(p.userById('u1')?.name, 'Ravindran');
        expect(
          p.assignments.where((a) => a.assignedTo == 'u1').map((a) => a.assignedToName).toSet(),
          {'Ravindran'},
        );
        expect(p.assignmentFor('shop-124')?.assignedToName, 'Anu', reason: "someone else's is untouched");
      });

      test('a failed write changes nothing on screen', () async {
        final r = repo()..manageError = Exception('network down');
        final p = await loaded(r);
        await expectLater(p.renameSalesPerson(ravi, 'Ravindran'), throwsA(isA<Exception>()));
        expect(p.userById('u1')?.name, 'Ravi');
      });
    });

    group('take back', () {
      test('several unsold QR codes at once', () async {
        final r = repo();
        final p = await loaded(r);
        final count = await p.takeBack([p.assignmentFor('shop-121')!, p.assignmentFor('shop-122')!]);
        expect(count, 2);
        expect(r.calls.single, 'unassignMany:shop-121,shop-122');
        expect(p.assignmentFor('shop-121'), isNull);
        expect(p.assignedCountFor('u1'), 1);
      });

      test('a sold one stops the whole thing and nothing is written', () async {
        final r = repo();
        final p = await loaded(r);
        await expectLater(
          p.takeBack([p.assignmentFor('shop-121')!, p.assignmentFor('shop-123')!]),
          throwsA(isA<SalesException>()),
        );
        expect(r.calls, isEmpty);
        expect(p.assignedCountFor('u1'), 3);
      });

      test('an empty list does nothing', () async {
        final r = repo();
        final p = await loaded(r);
        expect(await p.takeBack([]), 0);
        expect(r.calls, isEmpty);
      });
    });

    group('move', () {
      test('hands QR codes to another active sales person', () async {
        final r = repo();
        final p = await loaded(r);
        final count = await p.moveAssignments([p.assignmentFor('shop-121')!], anu);

        expect(count, 1);
        expect(r.calls.single, 'reassign:shop-121->u2');
        expect(p.assignmentFor('shop-121')?.assignedTo, 'u2');
        expect(p.assignmentFor('shop-121')?.assignedToName, 'Anu');
        expect(p.assignedCountFor('u1'), 2);
        expect(p.assignedCountFor('u2'), 2);
      });

      test('a sold QR cannot be moved, and nothing is written', () async {
        final r = repo();
        final p = await loaded(r);
        await expectLater(
          p.moveAssignments([p.assignmentFor('shop-121')!, p.assignmentFor('shop-123')!], anu),
          throwsA(isA<SalesException>()),
        );
        expect(r.calls, isEmpty);
      });

      test('cannot move to someone who is turned off', () async {
        final r = repo();
        final p = await loaded(r);
        await expectLater(
          p.moveAssignments([p.assignmentFor('shop-121')!], p.userById('u3')!),
          throwsA(isA<SalesException>()),
        );
        expect(r.calls, isEmpty);
      });

      test('moving to the person who already has it writes nothing', () async {
        final r = repo();
        final p = await loaded(r);
        expect(await p.moveAssignments([p.assignmentFor('shop-121')!], ravi), 0);
        expect(r.calls, isEmpty);
      });
    });

    group('delete a sales person', () {
      test('frees the QR codes not set up and keeps the sold ones', () async {
        final r = repo();
        final p = await loaded(r);
        final result = await p.deleteSalesPerson(ravi);

        expect(result.freed, 2);
        expect(result.kept, 1);
        expect(r.calls.single, 'deleteUser:u1:shop-121,shop-122');
        expect(p.userById('u1'), isNull);
        expect(p.assignmentFor('shop-121'), isNull);
        expect(p.assignmentFor('shop-122'), isNull);
        expect(p.assignmentFor('shop-123'), isNotNull, reason: 'the record of the sale stays');
        expect(p.assignmentFor('shop-124'), isNotNull, reason: "someone else's is untouched");
      });

      test('a failure leaves the person and their QR codes as they were', () async {
        final r = repo()..manageError = Exception('network down');
        final p = await loaded(r);
        await expectLater(p.deleteSalesPerson(ravi), throwsA(isA<Exception>()));
        expect(p.userById('u1'), isNotNull);
        expect(p.assignedCountFor('u1'), 3);
      });
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

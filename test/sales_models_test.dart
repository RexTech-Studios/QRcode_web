import 'package:flutter_test/flutter_test.dart';
import 'package:reviewqr_admin/models/assignment_model.dart';
import 'package:reviewqr_admin/models/sales_user_model.dart';
import 'package:reviewqr_admin/utils/date_parse.dart';

/// Stands in for a Firestore Timestamp, which exposes toDate().
class _FakeTimestamp {
  final DateTime value;
  _FakeTimestamp(this.value);
  DateTime toDate() => value;
}

void main() {
  group('parseDate', () {
    test('reads DateTime, ISO strings and Timestamp-like values', () {
      final when = DateTime(2026, 11, 9, 8, 30);
      expect(parseDate(when), when);
      expect(parseDate(when.toIso8601String()), when);
      expect(parseDate(_FakeTimestamp(when)), when);
    });

    test('returns null for null and for junk', () {
      expect(parseDate(null), isNull);
      expect(parseDate('not a date'), isNull);
      expect(parseDate(42), isNull);
    });
  });

  group('Assignment.fromMap', () {
    test('an unsold assignment has explicit nulls and is unlocked', () {
      final a = Assignment.fromMap({
        'shopId': 's1',
        'qrId': 'q1',
        'qrCode': 'QR121',
        'assignedTo': 'u1',
        'assignedToName': 'Ravi',
        'assignedAt': DateTime(2026, 11, 1),
        'locked': false,
        'soldAt': null,
        'lastEditedAt': null,
      });
      expect(a.isSold, isFalse);
      expect(a.locked, isFalse);
      expect(a.repCanEdit, isTrue);
      expect(a.qrCode, 'QR121');
    });

    test('a sold assignment is locked and has a sale date', () {
      final a = Assignment.fromMap({
        'shopId': 's1',
        'qrCode': 'QR121',
        'assignedTo': 'u1',
        'locked': true,
        'soldAt': _FakeTimestamp(DateTime(2026, 11, 5)),
      });
      expect(a.isSold, isTrue);
      expect(a.repCanEdit, isFalse);
      expect(a.soldAt, DateTime(2026, 11, 5));
    });

    test(
      'a missing or malformed locked flag counts as locked (fail closed)',
      () {
        expect(Assignment.fromMap({'shopId': 's1'}).locked, isTrue);
        expect(
          Assignment.fromMap({'shopId': 's1', 'locked': 'no'}).locked,
          isTrue,
        );
        expect(
          Assignment.fromMap({'shopId': 's1', 'locked': false}).locked,
          isFalse,
        );
      },
    );

    test('falls back to the doc id when shopId is absent', () {
      expect(Assignment.fromMap({}, fallbackShopId: 'doc-id').shopId, 'doc-id');
    });

    test('copyWith keeps the sale date when only the lock changes', () {
      final sold = Assignment.fromMap({
        'shopId': 's1',
        'locked': true,
        'soldAt': DateTime(2026, 11, 5),
      });
      final unlocked = sold.copyWith(locked: false);
      expect(unlocked.locked, isFalse);
      expect(unlocked.soldAt, DateTime(2026, 11, 5));
    });
  });

  group('SalesUser.fromMap', () {
    test('only role "sales" counts as a sales person', () {
      expect(
        SalesUser.fromMap({'role': 'sales', 'active': true}).isSales,
        isTrue,
      );
      expect(SalesUser.fromMap({'role': 'admin'}).isSales, isFalse);
      expect(SalesUser.fromMap({}).isSales, isFalse);
    });

    test('active must be exactly true', () {
      expect(
        SalesUser.fromMap({'role': 'sales', 'active': true}).active,
        isTrue,
      );
      expect(
        SalesUser.fromMap({'role': 'sales', 'active': 'true'}).active,
        isFalse,
      );
      expect(SalesUser.fromMap({'role': 'sales'}).active, isFalse);
    });
  });
}

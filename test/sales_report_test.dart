import 'package:flutter_test/flutter_test.dart';
import 'package:reviewqr_admin/models/assignment_model.dart';
import 'package:reviewqr_admin/models/sales_user_model.dart';
import 'package:reviewqr_admin/utils/sales_report.dart';

Assignment assignment(
  String code, {
  String rep = 'u1',
  String repName = 'Ravi',
  DateTime? assignedAt,
  DateTime? soldAt,
  bool locked = false,
}) => Assignment(
  shopId: 'shop-$code',
  qrId: 'qr-$code',
  qrCode: code,
  assignedTo: rep,
  assignedToName: repName,
  assignedAt: assignedAt ?? DateTime(2026, 11, 1, 10),
  soldAt: soldAt,
  locked: locked || soldAt != null,
);

void main() {
  final users = [
    const SalesUser(uid: 'u1', name: 'Ravi', email: 'ravi@x.com'),
    const SalesUser(uid: 'u2', name: 'Anu', email: 'anu@x.com'),
  ];

  test('counts assigned, sold and pending per sales person', () {
    final report = SalesReport.build(
      assignments: [
        assignment('QR1', soldAt: DateTime(2026, 11, 5, 9)),
        assignment('QR2', soldAt: DateTime(2026, 11, 6, 9)),
        assignment('QR3'),
        assignment(
          'QR4',
          rep: 'u2',
          repName: 'Anu',
          soldAt: DateTime(2026, 11, 6, 9),
        ),
      ],
      users: users,
      shopNames: const {},
    );
    final ravi = report.summaries.firstWhere((s) => s.uid == 'u1');
    expect(ravi.soldInRange, 2);
    expect(ravi.pendingNow, 1);
    expect(ravi.assignedInRange, 3);
    expect(report.totalSold, 3);
    expect(report.summaries.first.uid, 'u1', reason: 'most sales first');
  });

  test(
    'date range is inclusive of the whole last day and excludes outside days',
    () {
      final report = SalesReport.build(
        assignments: [
          assignment('QR1', soldAt: DateTime(2026, 11, 4, 23, 59)),
          assignment('QR2', soldAt: DateTime(2026, 11, 5, 0, 0)),
          assignment('QR3', soldAt: DateTime(2026, 11, 6, 23, 59)),
          assignment('QR4', soldAt: DateTime(2026, 11, 7, 0, 0)),
        ],
        users: users,
        shopNames: const {},
        from: DateTime(2026, 11, 5),
        to: DateTime(2026, 11, 6),
      );
      expect(report.soldRows.map((r) => r.qrCode).toSet(), {'QR2', 'QR3'});
    },
  );

  test('pending is not limited by the date range', () {
    final report = SalesReport.build(
      assignments: [assignment('QR1'), assignment('QR2')],
      users: users,
      shopNames: const {},
      from: DateTime(2030, 1, 1),
      to: DateTime(2030, 1, 2),
    );
    expect(report.summaries.firstWhere((s) => s.uid == 'u1').pendingNow, 2);
    expect(report.totalSold, 0);
  });

  test('lists a sales person with nothing assigned, and one only seen on an assignment', () {
    final report = SalesReport.build(
      assignments: [assignment('QR9', rep: 'gone', repName: 'Old Rep')],
      users: users,
      shopNames: const {},
    );
    expect(
      report.summaries.map((s) => s.name),
      containsAll(['Ravi', 'Anu', 'Old Rep']),
    );
  });

  test('sold rows are newest first and use the shop name', () {
    final report = SalesReport.build(
      assignments: [
        assignment('QR1', soldAt: DateTime(2026, 11, 5)),
        assignment('QR2', soldAt: DateTime(2026, 11, 8)),
      ],
      users: users,
      shopNames: const {'shop-QR1': 'Cafe One', 'shop-QR2': 'Cafe Two'},
    );
    expect(report.soldRows.map((r) => r.qrCode), ['QR2', 'QR1']);
    expect(report.soldRows.first.shopName, 'Cafe Two');
  });

  group('CSV', () {
    final report = SalesReport.build(
      assignments: [
        assignment('QR1', soldAt: DateTime(2026, 11, 5)),
        assignment('QR2', soldAt: DateTime(2026, 11, 6)),
        assignment('QR3', soldAt: DateTime(2026, 11, 7)),
      ],
      users: users,
      shopNames: const {
        'shop-QR1': 'Cafe, "The Best"',
        'shop-QR2': '=HYPERLINK("http://evil")',
        'shop-QR3': '@cmd',
      },
    );

    test('quotes commas and quotes', () {
      expect(report.soldCsv(), contains('"Cafe, ""The Best"""'));
    });

    test('defuses spreadsheet formulas typed into a shop name', () {
      final csv = report.soldCsv();
      expect(csv, isNot(contains(',=HYPERLINK')));
      expect(csv, contains("'=HYPERLINK"));
      expect(csv, contains("'@cmd"));
    });

    test('has a header, one row per sale, and Windows line endings', () {
      final lines = report.soldCsv().trim().split('\r\n');
      expect(
        lines.first,
        'Sales person,QR number,Shop name,Assigned on,Sold on',
      );
      expect(lines, hasLength(4));
    });

    test('summary CSV lists every sales person', () {
      final csv = report.summaryCsv();
      expect(csv, contains('Ravi,3,3,0'));
      expect(csv, contains('Anu,0,0,0'));
    });
  });
}

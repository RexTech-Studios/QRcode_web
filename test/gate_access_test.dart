import 'package:flutter_test/flutter_test.dart';
import 'package:reviewqr_admin/models/sales_user_model.dart';
import 'package:reviewqr_admin/utils/app_config.dart';
import 'package:reviewqr_admin/utils/gate_access.dart';

void main() {
  const active = SalesUser(uid: 'u1', name: 'Ravi', email: 'r@x.com');
  const off = SalesUser(uid: 'u1', name: 'Ravi', email: 'r@x.com', active: false);
  const otherRole = SalesUser(uid: 'u1', name: 'Ravi', email: 'r@x.com', role: 'admin');

  test('the admin uid always gets the admin dashboard, with or without a record', () {
    expect(decideGateAccess(AppConfig.adminUid, null), GateAccess.admin);
    expect(decideGateAccess(AppConfig.adminUid, active), GateAccess.admin);
  });

  test('an active sales person gets the sales screen', () {
    expect(decideGateAccess('u1', active), GateAccess.rep);
  });

  test('a turned-off sales person is refused, with their own message', () {
    expect(decideGateAccess('u1', off), GateAccess.disabled);
  });

  test('someone with no record is refused', () {
    expect(decideGateAccess('stranger', null), GateAccess.notAuthorized);
  });

  test('a record with any role other than sales never grants access', () {
    expect(decideGateAccess('u1', otherRole), GateAccess.notAuthorized);
    expect(
      decideGateAccess('u1', const SalesUser(uid: 'u1', name: 'x', email: 'x', role: '')),
      GateAccess.notAuthorized,
    );
  });

  test('a sales record can never be used to reach the admin dashboard', () {
    for (final user in [active, off, otherRole, null]) {
      expect(
        decideGateAccess('not-the-admin', user),
        isNot(GateAccess.admin),
        reason: '$user',
      );
    }
  });
}

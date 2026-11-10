import '../models/sales_user_model.dart';
import 'app_config.dart';

/// Where a signed-in account is allowed to go.
enum GateAccess { admin, rep, notAuthorized, disabled }

/// Decides what a signed-in account may open. [user] is that account's
/// `users/{uid}` record, or null if it has none.
///
/// This only chooses which screen to show. firestore.rules is what actually
/// protects the data, so the two must agree: sales means role == 'sales' AND
/// active.
GateAccess decideGateAccess(String uid, SalesUser? user) {
  if (AppConfig.isAdmin(uid)) return GateAccess.admin;
  if (user == null || !user.isSales) return GateAccess.notAuthorized;
  if (!user.active) return GateAccess.disabled;
  return GateAccess.rep;
}

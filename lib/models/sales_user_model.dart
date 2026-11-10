import '../utils/date_parse.dart';

/// A sales person's login record, stored at `users/{uid}`. Only the admin can
/// write it. The role and active flag decide what firestore.rules lets the
/// person do.
class SalesUser {
  static const String salesRole = 'sales';

  final String uid;
  final String name;
  final String email;
  final String role;
  final bool active;
  final DateTime? createdAt;

  const SalesUser({
    required this.uid,
    required this.name,
    required this.email,
    this.role = salesRole,
    this.active = true,
    this.createdAt,
  });

  bool get isSales => role == salesRole;

  factory SalesUser.fromMap(Map<String, dynamic> map, {String? fallbackUid}) {
    return SalesUser(
      uid: (map['uid'] as String?) ?? fallbackUid ?? '',
      name: (map['name'] as String?) ?? '',
      email: (map['email'] as String?) ?? '',
      role: (map['role'] as String?) ?? '',
      active: map['active'] == true,
      createdAt: parseDate(map['createdAt']),
    );
  }

  SalesUser copyWith({bool? active, String? name}) => SalesUser(
    uid: uid,
    name: name ?? this.name,
    email: email,
    role: role,
    active: active ?? this.active,
    createdAt: createdAt,
  );
}

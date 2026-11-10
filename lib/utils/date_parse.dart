/// Reads a date from whatever a Firestore document holds: a [DateTime], an
/// ISO-8601 string, or a Firestore `Timestamp` (anything with `toDate()`).
/// Returns null for null or anything unreadable.
DateTime? parseDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  try {
    final converted = (value as dynamic).toDate();
    return converted is DateTime ? converted : null;
  } catch (_) {
    return null;
  }
}

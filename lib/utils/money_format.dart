/// Whole rupees with Indian digit grouping: 1500 -> "1,500", 150000 -> "1,50,000".
String formatRupees(int amount) {
  final negative = amount < 0;
  final digits = amount.abs().toString();
  String grouped;
  if (digits.length <= 3) {
    grouped = digits;
  } else {
    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    grouped = '${parts.join(',')},$last3';
  }
  return negative ? '-$grouped' : grouped;
}

/// Reads what the admin typed as a price: "1500", "1,500", "Rs. 1500", "1500/-".
/// Returns null for anything that isn't a whole, positive number of rupees.
int? parseRupees(String input) {
  final cleaned = input
      .toLowerCase()
      .replaceAll(RegExp(r'rs\.?|inr|₹|/-|[,\s]'), '');
  if (cleaned.isEmpty || !RegExp(r'^\d+$').hasMatch(cleaned)) return null;
  final value = int.tryParse(cleaned);
  if (value == null || value <= 0) return null;
  return value;
}

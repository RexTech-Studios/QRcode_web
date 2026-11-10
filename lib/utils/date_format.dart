const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "9 Nov 2026", in the viewer's local time.
String formatShortDate(DateTime date) {
  final d = date.toLocal();
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

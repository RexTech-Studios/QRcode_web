// Parsing for the app's route names, e.g. `/review/<shopId>`.

List<String> _segments(String route) =>
    Uri.tryParse(route)?.pathSegments ?? const [];

/// True for anything under `/review`, well-formed or not.
bool isReviewPath(String route) {
  final segments = _segments(route);
  return segments.isNotEmpty && segments.first == 'review';
}

/// The shop id from a well-formed `/review/<shopId>`, otherwise null.
String? reviewShopId(String route) {
  final segments = _segments(route);
  if (segments.length != 2 || segments.first != 'review') return null;
  return segments[1].isEmpty ? null : segments[1];
}

/// Whether the page was opened on a review link. The app uses hash URLs, so
/// the route is in the fragment (`/#/review/<id>`) and the path is just `/`.
bool isReviewLocation(Uri base) => isReviewPath(base.fragment);

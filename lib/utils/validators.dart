class Validators {
  Validators._();

  /// Accepts Google Maps review / place links, e.g.
  /// https://g.page/r/xxxx/review, https://maps.app.goo.gl/xxxx,
  /// https://www.google.com/maps/place/...
  static bool isValidGoogleMapsUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.isAbsolute) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;

    final host = uri.host.toLowerCase();
    const allowedHosts = [
      'g.page',
      'goo.gl',
      'maps.app.goo.gl',
      'maps.google.com',
      'google.com',
      'www.google.com',
    ];

    return allowedHosts.any((h) => host == h || host.endsWith('.$h'));
  }

  /// Whether the public review page may send a customer to [value]. The shop
  /// doc is remote data, so this is re-checked at launch rather than trusted
  /// from when the link was entered in the form.
  static bool isSafeReviewRedirect(String value) {
    if (!isValidGoogleMapsUrl(value)) return false;
    return Uri.parse(value.trim()).scheme == 'https';
  }

  static String? googleMapsUrlErrorText(String value) {
    if (value.trim().isEmpty) return null;
    if (!isValidGoogleMapsUrl(value)) {
      return 'Enter a valid Google Maps review link';
    }
    return null;
  }

  static bool isNotEmpty(String value) => value.trim().isNotEmpty;
}

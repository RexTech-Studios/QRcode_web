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

  static String? googleMapsUrlErrorText(String value) {
    if (value.trim().isEmpty) return null;
    if (!isValidGoogleMapsUrl(value)) {
      return 'Enter a valid Google Maps review link';
    }
    return null;
  }

  static bool isNotEmpty(String value) => value.trim().isNotEmpty;

  /// Accepts a WhatsApp contact number in international format, e.g.
  /// "+1 415 555 0132" or "919876543210". Only digits, spaces, and a
  /// leading "+" are allowed; at least 8 digits are required.
  static bool isValidWhatsappNumber(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    if (!RegExp(r'^\+?[0-9\s-]+$').hasMatch(trimmed)) return false;
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length >= 8 && digits.length <= 15;
  }

  static bool isValidEmail(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    return RegExp(r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$')
        .hasMatch(trimmed);
  }

  /// Strips everything but digits, for building a wa.me link.
  static String digitsOnly(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');
}

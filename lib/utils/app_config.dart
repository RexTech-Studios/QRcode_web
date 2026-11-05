/// App-wide constants that identify this deployment.
class AppConfig {
  AppConfig._();

  /// Firebase Auth uid of the single admin. Not a secret: firestore.rules
  /// holds the same value and is what actually enforces it.
  static const String adminUid = '7HVKqxlkuiafMK6XVL9SOmGieph2';

  /// Origin encoded into every QR code. Printed stickers depend on this and
  /// on the URL shape in [reviewUrl], so neither can change without a
  /// permanent redirect from the old URLs.
  static const String publicOrigin = 'https://qrcode-16b68.web.app';

  /// Absolute URL of the customer review page for [shopId].
  static String reviewUrl(String shopId) => '$publicOrigin/#/review/$shopId';

  static bool isAdmin(String? uid) => uid == adminUid;
}

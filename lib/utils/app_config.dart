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

  /// Switches newly generated QR codes to the short fullstarqr.com link. Leave
  /// false until DEPLOY_PHASE_1B.md says otherwise. Existing QR codes keep the
  /// URL they were created with, so flipping this never affects them.
  static const bool useNewDomain = false;

  /// Absolute URL of the customer review page for [shopId].
  static String reviewUrl(String shopId, {bool newDomain = useNewDomain}) =>
      newDomain
      ? 'https://fullstarqr.com/r/$shopId'
      : '$publicOrigin/#/review/$shopId';

  static bool isAdmin(String? uid) => uid == adminUid;

  /// Local testing only: `flutter run --dart-define=USE_EMULATOR=true` points
  /// the app at the Firebase emulators instead of the live project. It is a
  /// compile-time constant that defaults to false, and the release build
  /// (deploy.ps1) never sets it, so a deployed build can't use it.
  static const bool useEmulator = bool.fromEnvironment('USE_EMULATOR');
  static const String emulatorHost = 'localhost';
  static const int authEmulatorPort = 9099;
  static const int firestoreEmulatorPort = 8089;
}

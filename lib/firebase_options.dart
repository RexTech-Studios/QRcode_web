// Placeholder Firebase configuration.
//
// This file is NOT connected to a real Firebase project yet. The app runs
// fully offline on Hive without it. When you're ready to enable cloud sync:
//   1. Run `flutterfire configure` in the project root (requires the
//      FlutterFire CLI and an existing/created Firebase project), which
//      will overwrite this file with real values, OR
//   2. Manually replace the placeholder strings below with the values from
//      your Firebase project settings (Project settings > General > Your apps).
//
// Until then, FirebaseService fails to initialize gracefully and the app
// falls back to local-only (Hive) storage automatically.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb, TargetPlatform, defaultTargetPlatform;

class DefaultFirebaseOptions {
  DefaultFirebaseOptions._();

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBuO6Ko7UaZ1GS2_AOCY-z4AzkR5FqzljM',
    appId: '1:184985262176:web:a78824b89587effa058b05',
    messagingSenderId: '184985262176',
    projectId: 'qrcode-16b68',
    authDomain: 'qrcode-16b68.firebaseapp.com',
    storageBucket: 'qrcode-16b68.firebasestorage.app',
    measurementId: 'G-Y8PNDFKFR2',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAXoK8MW872X3jcGavkM26KIW9NuWYtOAw',
    appId: '1:184985262176:android:ce3ce9c9fc4a7ca3058b05',
    messagingSenderId: '184985262176',
    projectId: 'qrcode-16b68',
    storageBucket: 'qrcode-16b68.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyC5_JLP0R4M7DBZhMTr61O8Iz3y_J9Ji_o',
    appId: '1:184985262176:ios:ae92b55c9ced347e058b05',
    messagingSenderId: '184985262176',
    projectId: 'qrcode-16b68',
    storageBucket: 'qrcode-16b68.firebasestorage.app',
    iosBundleId: 'com.rextech.reviewqrAdmin',
  );
}

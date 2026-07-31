import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Configuración Firebase por plataforma para MundiCam.
///
/// Android mantiene los datos que ya estaban funcionando en main.dart.
/// iOS queda preparado para inicializarse con el archivo nativo:
/// ios/Runner/GoogleService-Info.plist.
///
/// Cuando tengamos el GoogleService-Info.plist definitivo de iOS, este archivo
/// se puede regenerar con FlutterFire CLI para añadir aquí las opciones iOS
/// exactas sin tocar Android:
/// flutterfire configure --project=mundicam-app --platforms=android,ios --ios-bundle-id=com.mundicam.app --out=lib/firebase_options.dart
class DefaultFirebaseOptions {
  static FirebaseOptions? get currentPlatform {
    if (kIsWeb) {
      return null;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return null;
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCAPjO2CTzQFXFGoiP-0dWPPSGQfPWqR0s',
    appId: '1:754565814741:android:acf402a9ca7cd6d9f9855c',
    messagingSenderId: '754565814741',
    projectId: 'mundicam-app',
    storageBucket: 'mundicam-app.firebasestorage.app',
  );

  /// No se inventan credenciales iOS.
  /// En iOS Firebase usará ios/Runner/GoogleService-Info.plist.
  static const FirebaseOptions? ios = null;
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mundicam/firebase_options.dart';
import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/core/cache/category_cache_service.dart';
import 'package:mundicam/core/cache/storage_cache_service.dart';
import 'package:mundicam/core/notifications/notification_service.dart';
import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/features/auth/presentation/pages/login_page.dart';
import 'package:mundicam/app/main_screen.dart';

final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

Future<void> ensureFirebaseReady() async {
  try {
    if (Firebase.apps.isNotEmpty) {
      Firebase.app();
      debugPrint('[FIREBASE] Ya estaba inicializado | END');
      return;
    }

    final firebaseOptions = DefaultFirebaseOptions.currentPlatform;

    if (firebaseOptions != null) {
      await Firebase.initializeApp(options: firebaseOptions);
    } else {
      // En iOS, cuando todavía no se ha generado firebase_options.dart con
      // FlutterFire CLI, Firebase puede inicializarse desde el archivo nativo:
      // ios/Runner/GoogleService-Info.plist.
      await Firebase.initializeApp();
    }

    debugPrint('[FIREBASE] Inicializado correctamente | END');
  } on FirebaseException catch (e) {
    if (e.code == 'duplicate-app') {
      Firebase.app();
      debugPrint('[FIREBASE] Ya estaba inicializado | END');
      return;
    }
    rethrow;
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await ensureFirebaseReady();
  } catch (e) {
    debugPrint('[FCM_BG] Inicialización Firebase omitida: $e | END');
  }

  debugPrint('[FCM_BG] title="${message.notification?.title ?? ''}" | END');
  debugPrint('[FCM_BG] body="${message.notification?.body ?? ''}" | END');
  debugPrint('[FCM_BG] data=${message.data} | END');

  try {
    await NotificationService.handleBackgroundRemoteMessage(message);
  } catch (e) {
    debugPrint('[FCM_BG] Error procesando mensaje: $e | END');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await ensureFirebaseReady();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    debugPrint('[BOOT] Handler FCM background registrado para Android/iOS | END');
  } catch (e) {
    debugPrint('[BOOT] Error conectando Firebase: $e | END');
  }

  runApp(const ProviderScope(child: MyApp()));

  // Las notificaciones se inicializan inmediatamente, pero sin bloquear la UI.
  unawaited(_initializeNotifications());

  // Remote Config y precargas no deben competir con el primer frame.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_initializeDeferredServices());
  });
}

Future<void> _initializeDeferredServices() async {
  await Future.wait(<Future<void>>[
    _initializeRemoteConfig(),
    _preloadProtectedDataIfNeeded(),
  ]);
}

Future<void> _initializeRemoteConfig() async {
  if (Firebase.apps.isEmpty) return;

  try {
    final remoteConfig = FirebaseRemoteConfig.instance;

    await remoteConfig.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: const Duration(hours: 12),
      ),
    );

    await remoteConfig.setDefaults({
      'api_base_url': 'https://www.mundicam.com',
    });

    await remoteConfig.fetchAndActivate();
    debugPrint('[REMOTE_CONFIG] Inicializado correctamente | END');
  } catch (e) {
    debugPrint('[REMOTE_CONFIG] Inicialización omitida: $e | END');
  }
}

Future<void> _initializeNotifications() async {
  if (Firebase.apps.isEmpty) {
    debugPrint('[FCM] Firebase no inicializado; notificaciones omitidas | END');
    return;
  }

  try {
    await NotificationService().initialize();
    debugPrint('[FCM] Servicio de notificaciones inicializado | END');
  } catch (e) {
    debugPrint('[FCM] Error inicializando notificaciones: $e | END');
  }
}

Future<void> _preloadProtectedDataIfNeeded() async {
  final api = ApiService();
  if (await api.hasStoredWordPressSession()) {
    await _precargarDatos();
  } else {
    debugPrint('[SESSION] Sin sesión App API; precarga protegida omitida | END');
  }
}

Future<void> _precargarDatos() async {
  try {
    final apiService = ApiService();
    final cache = CategoryCacheService();

    final catDisco = await StorageCacheService.getCachedData('categorias');

    if (catDisco != null) {
      debugPrint('[CACHE] Categorías cargadas desde disco | END');
      return;
    }

    if (cache.getCachedCategories() == null) {
      debugPrint('[CACHE] Precargando categorías App API | END');

      final categorias = await apiService.getCategorias();

      cache.cacheCategories(categorias);

      await StorageCacheService.cacheData(
        'categorias',
        categorias.map((c) {
          return {
            'id': c.id,
            'name': c.name,
            'slug': c.slug,
            'parent': c.parent,
            'count': c.count,
          };
        }).toList(),
      );

      debugPrint('[CACHE] Categorías precargadas=${categorias.length} | END');
    } else {
      debugPrint('[CACHE] Categorías ya disponibles | END');
    }
  } catch (e) {
    debugPrint('[CACHE] Error durante precarga: $e | END');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mundicam',
      theme: AppTheme.lightTheme,
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends ConsumerStatefulWidget {
  const AuthWrapper({super.key});

  @override
  ConsumerState<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends ConsumerState<AuthWrapper> {
  Future<bool>? _sessionFuture;

  @override
  void initState() {
    super.initState();
    _sessionFuture = _validateSession();
  }

  Future<bool> _validateSession() async {
    final api = ApiService();
    final hasAppSession = await api.hasStoredWordPressSession();

    if (!hasAppSession) {
      // No se elimina el token FCM al arrancar sin sesión. El mismo dispositivo
      // debe conservarlo para poder registrarlo justo después del login.
      // clearDeviceRegistration() queda reservado para un cierre de sesión real.
      debugPrint(
        '[FCM] Sin sesión App API al arrancar: token local conservado | END',
      );

      if (Firebase.apps.isNotEmpty) {
        try {
          await FirebaseAuth.instance.signOut();
        } catch (e) {
          debugPrint('[FIREBASE] No se pudo cerrar sesión opcional: $e | END');
        }
      }
      await api.clearWordPressSession();
      return false;
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authStateProvider);

    return FutureBuilder<bool>(
      future: _sessionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }

        if (snapshot.data == true) {
          return const MainScreen();
        }

        return const LoginPage();
      },
    );
  }
}
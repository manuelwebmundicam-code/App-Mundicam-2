import 'dart:async';
import 'dart:ui';

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
import 'package:mundicam/features/catalog/presentation/providers/category_provider.dart';
import 'package:mundicam/features/training/presentation/providers/academy_provider.dart';

final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

Future<void> ensureFirebaseReady() async {
  try {
    if (Firebase.apps.isNotEmpty) {
      Firebase.app();
      debugPrint('✅ Firebase ya estaba inicializado');
      return;
    }

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    debugPrint('✅ Firebase inicializado correctamente');
  } on FirebaseException catch (e) {
    if (e.code == 'duplicate-app') {
      Firebase.app();
      debugPrint('✅ Firebase ya estaba inicializado');
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
    debugPrint('⚠️ Firebase background init ignorado: $e');
  }

  debugPrint('📩 FCM background title: ${message.notification?.title}');
  debugPrint('📩 FCM background body: ${message.notification?.body}');
  debugPrint('📩 FCM background data: ${message.data}');

  try {
    await NotificationService.handleBackgroundRemoteMessage(message);
  } catch (e) {
    debugPrint('⚠️ No se pudo procesar FCM background: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('❌ Error Flutter no controlado: ${details.exceptionAsString()}');
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('❌ Error nativo/release no controlado: $error');
    debugPrintStack(stackTrace: stack);
    return true;
  };

  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.primary,
                  size: 44,
                ),
                SizedBox(height: 14),
                Text(
                  'No se pudo cargar esta pantalla.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Oswald',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Cierra la app y vuelve a intentarlo. Si continúa, contacta con MundiCam.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  };

  try {
    await ensureFirebaseReady().timeout(const Duration(seconds: 12));

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    debugPrint('✅ Handler FCM background registrado para Android/iOS');
  } catch (e) {
    debugPrint('❌ Error al conectar Firebase: $e');
  }

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

    await remoteConfig.fetchAndActivate().timeout(const Duration(seconds: 12));
    debugPrint('✅ Remote Config inicializado correctamente');
  } catch (e) {
    debugPrint('⚠️ Error al inicializar Remote Config: $e');
  }

  runApp(const ProviderScope(child: MyApp()));

  unawaited(_postRunAppBootstrap());
}

Future<void> _postRunAppBootstrap() async {
  if (Firebase.apps.isNotEmpty) {
    try {
      await NotificationService()
          .initialize()
          .timeout(const Duration(seconds: 15), onTimeout: () {
        debugPrint('⚠️ Inicialización FCM tardó demasiado. Se reintentará después.');
      });
    } catch (e) {
      debugPrint('⚠️ Error inicializando notificaciones: $e');
    }
  } else {
    debugPrint('⚠️ Firebase no está inicializado. Se omiten notificaciones FCM.');
  }

  try {
    final api = ApiService();
    if (await api.hasStoredWordPressSession()) {
      await _precargarDatos();
    } else {
      debugPrint('ℹ️ Sin sesión MundiCam App API. Se omite precarga protegida.');
    }
  } catch (e) {
    debugPrint('⚠️ Bootstrap posterior al arranque no crítico: $e');
  }
}

Future<void> _precargarDatos() async {
  try {
    final apiService = ApiService();
    final cache = CategoryCacheService();

    final catDisco = await StorageCacheService.getCachedData('categorias');

    if (catDisco != null) {
      debugPrint('⚡ Categorías desde disco');
      return;
    }

    if (cache.getCachedCategories() == null) {
      debugPrint('📦 Precargando categorías App API...');

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

      debugPrint('✅ Categorías precargadas: ${categorias.length}');
    } else {
      debugPrint('📦 Categorías ya en caché');
    }
  } catch (e) {
    debugPrint('⚠️ Error precargando: $e');
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


class _MundiCamStartupScreen extends StatelessWidget {
  const _MundiCamStartupScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppColors.primary),
                SizedBox(height: 16),
                Text(
                  'Preparando tu sesión...',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Oswald',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
    final hasStoredToken = await api.hasStoredAppSession();
    final hasAppSession = hasStoredToken
        ? await api
            .validateStoredAppSession()
            .timeout(const Duration(seconds: 15), onTimeout: () {
            debugPrint(
              '⚠️ /me tardó demasiado en arranque. Se fuerza login visible para evitar pantalla blanca en iOS Review.',
            );
            return false;
          })
        : false;

    if (!hasAppSession) {
      try {
        await NotificationService().clearDeviceRegistration();
      } catch (e) {
        debugPrint('⚠️ No se pudo limpiar el dispositivo FCM: $e');
      }

      if (Firebase.apps.isNotEmpty) {
        try {
          await FirebaseAuth.instance.signOut();
        } catch (e) {
          debugPrint('⚠️ No se pudo cerrar sesión Firebase: $e');
        }
      }
      await api.clearWordPressSession();
      return false;
    }

    try {
      ref.read(categoriesProvider.future);
      ref.read(academyProvider.future);
    } catch (_) {}

    return true;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _sessionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _MundiCamStartupScreen();
        }

        if (snapshot.hasError) {
          debugPrint('⚠️ Error restaurando sesión en arranque: ${snapshot.error}');
          return const LoginPage();
        }

        if (snapshot.data == true) {
          return const MainScreen();
        }

        return const LoginPage();
      },
    );
  }
}
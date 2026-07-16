import 'dart:io' show Platform;

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

    final firebaseOptions = DefaultFirebaseOptions.currentPlatform;

    if (firebaseOptions != null) {
      await Firebase.initializeApp(options: firebaseOptions);
    } else {
      // En iOS, cuando todavía no se ha generado firebase_options.dart con
      // FlutterFire CLI, Firebase puede inicializarse desde el archivo nativo:
      // ios/Runner/GoogleService-Info.plist.
      await Firebase.initializeApp();
    }

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
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await ensureFirebaseReady();

    if (!Platform.isIOS) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } else {
      debugPrint('ℹ️ Notificaciones FCM desactivadas en iOS de momento.');
    }
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

    await remoteConfig.fetchAndActivate();
    debugPrint('✅ Remote Config inicializado correctamente');
  } catch (e) {
    debugPrint('⚠️ Error al inicializar Remote Config: $e');
  }

  if (Firebase.apps.isNotEmpty && !Platform.isIOS) {
    try {
      await NotificationService().initialize();
    } catch (e) {
      debugPrint('⚠️ Error inicializando notificaciones: $e');
    }
  } else if (Platform.isIOS) {
    debugPrint('ℹ️ Notificaciones omitidas en iOS. Se activarán más adelante con APNs.');
  } else {
    debugPrint('⚠️ Firebase no está inicializado. Se omiten notificaciones FCM.');
  }

  final api = ApiService();
  if (await api.hasStoredWordPressSession()) {
    _precargarDatos();
  } else {
    debugPrint('ℹ️ Sin sesión MundiCam App API. Se omite precarga protegida.');
  }

  runApp(const ProviderScope(child: MyApp()));
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
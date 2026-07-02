import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

const FirebaseOptions mundicamFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyCAPjO2CTzQFXFGoiP-0dWPPSGQfPWqR0s',
  appId: '1:754565814741:android:acf402a9ca7cd6d9f9855c',
  messagingSenderId: '754565814741',
  projectId: 'mundicam-app',
  storageBucket: 'mundicam-app.firebasestorage.app',
);

Future<void> ensureFirebaseReady() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: mundicamFirebaseOptions);
    debugPrint('✅ Firebase inicializado correctamente');
  } else {
    Firebase.app();
    debugPrint('✅ Firebase ya estaba inicializado');
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

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
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

  await NotificationService().initialize();

  // ============================================================
  // PRUEBA TEMPORAL FCM POR TOPIC
  // Cuando confirmemos que llegan las notificaciones, se puede quitar
  // este bloque completo o dejar solo los logs que interesen.
  // ============================================================
  try {
    await FirebaseMessaging.instance.subscribeToTopic('mundicam_test');
    debugPrint('✅ Suscrito al topic FCM: mundicam_test');
  } catch (e) {
    debugPrint('❌ Error suscribiendo al topic mundicam_test: $e');
  }

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint('🧪 FCM RAW foreground recibido');
    debugPrint('🧪 title: ${message.notification?.title}');
    debugPrint('🧪 body: ${message.notification?.body}');
    debugPrint('🧪 data: ${message.data}');
  });

  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    debugPrint('🧪 FCM RAW opened app');
    debugPrint('🧪 title: ${message.notification?.title}');
    debugPrint('🧪 body: ${message.notification?.body}');
    debugPrint('🧪 data: ${message.data}');
  });

  try {
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();

    if (initialMessage != null) {
      debugPrint('🧪 FCM RAW initial message');
      debugPrint('🧪 title: ${initialMessage.notification?.title}');
      debugPrint('🧪 body: ${initialMessage.notification?.body}');
      debugPrint('🧪 data: ${initialMessage.data}');
    }
  } catch (e) {
    debugPrint('⚠️ Error leyendo initialMessage FCM: $e');
  }
  // ============================================================

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
      await FirebaseAuth.instance.signOut();
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
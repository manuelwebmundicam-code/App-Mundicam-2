import 'package:Mundicam/services/category_cache_service.dart';
import 'package:Mundicam/services/storage_cache_service.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:Mundicam/theme.dart';
import 'services/notification_service.dart';
import 'pages/login_page.dart';
import 'pages/main_screen.dart';
import 'providers/category_provider.dart';
import 'providers/academy_provider.dart';
import 'services/api_service.dart';

final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'AIzaSyAiagG6V0Cg4tgfuIDTe2Rz24G17N8ZHzQ',
        appId: '1:754565814741:android:74c8d2a07bdf2bd5f9855c',
        messagingSenderId: '754565814741',
        projectId: 'mundicam-app',
        storageBucket: 'mundicam-app.firebasestorage.app',
      ),
    );
    debugPrint("✅ Firebase inicializado correctamente");
  } catch (e) {
    debugPrint("❌ Error al conectar Firebase: $e");
  }

  try {
    final remoteConfig = FirebaseRemoteConfig.instance;
    await remoteConfig.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 10),
      minimumFetchInterval: const Duration(hours: 12),
    ));
    await remoteConfig.setDefaults({
      'wc_consumer_key': '',
      'wc_consumer_secret': '',
      'api_base_url': 'https://www.mundicam.com',
    });
    await remoteConfig.fetchAndActivate();
    debugPrint("✅ Remote Config inicializado correctamente");
  } catch (e) {
    debugPrint("⚠️ Error al inicializar Remote Config: $e");
  }

  // Inicializar notificaciones push
  await NotificationService().initialize();

  // Precargar categorías (disco + RAM)
  _precargarDatos();

  runApp(const ProviderScope(child: MyApp()));
}

Future<void> _precargarDatos() async {
  try {
    final apiService = ApiService();
    final cache = CategoryCacheService();

    // Intentar desde disco primero
    final catDisco = await StorageCacheService.getCachedData('categorias');
    if (catDisco != null) {
      debugPrint('⚡ Categorías desde disco');
      return;
    }

    // Descargar y guardar en RAM + Disco
    if (cache.getCachedCategories() == null) {
      debugPrint('📦 Precargando categorías...');
      final categorias = await apiService.getCategorias();
      cache.cacheCategories(categorias);
      await StorageCacheService.cacheData('categorias', categorias.map((c) {
        return {'id': c.id, 'name': c.name, 'slug': c.slug, 'parent': c.parent, 'count': c.count};
      }).toList());
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
  @override
  void initState() {
    super.initState();
    ref.read(categoriesProvider.future);
    ref.read(academyProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (user) {
        if (user != null) {
          return const MainScreen();
        }
        return const LoginPage();
      },
      loading: () => const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      ),
      error: (e, stack) => Scaffold(
        body: Center(
          child: Text("Error: $e"),
        ),
      ),
    );
  }
}
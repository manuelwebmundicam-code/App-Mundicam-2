import 'package:shared_preferences/shared_preferences.dart';

/// Estado local del calentamiento inicial de Home.
///
/// La pantalla completa de carga se usa una sola vez por instalación, hasta que
/// categorías + promociones + Academy hayan terminado su primera carga. Después
/// los providers pueden refrescar en segundo plano sin volver a bloquear Home.
class HomeWarmupState {
  HomeWarmupState._();

  static const String _completedKey = 'mundicam_home_warmup_complete_v1';

  static bool completed = false;

  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      completed = prefs.getBool(_completedKey) ?? false;
    } catch (_) {
      // Fail-open de almacenamiento: si SharedPreferences falla, se conserva el
      // comportamiento seguro de primera carga sin romper el arranque.
      completed = false;
    }
  }

  static Future<void> markComplete() async {
    completed = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_completedKey, true);
    } catch (_) {
      // El estado de esta ejecución ya está completado; un fallo de persistencia
      // no debe bloquear la aplicación.
    }
  }
}

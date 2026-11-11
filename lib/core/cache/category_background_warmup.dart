import 'package:mundicam/features/catalog/data/models/category_model.dart';

/// Precarga acotada de la taxonomía autenticada: nunca productos ni precios.
/// Las excepciones no deben impedir el acceso a Inicio.
class CategoryBackgroundWarmup {
  CategoryBackgroundWarmup._();

  static const int maxRootsPerRun = 4;
  static const Duration timeoutPerRoot = Duration(seconds: 4);
  static bool _running = false;

  static Future<void> run({
    required List<CategoryModel> roots,
    required Future<bool> Function() hasSession,
    required Future<List<CategoryModel>> Function(int) loadChildren,
  }) async {
    if (_running) return;
    _running = true;
    try {
      if (!await hasSession()) return;
      final ids = <int>{};
      for (final root in roots) {
        if (ids.length >= maxRootsPerRun) break;
        if (root.id <= 0 || root.parent != 0 || root.hasChildren == false ||
            !ids.add(root.id)) continue;
        try {
          // Secuencial: como máximo cuatro peticiones, sin ráfagas a WooCommerce.
          await loadChildren(root.id).timeout(timeoutPerRoot);
        } catch (_) {
          // La navegación normal conserva su fallback autenticado.
        }
      }
    } catch (_) {
      // Una sesión no disponible o fallo de red nunca bloquea Inicio.
    } finally {
      _running = false;
    }
  }
}

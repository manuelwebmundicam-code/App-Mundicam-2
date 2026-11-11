import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/features/catalog/data/models/category_model.dart';
import 'package:mundicam/features/catalog/presentation/providers/products_paginated_provider.dart';

/// Calienta SOLO las 10 categorías principales indicadas por MundiCam.
/// Los 15 productos/precios se obtienen de la API B2B autenticada y se
/// conservan en la MISMA caché en memoria que utiliza la pantalla normal.
/// No escribe productos comerciales en disco ni realiza consultas públicas.
class CategoryFirstPagePreloader {
  CategoryFirstPagePreloader._();

  // Permite desactivar inmediatamente la prueba sin cambiar código.
  static const bool enabled = bool.fromEnvironment(
    'MUNDICAM_CATEGORY_FIRST_PAGE_PRELOAD',
    defaultValue: true,
  );

  // Slugs de los enlaces del catálogo web facilitados por MundiCam.
  // No inventamos IDs: se obtienen de las categorías reales recibidas.
  static const List<String> _prioritySlugs = <String>[
    'video-cctv-hd',
    'video-ip',
    'accessorios-cctv',
    'networking',
    'intrusion-alarmas',
    'soluciones-autonomas',
    'incendio',
    'control-accesos',
    'drones-pro',
    'antihurto',
  ];

  // Fallback estricto para categorías principales cuyos slugs aún no viajen
  // en el JSON de alguna versión de la API. Nunca buscar por contains().
  static const List<String> _priorityNames = <String>[
    'video cctv hd',
    'video ip hd',
    'complementos',
    'networking',
    'intrusion',
    'energia',
    'incendio',
    'accesos',
    'drones pro',
    'antihurto',
  ];

  static bool _scheduled = false;
  static bool _running = false;
  // El listado que el cliente está consultando tiene preferencia absoluta.
  // Las precargas futuras esperan mientras exista una pantalla de catálogo.
  static int _foregroundCatalogViews = 0;
  static Completer<void>? _foregroundIdle;

  static void beginForegroundCatalogView() {
    _foregroundCatalogViews++;
    if (_foregroundCatalogViews == 1) {
      _foregroundIdle = Completer<void>();
    }
  }

  static void endForegroundCatalogView() {
    if (_foregroundCatalogViews == 0) return;
    _foregroundCatalogViews--;
    if (_foregroundCatalogViews == 0) {
      final wait = _foregroundIdle;
      _foregroundIdle = null;
      if (wait != null && !wait.isCompleted) wait.complete();
    }
  }

  static Future<void> _waitForForegroundIdle() async {
    while (_foregroundCatalogViews > 0) {
      final wait = _foregroundIdle;
      if (wait == null) break;
      if (kDebugMode) {
        debugPrint('MUNDICAM_CATEGORY_PRELOAD status=paused_foreground');
      }
      await wait.future;
    }
  }

  static final Map<String, DateTime> _lastAttemptByCategory =
      <String, DateTime>{};

  /// No retiene WidgetRef/BuildContext: seguro aunque se cierre Inicio.
  /// Llamar desde el estado `data` de cualquiera de las dos pantallas.
  static void schedule(List<CategoryModel> categories) {
    if (!enabled || categories.isEmpty || _scheduled || _running) return;
    final targets = _selectTargets(categories);
    if (targets.isEmpty) return;

    _scheduled = true;
    // Dar prioridad al primer frame de Inicio y a la carga de categorías.
    Future<void>.delayed(const Duration(milliseconds: 750), () {
      _scheduled = false;
      if (_running) return;
      _running = true;
      unawaited(_run(targets).whenComplete(() => _running = false));
    });
  }

  static Future<void> _run(List<CategoryModel> targets) async {
    final api = ApiService();
    try {
      if (!await api.hasStoredWordPressSession()) return;
      await api.refreshSessionContextFromBackend();
      final identity = api.catalogCacheIdentity;
      if (identity.startsWith('user:anon|')) return;

      final now = DateTime.now();
      final pending = <CategoryModel>[];
      for (final category in targets) {
        final key = '$identity|${category.id}';
        final previous = _lastAttemptByCategory[key];
        // Evita volver a lanzar 10 consultas en cada rebuild/entrada a Inicio.
        // El TTL de la caché de pantalla sigue siendo de 3 minutos.
        if (previous != null &&
            now.difference(previous) < const Duration(minutes: 3)) {
          continue;
        }
        pending.add(category);
        _lastAttemptByCategory[key] = now;
      }
      if (_lastAttemptByCategory.length > 100) {
        _lastAttemptByCategory.removeWhere((_, at) =>
            now.difference(at) > const Duration(minutes: 6));
      }
      if (pending.isEmpty) return;

      // Una sola petición comercial de fondo cada vez. VIDEO CCTV HD y
      // VIDEO IP HD tienen prioridad si el usuario todavía está en Inicio.
      // Si entra a una categoría, no se lanzan nuevas precargas hasta salir.
      // La petición que ya esté en curso no se cancela para no alterar la API.
      for (final category in pending) {
        await _waitForForegroundIdle();
        if (api.catalogCacheIdentity != identity) return;
        final watch = Stopwatch()..start();
        try {
          final count = await ProductsPaginatedNotifier.preloadFirstPage(
            apiService: api,
            categoryId: category.id,
          );
          if (kDebugMode) {
            debugPrint(
              'MUNDICAM_CATEGORY_PRELOAD category=${category.id} '
              'count=$count elapsed_ms=${watch.elapsedMilliseconds} status=ok',
            );
          }
        } catch (error) {
          // La pantalla interactiva conserva el tratamiento normal del error.
          if (kDebugMode) {
            debugPrint(
              'MUNDICAM_CATEGORY_PRELOAD category=${category.id} '
              'elapsed_ms=${watch.elapsedMilliseconds} status=error '
              'error_type=${error.runtimeType}',
            );
          }
        }
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('MUNDICAM_CATEGORY_PRELOAD status=skipped detail=$error');
      }
    }
  }

  static List<CategoryModel> _selectTargets(List<CategoryModel> categories) {
    final roots = categories.where((category) =>
        category.id > 0 && category.parent == 0).toList();
    final selected = <CategoryModel>[];
    final usedIds = <int>{};
    for (var i = 0; i < _prioritySlugs.length; i++) {
      final slug = _prioritySlugs[i];
      final name = _priorityNames[i];
      CategoryModel? found;
      for (final category in roots) {
        if (usedIds.contains(category.id)) continue;
        if (category.slug.trim().toLowerCase() == slug) {
          found = category;
          break;
        }
      }
      if (found == null) {
        for (final category in roots) {
          if (usedIds.contains(category.id)) continue;
          if (_normalize(category.name) == name) {
            found = category;
            break;
          }
        }
      }
      if (found != null && usedIds.add(found.id)) selected.add(found);
    }
    return selected;
  }

  static String _normalize(String name) => name
      .trim()
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll(RegExp(r'\s+'), ' ');
}

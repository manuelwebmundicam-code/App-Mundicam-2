import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mundicam/features/catalog/data/models/category_model.dart';
import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/core/cache/category_cache_service.dart';

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

final categoriesProvider = FutureProvider<List<CategoryModel>>((ref) async {
  final cache = CategoryCacheService();

  // Verificar caché primero
  final cached = cache.getCachedCategories();
  if (cached != null && cached.isNotEmpty) {
    if (kDebugMode) {
      debugPrint('[CATEGORIES] Caché=${cached.length} | END');
    }
    return cached;
  }

  // Si no hay caché, cargar de WooCommerce
  if (kDebugMode) {
    debugPrint('[CATEGORIES] Cargando desde App API | END');
  }
  final api = ref.watch(apiServiceProvider);
  final allCategories = await api.getCategorias();

  final filteredCategories = allCategories.where((cat) {
    final name = cat.name.toLowerCase().trim();
    final normalized = name
        .replaceAll('í', 'i')
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u');
    final isMain = cat.parent == 0;
    final isForbidden = normalized.contains('sincategoria');
    return isMain && !isForbidden;
  }).toList();

  // Guardar en caché
  if (filteredCategories.isNotEmpty) {
    cache.cacheCategories(filteredCategories);
    if (kDebugMode) {
      debugPrint('[CATEGORIES] Guardadas=${filteredCategories.length} | END');
    }
  }

  return filteredCategories;
});

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/catalog/data/models/category_model.dart';
import '../services/api_service.dart';
import '../services/category_cache_service.dart';

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

final categoriesProvider = FutureProvider<List<CategoryModel>>((ref) async {
  final cache = CategoryCacheService();

  // Verificar caché primero
  final cached = cache.getCachedCategories();
  if (cached != null && cached.isNotEmpty) {
    debugPrint('📦 Categorías desde caché (${cached.length})');
    return cached;
  }

  // Si no hay caché, cargar de WooCommerce
  debugPrint('🌐 Cargando categorías de WooCommerce...');
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
    debugPrint('✅ ${filteredCategories.length} categorías guardadas en caché');
  }

  return filteredCategories;
});

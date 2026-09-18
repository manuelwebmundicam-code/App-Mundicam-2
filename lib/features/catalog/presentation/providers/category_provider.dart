import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mundicam/features/catalog/data/models/category_model.dart';
import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/core/cache/category_cache_service.dart';
import 'package:mundicam/core/cache/storage_cache_service.dart';

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

final categoriesProvider = FutureProvider<List<CategoryModel>>((ref) async {
  final cache = CategoryCacheService();

  // Verificar caché primero. La caché puede haber sido precargada con
  // categorías y subcategorías; Inicio debe mostrar únicamente categorías raíz.
  final cached = cache.getCachedCategories();
  if (cached != null && cached.isNotEmpty) {
    final filteredCached = cached.where((cat) {
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

    debugPrint(
      '📦 Categorías principales desde caché (${filteredCached.length})',
    );
    return filteredCached;
  }

  // En un arranque nuevo, la caché en memoria está vacía aunque ya exista
  // caché persistente. La rehidratamos antes de tocar la red para que Home no
  // vuelva a enseñar estados de carga/error después del primer calentamiento.
  final diskCached = await StorageCacheService.getCachedData('categorias');
  if (diskCached is List && diskCached.isNotEmpty) {
    final diskCategories = diskCached
        .whereType<Map>()
        .map((item) => CategoryModel.fromJson(Map<String, dynamic>.from(item)))
        .where((cat) {
          final normalized = cat.name
              .toLowerCase()
              .trim()
              .replaceAll('í', 'i')
              .replaceAll('á', 'a')
              .replaceAll('é', 'e')
              .replaceAll('ó', 'o')
              .replaceAll('ú', 'u');
          return cat.parent == 0 && !normalized.contains('sincategoria');
        })
        .toList();

    if (diskCategories.isNotEmpty) {
      cache.cacheCategories(diskCategories);
      debugPrint('⚡ Categorías principales rehidratadas desde disco (${diskCategories.length})');
      return diskCategories;
    }
  }

  // Si no hay caché válida, cargar de WooCommerce.
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
    await StorageCacheService.cacheData(
      'categorias',
      filteredCategories.map((category) => category.toJson()).toList(),
    );
    debugPrint('✅ ${filteredCategories.length} categorías guardadas en caché');
  }

  return filteredCategories;
});

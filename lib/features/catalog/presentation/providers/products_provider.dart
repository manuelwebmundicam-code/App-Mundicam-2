import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/features/catalog/data/models/producto.dart';
import 'package:mundicam/features/catalog/presentation/providers/filter_provider.dart';

/// Provider para la instancia del servicio API.
///
/// La fuente actual del catálogo es la web/XStore mediante ApiService,
/// no WooCommerce REST v3 público ni Store API pública para precios.
final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});

/// Provider para obtener productos filtrados por categoría.
///
/// Se deja por compatibilidad con pantallas antiguas. Para la pantalla principal
/// de categoría se usa productsPaginatedProvider.
final productsByCategoryProvider = FutureProvider.family<List<Product>, int>((
    ref,
    categoryId,
    ) async {
  final apiService = ref.watch(apiServiceProvider);
  final filters = ref.watch(productFilterProvider);

  final brandName = filters.brand.trim();
  final brandId = filters.brandId ??
      await apiService.getMarcaIdPorNombre(
        brandName.isEmpty ? null : brandName,
      );

  final result = await apiService.getProductosCatalogoFiltrado(
    categoryId: categoryId,
    brandId: brandId,
    brandName: brandName.isEmpty ? null : brandName,
    search: filters.search.trim().isEmpty ? null : filters.search.trim(),
    page: 1,
    perPage: 60,
    orderBy: filters.orderBy.trim().isEmpty ? null : filters.orderBy.trim(),
    attributeTermIds: filters.attributeTermIds,
    attributeLabels: filters.attributeLabels,
  );

  return _dedupeProducts(result.products);
});

/// Provider para realizar búsquedas de productos.
///
/// Ahora fuerza la misma fuente HTML/XStore que usa el catálogo, para evitar
/// mezclar resultados de Store API, REST v3 o datos incompletos.
final searchProductsProvider = FutureProvider.family<List<Product>, String>((
    ref,
    query,
    ) async {
  final cleanQuery = query.trim();
  if (cleanQuery.isEmpty) return [];

  final apiService = ref.watch(apiServiceProvider);
  final result = await apiService.getProductosCatalogoFiltrado(
    search: cleanQuery,
    page: 1,
    perPage: 80,
    orderBy: 'date',
  );

  return _dedupeProducts(result.products);
});

List<Product> _dedupeProducts(List<Product> products) {
  final byId = <int, Product>{};
  final withoutId = <String, Product>{};

  for (final product in products) {
    if (product.id > 0) {
      byId[product.id] = product;
    } else {
      final key = '${product.sku}|${product.name}'.toLowerCase().trim();
      if (key.isNotEmpty) withoutId[key] = product;
    }
  }

  return [
    ...byId.values,
    ...withoutId.values,
  ];
}

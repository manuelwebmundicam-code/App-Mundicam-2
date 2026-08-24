import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mundicam/features/catalog/data/models/producto.dart';
import 'package:mundicam/core/network/api_service.dart';
// 1. IMPORTANTE: Importa el archivo donde definas el StateProvider de filtros
import 'package:mundicam/features/catalog/presentation/providers/filter_provider.dart';

/// Provider para la instancia del servicio API
final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});

/// Provider para obtener productos filtrados por categoría
final productsByCategoryProvider = FutureProvider.family<List<Product>, int>((
  ref,
  categoryId,
) async {
  final apiService = ref.watch(apiServiceProvider);

  // 2. ESCUCHA DE FILTROS:
  // Al añadir esta línea, el provider se reiniciará automáticamente
  // cada vez que el usuario cambie un filtro en el Drawer.
  final filters = ref.watch(productFilterProvider);

  // 3. PASO DE PARÁMETROS:
  // Enviamos los filtros al método getProductos que ya actualizamos en el ApiService.
  return apiService.getProductos(
    categoryId: categoryId,
    brand: filters.brand,
    orderBy: filters.orderBy,
  );
});

/// Provider para realizar búsquedas de productos
/// Se utiliza en BusquedaPage para obtener resultados en tiempo real
final searchProductsProvider = FutureProvider.family<List<Product>, String>((
  ref,
  query,
) async {
  if (query.trim().isEmpty) {
    return [];
  }

  final apiService = ref.watch(apiServiceProvider);
  return apiService.buscarProductos(query);
});

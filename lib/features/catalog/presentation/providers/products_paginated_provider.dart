import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mundicam/features/catalog/data/models/producto.dart';
import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/features/home/presentation/providers/banner_mix_provider.dart';
import 'package:mundicam/features/catalog/presentation/providers/filter_provider.dart';

/// Provider para productos con scroll infinito
final productsPaginatedProvider =
    StateNotifierProvider.family<ProductsPaginatedNotifier, List<Product>, int>(
      (ref, categoryId) {
        return ProductsPaginatedNotifier(
          apiService: ref.read(apiServiceProvider),
          categoryId: categoryId,
          ref: ref,
        );
      },
    );

class ProductsPaginatedNotifier extends StateNotifier<List<Product>> {
  final ApiService apiService;
  final int categoryId;
  final Ref ref;

  int _currentPage = 1;
  bool _isLoading = false;
  bool _hasMore = true;
  final int _perPage = 30;

  ProductsPaginatedNotifier({
    required this.apiService,
    required this.categoryId,
    required this.ref,
  }) : super([]) {
    loadFirstPage();
  }

  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;

  Future<void> loadFirstPage() async {
    _currentPage = 1;
    _hasMore = true;
    _isLoading = true;

    try {
      final filters = ref.read(productFilterProvider);
      final productos = await apiService.getProductosPaginado(
        categoryId: categoryId,
        page: _currentPage,
        perPage: _perPage,
        brand: filters.brand,
        orderBy: filters.orderBy,
      );

      state = productos;
      _hasMore = productos.length >= _perPage;
    } catch (e) {
      // Mantener estado actual en caso de error
    } finally {
      _isLoading = false;
    }
  }

  Future<void> loadNextPage() async {
    if (_isLoading || !_hasMore) return;

    _isLoading = true;
    _currentPage++;

    try {
      final filters = ref.read(productFilterProvider);
      final productos = await apiService.getProductosPaginado(
        categoryId: categoryId,
        page: _currentPage,
        perPage: _perPage,
        brand: filters.brand,
        orderBy: filters.orderBy,
      );

      if (productos.isEmpty) {
        _hasMore = false;
      } else {
        state = [...state, ...productos];
        _hasMore = productos.length >= _perPage;
      }
    } catch (e) {
      _currentPage--; // Revertir la página en caso de error
    } finally {
      _isLoading = false;
    }
  }

  /// Reiniciar cuando cambian los filtros
  void refresh() {
    loadFirstPage();
  }
}

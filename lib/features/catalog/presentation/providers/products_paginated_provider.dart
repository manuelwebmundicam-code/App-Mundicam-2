import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mundicam/core/cache/product_cache_service.dart';
import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/features/catalog/data/models/producto.dart';
import 'package:mundicam/features/catalog/presentation/providers/filter_provider.dart';
import 'package:mundicam/features/home/presentation/providers/banner_mix_provider.dart';

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

  static const Duration _cacheTtl = Duration(minutes: 3);

  int _currentPage = 1;
  int _totalPages = 1;
  int _totalItems = 0;
  int _requestToken = 0;

  bool _isLoading = false;
  bool _hasMore = true;
  bool _hasLoadedFirstPage = false;

  Object? _lastError;

  final int _perPage = 30;

  ProductsPaginatedNotifier({
    required this.apiService,
    required this.categoryId,
    required this.ref,
  }) : super([]) {
    Future<void>.microtask(loadFirstPage);
  }

  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;
  bool get hasLoadedFirstPage => _hasLoadedFirstPage;

  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  int get totalItems => _totalItems;

  Object? get lastError => _lastError;

  static void clearGlobalCache() {
    ProductCacheService().clearCatalogMemory();
  }

  void clearCacheForCurrentCategory() {
    ProductCacheService().clearMemoryPrefix('catalog_page|cat:$categoryId|');
  }

  Future<void> loadFirstPage({
    bool forceRefresh = false,
  }) async {
    if (_isLoading && !forceRefresh) return;

    final token = ++_requestToken;

    _currentPage = 1;
    _hasMore = true;
    _isLoading = true;
    _lastError = null;

    try {
      final result = await _loadPage(
        page: _currentPage,
        forceRefresh: forceRefresh,
      );

      if (token != _requestToken) return;

      _hasLoadedFirstPage = true;
      state = result.products;
      _totalPages = result.totalPages;
      _totalItems = result.totalItems;
      _hasMore = result.hasNextPage;
    } catch (e) {
      if (token != _requestToken) return;

      _hasLoadedFirstPage = true;
      _lastError = e;
      _hasMore = false;

      if (kDebugMode) {
        debugPrint('❌ Error cargando primera página catálogo: $e');
      }
    } finally {
      if (token == _requestToken) {
        _isLoading = false;
      }
    }
  }

  Future<void> loadNextPage({
    bool forceRefresh = false,
  }) async {
    if (_isLoading || !_hasMore) return;

    final token = ++_requestToken;

    _isLoading = true;
    _lastError = null;

    final nextPage = _currentPage + 1;

    try {
      final result = await _loadPage(
        page: nextPage,
        forceRefresh: forceRefresh,
      );

      if (token != _requestToken) return;

      _currentPage = result.currentPage;
      _totalPages = result.totalPages;
      _totalItems = result.totalItems;

      if (result.products.isEmpty) {
        _hasMore = false;
      } else {
        state = [...state, ...result.products];
        _hasMore = result.hasNextPage;
      }
    } catch (e) {
      if (token != _requestToken) return;

      _hasLoadedFirstPage = true;
      _lastError = e;

      if (kDebugMode) {
        debugPrint('❌ Error cargando más productos catálogo: $e');
      }
    } finally {
      if (token == _requestToken) {
        _isLoading = false;
      }
    }
  }

  void refresh({
    bool forceRefresh = false,
  }) {
    loadFirstPage(forceRefresh: forceRefresh);
  }

  Future<CatalogProductsResult> _loadPage({
    required int page,
    required bool forceRefresh,
  }) async {
    final filters = ref.read(productFilterProvider);

    final brandName = filters.brand.trim();
    final search = filters.search.trim();
    final orderBy = filters.orderBy.trim();

    final effectiveBrandId = filters.brandId ??
        await apiService
            .getMarcaIdPorNombre(
          brandName.isEmpty ? null : brandName,
        )
            .timeout(
          const Duration(seconds: 2),
          onTimeout: () => null,
        );

    final cacheKey = _buildCacheKey(
      categoryId: categoryId,
      brandId: effectiveBrandId,
      brandName: brandName,
      search: search,
      orderBy: orderBy,
      attributeTermIds: filters.attributeTermIds,
      page: page,
      perPage: _perPage,
    );

    return ProductCacheService().getOrLoadMemory<CatalogProductsResult>(
      cacheKey,
      ttl: _cacheTtl,
      forceRefresh: forceRefresh,
      loader: () async {
        final result = await apiService.getProductosCatalogoFiltrado(
          categoryId: categoryId,
          brandId: effectiveBrandId,
          brandName: brandName.isEmpty ? null : brandName,
          search: search.isEmpty ? null : search,
          page: page,
          perPage: _perPage,
          orderBy: orderBy,
          attributeTermIds: filters.attributeTermIds,
          attributeLabels: filters.attributeLabels,
        );

        if (kDebugMode) {
          debugPrint(
            '🌐 Catálogo cargado: $cacheKey · total=${result.totalItems}',
          );
        }

        return result;
      },
    );
  }

  static String _buildCacheKey({
    required int categoryId,
    required int? brandId,
    required String brandName,
    required String search,
    required String orderBy,
    required Map<String, int> attributeTermIds,
    required int page,
    required int perPage,
  }) {
    return [
      'catalog_page|cat:$categoryId',
      'brandId:${brandId ?? 0}',
      'brand:${brandName.toLowerCase().trim()}',
      'search:${search.toLowerCase().trim()}',
      'order:$orderBy',
      'attrs:${_attributesCachePart(attributeTermIds)}',
      'page:$page',
      'perPage:$perPage',
    ].join('|');
  }

  static String _attributesCachePart(Map<String, int> attributeTermIds) {
    if (attributeTermIds.isEmpty) return '';

    final keys = attributeTermIds.keys.toList()..sort();
    return keys.map((key) => '$key:${attributeTermIds[key]}').join(',');
  }
}

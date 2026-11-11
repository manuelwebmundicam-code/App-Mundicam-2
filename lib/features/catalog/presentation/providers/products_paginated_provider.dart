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

  // Primera página de 10 productos para acelerar el arranque.
  // Reversible: --dart-define=MUNDICAM_CATEGORY_PAGE_SIZE=15
  static const int _configuredPageSize = int.fromEnvironment(
    'MUNDICAM_CATEGORY_PAGE_SIZE',
    defaultValue: 10,
  );
  final int _perPage = _configuredPageSize >= 5 && _configuredPageSize <= 30
      ? _configuredPageSize
      : 15;

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

  /// QA: precarga la primera pagina usando la API y la cache originales.
  /// Los precios siempre los calcula el PHP MundiCam para el usuario autenticado.
  static Future<int> preloadFirstPage({
    required ApiService apiService,
    required int categoryId,
  }) async {
    if (categoryId <= 0 || !await apiService.hasStoredAppSession()) {
      return 0;
    }

    final identity = apiService.catalogCacheIdentity;
    if (identity.startsWith('user:anon|')) return 0;

    final pageSize = _configuredPageSize >= 5 && _configuredPageSize <= 30
        ? _configuredPageSize
        : 15;
    final cacheKey = _buildCacheKey(
      userKey: identity,
      categoryId: categoryId,
      brandId: null,
      brandName: '',
      search: '',
      orderBy: '',
      attributeTermIds: const <String, int>{},
      page: 1,
      perPage: pageSize,
    );

    final result = await ProductCacheService()
        .getOrLoadMemory<CatalogProductsResult>(
      cacheKey,
      ttl: _cacheTtl,
      loader: () => apiService.getProductosCatalogoFiltrado(
        categoryId: categoryId,
        page: 1,
        perPage: pageSize,
      ),
    );
    return result.products.length;
  }
  static void clearGlobalCache() {
    ProductCacheService().clearCatalogMemory();
  }

  void clearCacheForCurrentCategory() {
    // La clave incluye la identidad comercial ANTES de cat:. El prefijo
    // anterior no coincidía nunca y no invalidaba el listado solicitado.
    final cache = ProductCacheService();
    final identity = apiService.catalogCacheIdentity;
    cache.clearMemoryPrefix('catalog_page|$identity|cat:$categoryId|');
    // La App API tiene otra capa de caché (30 min). Invalidarla solo al
    // pulsar Actualizar evita devolver stock/precios antiguos en un refresh.
    cache.clearMemoryPrefix('api_products|$identity|cat:$categoryId|');
  }

  void showReloadingState() {
    _requestToken++;
    _currentPage = 1;
    _totalPages = 1;
    _totalItems = 0;
    _hasMore = true;
    _hasLoadedFirstPage = false;
    _isLoading = true;
    _lastError = null;
    state = const <Product>[];
  }

  Future<void> loadFirstPage({
    bool forceRefresh = false,
    bool restartPending = false,
  }) async {
    // En cambios de filtro/categoría, invalidar SOLO la petición antigua,
    // no la caché comercial reciente con idéntico usuario/orden/filtros.
    // refresh explícito mantiene forceRefresh=true.
    if (_isLoading && !forceRefresh && !restartPending) return;

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
        final existingIds = state.map((product) => product.id).toSet();
        state = [
          ...state,
          ...result.products.where((product) => existingIds.add(product.id)),
        ];
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
      userKey: apiService.catalogCacheIdentity,
      categoryId: categoryId,
      brandId: effectiveBrandId,
      brandName: brandName,
      search: search,
      orderBy: orderBy,
      attributeTermIds: filters.attributeTermIds,
      page: page,
      perPage: _perPage,
    );

    final watch = Stopwatch()..start();
    try {
      return await ProductCacheService().getOrLoadMemory<CatalogProductsResult>(
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
    } finally {
      watch.stop();
      if (kDebugMode) {
        debugPrint(
          'MUNDICAM_CATEGORY_TIMING category=$categoryId '
          'page=$page size=$_perPage elapsed_ms=' +
          watch.elapsedMilliseconds.toString() +
          ' force_refresh=$forceRefresh',
        );
      }
    }
  }

  static String _buildCacheKey({
    required String userKey,
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
      'catalog_page|$userKey',
      'cat:$categoryId',
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

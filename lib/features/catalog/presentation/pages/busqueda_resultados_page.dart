// busqueda_resultados_page.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:mundicam/core/firebase/firebase_service.dart';
import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/core/analytics/mundicam_analytics_service.dart';
import 'package:mundicam/features/cart/presentation/providers/cart_provider.dart';
import 'package:mundicam/features/catalog/data/models/producto.dart';
import 'package:mundicam/features/catalog/presentation/pages/producto_detalles_page.dart';
import 'package:mundicam/features/catalog/presentation/pages/productos_por_categoria.dart';
import 'package:mundicam/features/quotes/data/models/local_quote_model.dart';
import 'package:mundicam/features/quotes/presentation/providers/local_quote_provider.dart';
import 'package:mundicam/features/quotes/presentation/widgets/quote_selection_dialog.dart';
import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/shared/widgets/professional_page_app_bar.dart';


final _searchCanViewStockDetailsProvider = FutureProvider<bool>((ref) async {
  try {
    return ApiService().currentSessionCanViewStockDetails();
  } catch (e) {
    if (kDebugMode) {
      debugPrint('Error resolviendo permiso de stock en búsqueda: $e');
    }
    return false;
  }
});

class BusquedaResultadosPage extends ConsumerStatefulWidget {
  final String query;
  final VoidCallback? onGoCart;
  final VoidCallback? onGoQuotes;

  const BusquedaResultadosPage({
    super.key,
    required this.query,
    this.onGoCart,
    this.onGoQuotes,
  });

  @override
  ConsumerState<BusquedaResultadosPage> createState() => _BusquedaResultadosPageState();
}

class _BusquedaResultadosPageState extends ConsumerState<BusquedaResultadosPage> {
  final ApiService _api = ApiService();
  late String _cleanedQuery;
  bool _loading = true;
  Object? _error;
  List<Product> _productos = const <Product>[];
  List<_SearchFacet> _availableCategoryFacets = const <_SearchFacet>[];
  List<_SearchFacet> _availableBrandFacets = const <_SearchFacet>[];
  int _totalItems = 0;
  int _selectedCategoryId = 0;
  String _selectedCategoryName = '';
  String _selectedBrand = '';
  String _orderBy = '';
  int _requestToken = 0;
  bool _searchEventTracked = false;

  final ScrollController _scrollController = ScrollController();
  bool _loadingMore = false;
  bool _hasMore = false;
  int _currentPage = 1;

  static const int _firstPageSize = 10;
  static const int _nextPageSize = 10;

  bool get _hasActiveFilters =>
      _selectedCategoryId > 0 || _selectedBrand.trim().isNotEmpty || _orderBy.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _cleanedQuery = _SearchEngine.cleanQuery(widget.query);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      MundicamAnalyticsService.instance
          .trackScreenViewForRoute(context, 'search_results');
    });
    _loadResults();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_loading || _loadingMore || !_hasMore) return;

    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 700) {
      _loadMoreResults();
    }
  }

  Future<void> _loadResults({bool forceRefresh = false}) async {
    // forceRefresh se mantiene para llamadas explícitas de UI; la API ya evita caché de filtros por query.
    if (forceRefresh) {
      // La recarga manual invalida el ciclo visual aunque el endpoint use la misma query.
    }
    final token = ++_requestToken;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _hasMore = false;
      _currentPage = 1;
      _error = null;
      _productos = const <Product>[];
    });

    try {
      var result = await _api.getProductosCatalogoFiltrado(
        categoryId: _selectedCategoryId > 0 ? _selectedCategoryId : null,
        brandName: _selectedBrand.trim().isEmpty ? null : _selectedBrand.trim(),
        search: _cleanedQuery,
        page: 1,
        perPage: _firstPageSize,
        orderBy: _orderBy.trim().isEmpty ? null : _orderBy.trim(),
      );

      // Evita pantallas vacías con endpoints antiguos cuando la búsqueda lleva
      // varias palabras: si "dahua 6mp" no devuelve nada, hacemos un único
      // fallback ligero con el término más fuerte, sin volver al context-search.
      if (result.products.isEmpty && !_hasActiveFilters) {
        final fallbackQuery = _fallbackSearchQuery(_cleanedQuery);
        if (fallbackQuery != null) {
          result = await _api.getProductosCatalogoFiltrado(
            search: fallbackQuery,
            page: 1,
            perPage: _firstPageSize,
            orderBy: _orderBy.trim().isEmpty ? null : _orderBy.trim(),
          );
        }
      }

      if (!mounted || token != _requestToken) return;
      final sorted = _SearchEngine.sortByRelevance(result.products, _cleanedQuery);
      final localCategoryFacets = _categoryFacets(sorted, onlyMainLike: true);
      final brandFacets = _brandFacets(_SearchEngine.productsForFilterFacets(sorted, _cleanedQuery));

      // Mostramos los primeros 10 resultados en cuanto llegan. El resto entra
      // después por paginación/caché del ApiService.
      setState(() {
        _productos = sorted;
        _availableCategoryFacets = localCategoryFacets;
        _availableBrandFacets = brandFacets;
        _totalItems = result.totalItems > 0 ? result.totalItems : sorted.length;
        _currentPage = result.currentPage <= 0 ? 1 : result.currentPage;
        _hasMore = result.hasNextPage;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });

      if (!_searchEventTracked) {
        _searchEventTracked = true;
        unawaited(
          MundicamAnalyticsService.instance.track(
            eventName: 'search',
            metadata: <String, dynamic>{
              'query': _cleanedQuery,
              'results': _totalItems > 0 ? _totalItems : sorted.length,
            },
            dedupeKey: 'search:$_cleanedQuery',
            dedupeWindow: const Duration(seconds: 2),
          ),
        );
      }

      _webLikeCategoryFacets(sorted).then((categoryFacets) {
        if (!mounted || token != _requestToken || categoryFacets.isEmpty) return;
        setState(() {
          _availableCategoryFacets = categoryFacets;
        });
      });

      if (_hasMore) {
        _loadMoreResults(automatic: true, requestToken: token);
      }
    } catch (e) {
      if (!mounted || token != _requestToken) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _hasMore = false;
        _error = e;
        _productos = const <Product>[];
        _availableCategoryFacets = const <_SearchFacet>[];
        _availableBrandFacets = const <_SearchFacet>[];
        _totalItems = 0;
      });
    }
  }

  Future<void> _loadMoreResults({
    bool automatic = false,
    int? requestToken,
  }) async {
    if (_loading || _loadingMore || !_hasMore) return;

    final token = requestToken ?? _requestToken;
    final nextPage = _currentPage + 1;

    setState(() {
      _loadingMore = true;
      _error = null;
    });

    try {
      final result = await _api.getProductosCatalogoFiltrado(
        categoryId: _selectedCategoryId > 0 ? _selectedCategoryId : null,
        brandName: _selectedBrand.trim().isEmpty ? null : _selectedBrand.trim(),
        search: _cleanedQuery,
        page: nextPage,
        perPage: _nextPageSize,
        orderBy: _orderBy.trim().isEmpty ? null : _orderBy.trim(),
      );

      if (!mounted || token != _requestToken) return;

      final merged = _dedupeProducts(<Product>[
        ..._productos,
        ...result.products,
      ]);
      final sorted = _SearchEngine.sortByRelevance(merged, _cleanedQuery);
      final localCategoryFacets = _categoryFacets(sorted, onlyMainLike: true);
      final brandFacets = _brandFacets(_SearchEngine.productsForFilterFacets(sorted, _cleanedQuery));

      setState(() {
        _productos = sorted;
        _availableCategoryFacets = localCategoryFacets.isNotEmpty
            ? localCategoryFacets
            : _availableCategoryFacets;
        _availableBrandFacets = brandFacets.isNotEmpty
            ? brandFacets
            : _availableBrandFacets;
        _totalItems = result.totalItems > 0 ? result.totalItems : _totalItems;
        _currentPage = result.currentPage <= _currentPage
            ? nextPage
            : result.currentPage;
        _hasMore = result.hasNextPage && result.products.isNotEmpty;
        _loadingMore = false;
      });

      // Carga una segunda página automática solo cuando el usuario acaba de entrar.
      // Así la pantalla enseña 10 rápido y acto seguido deja más resultados listos.
      if (automatic && _hasMore && mounted && token == _requestToken) {
        Future<void>.delayed(const Duration(milliseconds: 120), () {
          if (!mounted || token != _requestToken) return;
          _loadMoreResults(requestToken: token);
        });
      }
    } catch (e) {
      if (!mounted || token != _requestToken) return;
      setState(() {
        _loadingMore = false;
        if (!automatic) _error = e;
      });
      if (kDebugMode) {
        debugPrint('⚠️ Error cargando más resultados de búsqueda: $e');
      }
    }
  }

  List<Product> _dedupeProducts(Iterable<Product> products) {
    final seen = <int>{};
    final output = <Product>[];
    for (final product in products) {
      if (product.id <= 0 || seen.contains(product.id)) continue;
      seen.add(product.id);
      output.add(product);
    }
    return output;
  }


  void _openFilters() {
    final categories = _availableCategoryFacets.isNotEmpty ? _availableCategoryFacets : _categoryFacets(_productos);
    final brands = _availableBrandFacets.isNotEmpty ? _availableBrandFacets : _brandFacets(_SearchEngine.productsForFilterFacets(_productos, _cleanedQuery));

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _SearchFiltersSheet(
          query: _cleanedQuery,
          selectedCategoryId: _selectedCategoryId,
          selectedBrand: _selectedBrand,
          orderBy: _orderBy,
          categories: categories,
          brands: brands,
          onApply: ({required categoryId, required categoryName, required brand, required orderBy}) {
            Navigator.of(context).pop();

            final cleanCategoryName = categoryName.trim();

            // Si el usuario elige una categoría desde los filtros de búsqueda,
            // no hacemos un filtrado local/genérico. Entramos en la pantalla real
            // de esa categoría para reutilizar sus productos y sus filtros propios
            // tal como vienen de la web/PHP. Así VIDEO CCTV HD, INTRUSIÓN,
            // ACCESOS, etc. muestran sus filtros reales y no facetas mezcladas
            // del buscador global.
            if (categoryId > 0 && cleanCategoryName.isNotEmpty) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ProductosPorCategoriaScreen(
                    categoryId: categoryId,
                    categoryName: cleanCategoryName,
                    initialSearch: _cleanedQuery,
                    onGoCart: widget.onGoCart,
                    onGoQuotes: widget.onGoQuotes,
                  ),
                ),
              );
              return;
            }

            setState(() {
              _selectedCategoryId = 0;
              _selectedCategoryName = '';
              _selectedBrand = brand;
              _orderBy = orderBy;
            });
            _loadResults(forceRefresh: true);
          },
          onReset: () {
            Navigator.of(context).pop();
            _resetFilters();
          },
        );
      },
    );
  }

  void _resetFilters() {
    setState(() {
      _selectedCategoryId = 0;
      _selectedCategoryName = '';
      _selectedBrand = '';
      _orderBy = '';
    });
    _loadResults(forceRefresh: true);
  }

  String? _fallbackSearchQuery(String query) {
    final clean = query.trim().toLowerCase();
    if (clean.length < 4 || !clean.contains(' ')) return null;

    final tokens = clean
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n')
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.length >= 3 && !_isWeakFallbackToken(token))
        .toList();

    if (tokens.isEmpty) return null;
    final preferred = tokens.firstWhere(
      (token) => RegExp(r'[a-z]').hasMatch(token) && token.length >= 4,
      orElse: () => tokens.first,
    );
    return preferred == clean ? null : preferred;
  }

  bool _isWeakFallbackToken(String token) {
    const weak = <String>{
      'camara',
      'camaras',
      'camera',
      'cameras',
      'video',
      'seguridad',
      'para',
      'con',
      'del',
      'los',
      'las',
      'una',
      'uno',
    };
    return weak.contains(token);
  }

  Future<List<_SearchFacet>> _webLikeCategoryFacets(List<Product> products) async {
    // Para que el filtro de búsqueda global se comporte como la web, aquí no
    // sacamos subfamilias aleatorias desde los 50/80 productos cargados.
    // Primero intentamos usar las categorías principales reales del catálogo
    // con el contador que devuelve WordPress/WooCommerce.
    try {
      final allCategories = await _api.getCategorias(hideEmpty: true, parentOnly: true);
      final mainCategories = allCategories
          .where((cat) => cat.id > 0 && cat.parent == 0 && cat.count > 0 && !_SearchEngine.isForbiddenFacetName(cat.name))
          .map((cat) => _SearchFacet(id: cat.id, name: cat.name, count: cat.count))
          .toList();

      if (mainCategories.isNotEmpty) {
        mainCategories.sort((a, b) {
          final orderA = _SearchEngine.mainCategoryOrder(a.name);
          final orderB = _SearchEngine.mainCategoryOrder(b.name);
          if (orderA != orderB) return orderA.compareTo(orderB);
          return a.name.compareTo(b.name);
        });
        return mainCategories.take(12).toList();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ No se pudieron cargar categorías principales para filtros: $e');
      }
    }

    return _categoryFacets(products, onlyMainLike: true);
  }

  List<_SearchFacet> _categoryFacets(List<Product> products, {bool onlyMainLike = false}) {
    final byId = <int, _MutableFacet>{};
    for (final product in products) {
      for (var i = 0; i < product.categoryIds.length; i++) {
        final id = product.categoryIds[i];
        if (id <= 0) continue;
        final name = i < product.categoryNames.length ? product.categoryNames[i].trim() : '';
        if (name.isEmpty) continue;
        if (_SearchEngine.isForbiddenFacetName(name)) continue;
        if (onlyMainLike && !_SearchEngine.looksLikeMainCategory(name)) continue;
        final compact = _SearchEngine._normalize(name);
        if (compact.contains('sin categoria') || compact.contains('uncategorized')) continue;
        byId.putIfAbsent(id, () => _MutableFacet(id: id, name: name)).count++;
      }
    }
    final facets = byId.values
        .map((item) => _SearchFacet(id: item.id, name: item.name, count: item.count))
        .toList()
      ..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        if (byCount != 0) return byCount;
        return a.name.compareTo(b.name);
      });
    return facets.take(12).toList();
  }

  List<_SearchFacet> _brandFacets(List<Product> products) {
    final byName = <String, _MutableFacet>{};
    for (final product in products) {
      final brand = product.brandName?.trim() ?? '';
      if (brand.isEmpty || _SearchEngine.isForbiddenFacetName(brand)) continue;
      final key = _SearchEngine._normalize(brand);
      if (key.isEmpty) continue;
      byName.putIfAbsent(key, () => _MutableFacet(id: 0, name: brand)).count++;
    }
    final facets = byName.values
        .map((item) => _SearchFacet(id: item.id, name: item.name, count: item.count))
        .toList()
      ..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        if (byCount != 0) return byCount;
        return a.name.compareTo(b.name);
      });
    return facets.take(12).toList();
  }

  @override
  Widget build(BuildContext context) {
    final canViewStockDetails = ref.watch(_searchCanViewStockDetailsProvider).maybeWhen(
      data: (value) => value,
      orElse: () => false,
    );
    final FirebaseService firebase = FirebaseService();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: ProfessionalPageAppBar(
        title: _cleanedQuery.isEmpty ? 'RESULTADOS' : 'RESULTADOS: $_cleanedQuery',
        subtitle: '',
        icon: Icons.search_rounded,
        onBack: () => Navigator.of(context).pop(),
      ),
      body: _loading && _productos.isEmpty
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 16),
            Text('Buscando productos...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      )
          : _error != null
          ? _buildErrorState(context, _error!)
          : _productos.isEmpty
          ? _buildEmptyState(context, _cleanedQuery)
          : Column(
        children: [
          _SearchResultsHeader(
            query: _cleanedQuery,
            totalItems: _totalItems > 0 ? _totalItems : _productos.length,
            loadedItems: _productos.length,
            selectedCategoryName: _selectedCategoryName,
            selectedBrand: _selectedBrand,
            orderBy: _orderBy,
            hasActiveFilters: _hasActiveFilters,
            onOpenFilters: _openFilters,
            onReset: _resetFilters,
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () => _loadResults(forceRefresh: true),
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                itemCount: _productos.length + (_loadingMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= _productos.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    );
                  }
                  return ProductTileBusqueda(
                    p: _productos[index],
                    firebase: firebase,
                    onGoCart: widget.onGoCart,
                    onGoQuotes: widget.onGoQuotes,
                    canViewStockDetails: canViewStockDetails,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: Color(0xFFF8EAEA),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline, size: 48, color: AppColors.primary),
            ),
            const SizedBox(height: 18),
            const Text(
              'Error al buscar productos',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontFamily: 'Oswald',
                fontWeight: FontWeight.w900,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text('$error', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Volver'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, String cleanedQuery) {
    final suggestions = _SearchEngine.suggestionsFor(cleanedQuery);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: const BoxDecoration(color: Color(0xFFF8EAEA), shape: BoxShape.circle),
              child: const Icon(Icons.search_off_rounded, size: 58, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            Text(
              'No encontramos "$cleanedQuery"',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontFamily: 'Oswald',
                fontWeight: FontWeight.w900,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Prueba con una búsqueda más general, una marca, una referencia o una tecnología concreta.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[600], height: 1.5),
            ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: suggestions.map((suggestion) {
                  return ActionChip(
                    label: Text(suggestion, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BusquedaResultadosPage(
                            query: suggestion,
                            onGoCart: widget.onGoCart,
                            onGoQuotes: widget.onGoQuotes,
                          ),
                        ),
                      );
                    },
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Volver a buscar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResultsHeader extends StatelessWidget {
  final String query;
  final int totalItems;
  final int loadedItems;
  final String selectedCategoryName;
  final String selectedBrand;
  final String orderBy;
  final bool hasActiveFilters;
  final VoidCallback onOpenFilters;
  final VoidCallback onReset;

  const _SearchResultsHeader({
    required this.query,
    required this.totalItems,
    required this.loadedItems,
    required this.selectedCategoryName,
    required this.selectedBrand,
    required this.orderBy,
    required this.hasActiveFilters,
    required this.onOpenFilters,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7E7E7)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _resultText(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onOpenFilters,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: hasActiveFilters ? AppColors.primary : const Color(0xFFF0F2F5),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: hasActiveFilters ? AppColors.primary : const Color(0xFFD9DEE7)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tune_rounded, size: 17, color: hasActiveFilters ? Colors.white : AppColors.textPrimary),
                      const SizedBox(width: 6),
                      Text('Filtros', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: hasActiveFilters ? Colors.white : AppColors.textPrimary)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (hasActiveFilters) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      if (selectedCategoryName.trim().isNotEmpty) _chip('Categoría', selectedCategoryName.trim()),
                      if (selectedBrand.trim().isNotEmpty) _chip('Fabricante', selectedBrand.trim()),
                      if (orderBy.trim().isNotEmpty) _chip('Orden', _orderLabel(orderBy)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: onReset,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFD9DEE7)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.close_rounded, size: 14, color: AppColors.primary),
                        SizedBox(width: 4),
                        Text('Limpiar', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: AppColors.primary)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }


  String _resultText() {
    // Igual que en la pantalla de categoría: no mostramos contador numérico
    // porque el total puede variar mientras se completa la paginación/caché.
    if (loadedItems > 0 || totalItems > 0) {
      return 'Productos encontrados';
    }

    return 'Sin resultados';
  }

  Widget _chip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7F7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFF0D4D4)),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF8A1D1D)),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }

  String _orderLabel(String value) {
    switch (value) {
      case 'price_asc':
        return 'Precio bajo primero';
      case 'price_desc':
        return 'Precio alto primero';
      case 'date':
        return 'Más recientes';
      default:
        return value;
    }
  }
}

class _SearchFiltersSheet extends StatefulWidget {
  final String query;
  final int selectedCategoryId;
  final String selectedBrand;
  final String orderBy;
  final List<_SearchFacet> categories;
  final List<_SearchFacet> brands;
  final void Function({
  required int categoryId,
  required String categoryName,
  required String brand,
  required String orderBy,
  }) onApply;
  final VoidCallback onReset;

  const _SearchFiltersSheet({
    required this.query,
    required this.selectedCategoryId,
    required this.selectedBrand,
    required this.orderBy,
    required this.categories,
    required this.brands,
    required this.onApply,
    required this.onReset,
  });

  @override
  State<_SearchFiltersSheet> createState() => _SearchFiltersSheetState();
}

class _SearchFiltersSheetState extends State<_SearchFiltersSheet> {
  late int _categoryId;
  late String _categoryName;
  late String _brand;
  late String _orderBy;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.selectedCategoryId;
    _categoryName = '';
    for (final item in widget.categories) {
      if (item.id == _categoryId) {
        _categoryName = item.name;
        break;
      }
    }
    _brand = widget.selectedBrand;
    _orderBy = widget.orderBy;
  }

  List<_SearchFacet> get _visibleBrands {
    final normalizedSelected = _normalizeBrand(_brand);
    final byKey = <String, _SearchFacet>{};

    for (final brand in widget.brands) {
      final cleanName = brand.name.trim();
      if (cleanName.isEmpty) continue;

      final key = _normalizeBrand(cleanName);
      if (key.isEmpty) continue;

      final existing = byKey[key];
      if (existing == null || brand.count > existing.count) {
        byKey[key] = _SearchFacet(
          id: brand.id,
          name: cleanName,
          count: brand.count,
        );
      }
    }

    final values = byKey.values.toList()
      ..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        if (byCount != 0) return byCount;
        return a.name.compareTo(b.name);
      });

    // En búsqueda general no enseñamos una sección de fabricante con una sola
    // opción, porque queda como un filtro roto y confunde al usuario. Si no hay
    // varias marcas reales, ocultamos la sección; dentro de categorías se usan
    // los filtros propios de ProductosPorCategoriaScreen.
    if (normalizedSelected.isEmpty && values.length < 2) {
      return const <_SearchFacet>[];
    }

    return values;
  }

  String _normalizeBrand(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9áéíóúüñ]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: 0.86,
        minChildSize: 0.45,
        maxChildSize: 0.94,
        builder: (context, controller) {
          return Container(
            decoration: const BoxDecoration(
              color: Color(0xFFF4F7FB),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              children: [
                _header(context),
                Expanded(
                  child: ListView(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                    children: [
                      _sectionCard(
                        title: 'Ordenar por',
                        icon: Icons.swap_vert_rounded,
                        children: [
                          _optionTile('Más recientes', 'date', Icons.access_time_rounded),
                          _optionTile('Precio bajo primero', 'price_asc', Icons.trending_up_rounded),
                          _optionTile('Precio alto primero', 'price_desc', Icons.trending_down_rounded),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _sectionCard(
                        title: 'Categorías del producto',
                        icon: Icons.folder_special_rounded,
                        subtitle: 'Resultados para "${widget.query}"',
                        children: widget.categories.isEmpty
                            ? [_emptyInfo('No hay categorías disponibles para esta búsqueda.')]
                            : widget.categories.map((item) => _facetTile(item, isCategory: true)).toList(),
                      ),
                      if (_visibleBrands.isNotEmpty || _brand.trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _sectionCard(
                          title: 'Fabricante',
                          icon: Icons.factory_rounded,
                          children: _visibleBrands.isEmpty
                              ? [_emptyInfo('No hay fabricantes disponibles para esta búsqueda.')]
                              : _visibleBrands.map((item) => _facetTile(item, isCategory: false)).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                _bottomButtons(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 14, 14),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.14), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.tune_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Filtros', style: TextStyle(fontFamily: 'Oswald', fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                Text('Resultados · "${widget.query}"', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white70)),
              ],
            ),
          ),
          IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE1E5EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title.toUpperCase(), style: const TextStyle(fontFamily: 'Oswald', fontSize: 13, fontWeight: FontWeight.w900, color: Colors.black87))),
            ],
          ),
          if (subtitle != null && subtitle.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(fontSize: 11.5, color: Color(0xFF6B7280), fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _optionTile(String title, String value, IconData icon) {
    final selected = _orderBy == value;
    return _plainTile(
      title: title,
      count: null,
      icon: icon,
      selected: selected,
      onTap: () => setState(() => _orderBy = selected ? '' : value),
    );
  }

  Widget _facetTile(_SearchFacet item, {required bool isCategory}) {
    final selected = isCategory
        ? _categoryId == item.id
        : _SearchEngine._normalize(_brand) == _SearchEngine._normalize(item.name);
    return _plainTile(
      title: item.name,
      count: item.count,
      icon: isCategory ? Icons.folder_rounded : Icons.sell_outlined,
      selected: selected,
      onTap: () {
        setState(() {
          if (isCategory) {
            if (selected) {
              _categoryId = 0;
              _categoryName = '';
            } else {
              _categoryId = item.id;
              _categoryName = item.name;
            }
          } else {
            _brand = selected ? '' : item.name;
          }
        });
      },
    );
  }

  Widget _plainTile({
    required String title,
    required int? count,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary.withOpacity(0.08) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: selected ? AppColors.primary : const Color(0xFFE1E5EC)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: selected ? AppColors.primary : const Color(0xFF6B7280)),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: selected ? AppColors.primary : AppColors.textPrimary))),
              if (count != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: selected ? AppColors.primary : const Color(0xFFEFF2F6), borderRadius: BorderRadius.circular(999)),
                  child: Text('$count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: selected ? Colors.white : const Color(0xFF6B7280))),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyInfo(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFE1E5EC))),
      child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF6B7280))),
    );
  }

  Widget _bottomButtons() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: const BoxDecoration(color: Color(0xFFF4F7FB), border: Border(top: BorderSide(color: Color(0xFFE1E5EC)))),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: widget.onReset,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: Color(0xFFD9DEE7)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Restablecer', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: () => widget.onApply(categoryId: _categoryId, categoryName: _categoryName, brand: _brand, orderBy: _orderBy),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Ver productos', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchFacet {
  final int id;
  final String name;
  final int count;

  const _SearchFacet({required this.id, required this.name, required this.count});
}

class _MutableFacet {
  final int id;
  final String name;
  int count = 0;

  _MutableFacet({required this.id, required this.name});
}

class _SearchEngine {
  static final Map<String, List<String>> _synonyms = {
    'camara': [
      'camara',
      'camaras',
      'camera',
      'cctv',
      'ip',
      'hd',
      'hdcvi',
      'turret',
      'bullet',
      'domo',
      'ptz',
      'lente',
      'varifocal',
    ],
    'grabador': [
      'grabador',
      'nvr',
      'xvr',
      'dvr',
      'recorder',
      'canales',
      'h265',
      'h.265',
      'poe',
    ],
    'alarma': [
      'alarma',
      'alarmas',
      'intrusion',
      'intrusión',
      'hub',
      'detector',
      'sirena',
      'teclado',
      'contacto',
      'jeweller',
      'fibra',
    ],
    'incendio': [
      'incendio',
      'fuego',
      'detector humo',
      'detector termico',
      'sirena incendio',
      'en54',
      'teletek',
    ],
    'acceso': [
      'acceso',
      'control acceso',
      'lector',
      'tarjeta',
      'biometrico',
      'biométrico',
      'cerradura',
      'terminal',
    ],
    'networking': [
      'networking',
      'red',
      'switch',
      'router',
      'poe',
      'wifi',
      'omada',
      'vigi',
      'tplink',
      'tp-link',
    ],
    '4g': [
      '4g',
      'lte',
      'sim',
      'm2m',
      'iot',
      'router 4g',
      'multioperador',
    ],
    'solar': [
      'solar',
      'panel solar',
      'autonomo',
      'autónomo',
      'bateria',
      'batería',
      'torre',
      'pod',
      'evolve',
    ],
    'analitica': [
      'analitica',
      'analítica',
      'ia',
      'ai',
      'deteccion',
      'detección',
      'persona',
      'vehiculo',
      'vehículo',
      'perimetral',
      'secury360',
    ],
  };

  static final List<String> _knownBrands = [
    'ajax',
    'dahua',
    'hikvision',
    'ksenia',
    'teletek',
    'tp-link',
    'tplink',
    'vigi',
    'omada',
    'mobotix',
    'secury360',
    'evolve',
    'wisim',
    'softguard',
    'mci',
    'powersafe',
    'power safe',
  ];

  static String cleanQuery(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static List<Product> sortByRelevance(List<Product> products, String query) {
    final terms = _expandedTerms(query);
    final scored = products
        .map(
          (product) => _ScoredProduct(
        product: product,
        score: _score(product, query, terms),
      ),
    )
        .toList();

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.product.name.compareTo(b.product.name);
    });

    return scored.map((item) => item.product).toList();
  }

  static int _score(Product product, String query, List<String> terms) {
    final normalizedQuery = _normalize(query);
    final name = _normalize(product.name);
    final sku = _normalize(product.sku);
    final description = _normalize(product.shortDescription);
    final fullText = '$name $sku $description';

    int score = 0;

    if (sku.isNotEmpty && sku == normalizedQuery) score += 500;
    if (sku.isNotEmpty && sku.contains(normalizedQuery)) score += 300;
    if (name == normalizedQuery) score += 260;
    if (name.startsWith(normalizedQuery)) score += 210;
    if (name.contains(normalizedQuery)) score += 170;

    for (final brand in _knownBrands) {
      final normalizedBrand = _normalize(brand);
      if (normalizedQuery.contains(normalizedBrand)) {
        if (name.contains(normalizedBrand)) score += 120;
        if (description.contains(normalizedBrand)) score += 60;
        if (sku.contains(normalizedBrand)) score += 90;
      }
    }

    for (final term in terms) {
      if (term.length < 2) continue;
      if (name.contains(term)) score += 38;
      if (sku.contains(term)) score += 45;
      if (description.contains(term)) score += 18;
      if (fullText.contains(term)) score += 10;
    }

    if (product.isInstock) score += 8;

    if (name.contains('kit') && normalizedQuery.contains('kit')) score += 35;
    if (name.contains('poe') && normalizedQuery.contains('poe')) score += 35;
    if (name.contains('wifi') && normalizedQuery.contains('wifi')) score += 35;
    if (name.contains('4g') && normalizedQuery.contains('4g')) score += 35;
    if (name.contains('en54') && normalizedQuery.contains('en54')) score += 45;

    if (name.contains('grado') && normalizedQuery.contains('grado')) {
      score += 30;
    }

    return score;
  }

  static List<String> _expandedTerms(String query) {
    final normalized = _normalize(query);
    final terms = <String>{};

    for (final raw in normalized.split(' ')) {
      final term = raw.trim();
      if (term.length >= 2) terms.add(term);
    }

    _synonyms.forEach((key, values) {
      final normalizedKey = _normalize(key);
      if (normalized.contains(normalizedKey) ||
          values.any((v) => normalized.contains(_normalize(v)))) {
        for (final value in values) {
          for (final part in _normalize(value).split(' ')) {
            if (part.trim().length >= 2) terms.add(part.trim());
          }
        }
      }
    });

    for (final brand in _knownBrands) {
      final normalizedBrand = _normalize(brand);
      if (normalized.contains(normalizedBrand)) {
        for (final part in normalizedBrand.split(' ')) {
          if (part.trim().length >= 2) terms.add(part.trim());
        }
      }
    }

    return terms.toList();
  }

  static List<Product> productsForFilterFacets(List<Product> products, String query) {
    final terms = _meaningfulTerms(query);
    if (terms.isEmpty) return products;

    final precise = products.where((product) {
      final text = _productFilterText(product);
      return terms.every((term) => _textContainsTerm(text, term));
    }).toList();

    // Si el endpoint devuelve pocos productos muy exactos, usamos esos para contar
    // fabricantes. Si no hay suficientes datos, mantenemos el conjunto original
    // para no dejar el filtro vacío.
    return precise.isNotEmpty ? precise : products;
  }

  static String _productFilterText(Product product) {
    final attributesText = product.attributes
        .map((attribute) => '${attribute.name} ${attribute.options.join(' ')}')
        .join(' ');
    return _normalize([
      product.name,
      product.sku,
      product.shortDescription,
      product.description,
      product.brandName ?? '',
      product.categoryNames.join(' '),
      product.categorySlugs.join(' '),
      attributesText,
    ].join(' '));
  }

  static List<String> _meaningfulTerms(String query) {
    final stopWords = <String>{
      'de', 'del', 'la', 'las', 'el', 'los', 'para', 'por', 'con', 'sin',
      'en', 'un', 'una', 'unos', 'unas', 'y', 'o', 'a', 'al',
    };
    final normalized = _normalize(query);
    final terms = <String>{};
    for (final raw in normalized.split(' ')) {
      var term = raw.trim();
      if (term.length < 3 || stopWords.contains(term)) continue;
      if (term.endsWith('es') && term.length > 4) {
        term = term.substring(0, term.length - 2);
      } else if (term.endsWith('s') && term.length > 3) {
        term = term.substring(0, term.length - 1);
      }
      if (term.length >= 3) terms.add(term);
    }
    return terms.toList();
  }

  static bool _textContainsTerm(String text, String term) {
    if (text.contains(term)) return true;
    if (term == 'caja' && text.contains('box')) return true;
    if (term == 'seguridad' && (text.contains('security') || text.contains('segur'))) return true;
    return false;
  }

  static bool isForbiddenFacetName(String value) {
    final normalized = _normalize(value);
    return normalized.isEmpty ||
        normalized.contains('sin categoria') ||
        normalized.contains('uncategorized') ||
        normalized.contains('oferta') ||
        normalized.contains('outlet') ||
        normalized.contains('formacion');
  }

  static bool looksLikeMainCategory(String value) {
    final normalized = _normalize(value);
    if (normalized.isEmpty) return false;
    const mainWords = [
      'video cctv hd',
      'video ip hd',
      'complementos',
      'intrusion',
      'accesos',
      'incendio',
      'networking',
      'drones pro',
      'energia',
      'anti hurto',
      'antihurto',
    ];
    return mainWords.any((item) => normalized == item || normalized.contains(item));
  }

  static int mainCategoryOrder(String value) {
    final normalized = _normalize(value);
    final order = <String>[
      'video cctv hd',
      'video ip hd',
      'complementos',
      'intrusion',
      'accesos',
      'incendio',
      'networking',
      'drones pro',
      'energia',
      'anti hurto',
      'antihurto',
    ];
    for (var i = 0; i < order.length; i++) {
      final key = order[i];
      if (normalized == key || normalized.contains(key)) return i;
    }
    return 999;
  }

  static List<String> detectedReadableTerms(String query) {
    final normalized = _normalize(query);
    final detected = <String>[];

    for (final brand in _knownBrands) {
      if (normalized.contains(_normalize(brand))) {
        detected.add(_brandLabel(brand));
      }
    }

    if (_containsAny(
      normalized,
      ['camara', 'camaras', 'cctv', 'turret', 'bullet', 'domo', 'ptz'],
    )) {
      detected.add('CCTV / Cámaras');
    }

    if (_containsAny(normalized, ['nvr', 'xvr', 'dvr', 'grabador'])) {
      detected.add('Grabadores');
    }

    if (_containsAny(
      normalized,
      ['alarma', 'intrusion', 'hub', 'detector', 'sirena'],
    )) {
      detected.add('Intrusión');
    }

    if (_containsAny(normalized, ['incendio', 'fuego', 'en54', 'humo'])) {
      detected.add('Incendio');
    }

    if (_containsAny(
      normalized,
      ['poe', 'switch', 'router', 'wifi', 'networking', 'red'],
    )) {
      detected.add('Networking');
    }

    if (_containsAny(normalized, ['4g', 'lte', 'sim', 'm2m', 'iot'])) {
      detected.add('IoT / M2M');
    }

    return detected.toSet().take(6).toList();
  }

  static List<String> suggestionsFor(String query) {
    final normalized = _normalize(query);

    if (_containsAny(normalized, ['camara', 'camera', 'cctv'])) {
      return ['cámara IP', 'cámara PoE', 'cámara Dahua', 'cámara Hikvision'];
    }

    if (_containsAny(normalized, ['grabador', 'nvr', 'xvr', 'dvr'])) {
      return ['NVR Dahua', 'grabador IP', 'XVR', 'NVR PoE'];
    }

    if (_containsAny(normalized, ['alarma', 'intrusion', 'intrusión'])) {
      return ['Ajax Hub', 'detector Ajax', 'sirena Ajax', 'Ksenia lares'];
    }

    if (_containsAny(normalized, ['incendio', 'fuego', 'en54'])) {
      return ['Teletek EN54', 'Ajax EN54', 'detector humo', 'central incendio'];
    }

    if (_containsAny(normalized, ['red', 'poe', 'switch', 'router', 'wifi'])) {
      return ['switch PoE', 'router 4G', 'Omada', 'VIGI'];
    }

    return ['Dahua', 'Ajax', 'Hikvision', 'cámara IP', 'NVR', 'switch PoE'];
  }

  static String _normalize(String value) {
    String text = value.toLowerCase().trim();

    const replacements = {
      'á': 'a',
      'à': 'a',
      'ä': 'a',
      'â': 'a',
      'é': 'e',
      'è': 'e',
      'ë': 'e',
      'ê': 'e',
      'í': 'i',
      'ì': 'i',
      'ï': 'i',
      'î': 'i',
      'ó': 'o',
      'ò': 'o',
      'ö': 'o',
      'ô': 'o',
      'ú': 'u',
      'ù': 'u',
      'ü': 'u',
      'û': 'u',
      'ñ': 'n',
      '/': ' ',
      '-': ' ',
      '_': ' ',
      '.': ' ',
      ',': ' ',
      ';': ' ',
      ':': ' ',
      '(': ' ',
      ')': ' ',
      '[': ' ',
      ']': ' ',
    };

    replacements.forEach((from, to) => text = text.replaceAll(from, to));

    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool _containsAny(String source, List<String> values) {
    return values.any((value) => source.contains(_normalize(value)));
  }

  static String _brandLabel(String brand) {
    switch (_normalize(brand)) {
      case 'tplink':
      case 'tp link':
        return 'TP-Link';
      case 'vigi':
        return 'VIGI';
      case 'omada':
        return 'Omada';
      case 'ajax':
        return 'Ajax';
      case 'dahua':
        return 'Dahua';
      case 'hikvision':
        return 'Hikvision';
      case 'ksenia':
        return 'Ksenia';
      case 'teletek':
        return 'Teletek';
      case 'mobotix':
        return 'Mobotix';
      case 'secury360':
        return 'Secury360';
      case 'evolve':
        return 'Evolve Xtender';
      case 'wisim':
        return 'WiSIM';
      default:
        return brand.toUpperCase();
    }
  }
}

class _ScoredProduct {
  final Product product;
  final int score;

  const _ScoredProduct({
    required this.product,
    required this.score,
  });
}

class ProductTileBusqueda extends ConsumerStatefulWidget {
  final Product p;
  final FirebaseService firebase;
  final VoidCallback? onGoCart;
  final VoidCallback? onGoQuotes;
  final bool canViewStockDetails;

  const ProductTileBusqueda({
    super.key,
    required this.p,
    required this.firebase,
    this.onGoCart,
    this.onGoQuotes,
    this.canViewStockDetails = false,
  });

  @override
  ConsumerState<ProductTileBusqueda> createState() =>
      _ProductTileBusquedaState();
}

class _ProductTileBusquedaState extends ConsumerState<ProductTileBusqueda> {
  int cantidad = 1;
  bool _isAddingToQuote = false;

  double _precioDouble(Product p) {
    return double.tryParse(p.price.replaceAll(',', '.').trim()) ?? 0;
  }

  String _formatearPrecio(double value) {
    return value <= 0
        ? 'Bajo consulta'
        : '${value.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  void _goToQuotesKeepingTabs() {
    final goQuotes = widget.onGoQuotes;

    if (goQuotes != null) {
      final navigator = Navigator.of(context);
      if (navigator.canPop()) navigator.popUntil((route) => route.isFirst);
      WidgetsBinding.instance.addPostFrameCallback((_) => goQuotes());
      return;
    }

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Producto añadido al presupuesto'),
        backgroundColor: AppColors.primary,
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final precio = _precioDouble(p);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE7E7E7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProductDetailScreen(
                      product: p,
                      onGoCart: widget.onGoCart,
                      onGoQuotes: widget.onGoQuotes,
                    ),
                  ),
                );
              },
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Hero(
                    tag: 'search_${p.id}',
                    child: ProductImageBusqueda(p: p),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                p.name,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.textPrimary,
                                  height: 1.17,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _stockChip(p),
                          ],
                        ),
                        if (widget.canViewStockDetails) ...[
                          const SizedBox(height: 6),
                          _SearchStockDetailsText(product: p),
                        ],
                        if (p.shortDescription.trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            p.shortDescription,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B7280),
                              height: 1.25,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Text(
                          _formatearPrecio(precio),
                          style: TextStyle(
                            fontSize: precio > 0 ? 22 : 18,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primary,
                            fontFamily: 'Oswald',
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _quantitySelector(p),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: p.canAddToCart
                          ? () {
                        ref
                            .read(cartProvider.notifier)
                            .addProduct(p, cantidad);

                        ScaffoldMessenger.of(context).clearSnackBars();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '$cantidad x ${p.name} añadido al carrito',
                            ),
                            backgroundColor: AppColors.primary,
                            duration: const Duration(seconds: 1),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                          : null,
                      icon: Icon(
                        p.canAddToCart
                            ? Icons.shopping_cart_outlined
                            : Icons.block_rounded,
                        size: 17,
                        color: Colors.white,
                      ),
                      label: Text(
                        p.isUnderConsultation
                            ? 'BAJO CONSULTA'
                            : (p.hasStock ? 'AÑADIR CARRITO' : 'SIN STOCK'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                          color: Colors.white,
                          fontFamily: 'Oswald',
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                        p.canAddToCart ? AppColors.primary : Colors.grey.shade400,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: OutlinedButton.icon(
                onPressed: (p.canRequestQuote && !_isAddingToQuote)
                    ? () => _addToQuote(p)
                    : null,
                icon: _isAddingToQuote
                    ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                )
                    : Icon(
                  p.canRequestQuote
                      ? Icons.description_outlined
                      : Icons.block_rounded,
                  size: 17,
                ),
                label: Text(
                  _isAddingToQuote
                      ? 'AÑADIENDO...'
                      : p.canRequestQuote
                      ? 'AÑADIR AL PRESUPUESTO'
                      : 'NO PRESUPUESTAR',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                    fontFamily: 'Oswald',
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  backgroundColor: p.canRequestQuote
                      ? Colors.white
                      : Colors.grey.shade100,
                  foregroundColor: AppColors.textPrimary,
                  disabledForegroundColor: Colors.grey.shade500,
                  side: BorderSide(
                    color: p.canRequestQuote
                        ? const Color(0xFFD9DEE7)
                        : Colors.grey.shade300,
                    width: 1.2,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quantitySelector(Product p) {
    final canChangeQuantity = p.canAddToCart || p.canRequestQuote;
    return Opacity(
      opacity: canChangeQuantity ? 1.0 : 0.55,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FB),
          border: Border.all(color: const Color(0xFFE1E4EA)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _qtyBtn(
              Icons.remove,
              enabled: canChangeQuantity && cantidad > 1,
              onTap: () {
                if (cantidad > 1) setState(() => cantidad--);
              },
            ),
            SizedBox(
              width: 34,
              child: Text(
                '$cantidad',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: p.canAddToCart ? AppColors.textPrimary : Colors.grey,
                ),
              ),
            ),
            _qtyBtn(
              Icons.add,
              enabled: canChangeQuantity && (p.maxPurchaseQty <= 0 || cantidad < p.maxPurchaseQty),
              isPrimary: canChangeQuantity,
              onTap: () {
                if (canChangeQuantity && (p.maxPurchaseQty <= 0 || cantidad < p.maxPurchaseQty)) {
                  setState(() => cantidad++);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _stockChip(Product p) {
    final bajoConsulta = p.isUnderConsultation;
    final hasStock = p.hasStock;
    final bgColor = bajoConsulta
        ? const Color(0xFFFFF7ED)
        : hasStock
        ? const Color(0xFFEAF7EE)
        : const Color(0xFFFDECEC);
    final textColor = bajoConsulta
        ? const Color(0xFFC2410C)
        : hasStock
        ? const Color(0xFF218047)
        : const Color(0xFFC62828);
    final label = bajoConsulta
        ? 'Bajo consulta'
        : hasStock
        ? 'En stock'
        : 'Sin stock';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: textColor.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: textColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              color: textColor,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _qtyBtn(
      IconData icon, {
        required bool enabled,
        required VoidCallback onTap,
        bool isPrimary = false,
      }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: SizedBox(
        width: 34,
        height: 42,
        child: Icon(
          icon,
          size: 17,
          color: enabled
              ? (isPrimary ? AppColors.primary : Colors.black87)
              : Colors.grey.shade400,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // AÑADIR AL PRESUPUESTO CON QuoteSelectionDialog
  // ═══════════════════════════════════════════════════════════════

  Future<void> _addToQuote(Product product) async {
    if (_isAddingToQuote) return;
    if (product.id == 0) return;

    if (!product.canRequestQuote) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se puede añadir "${product.name}" al presupuesto.'),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final precio = _precioDouble(product);

    // Mostrar el diálogo de selección de presupuesto
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => QuoteSelectionDialog(
        productName: product.name,
        productId: product.id,
        price: precio,
        quantity: cantidad,
      ),
    );

    // Usuario canceló el diálogo
    if (result == null || !mounted) return;

    setState(() => _isAddingToQuote = true);

    try {
      final action = result['action'] as String;
      final notifier = ref.read(localQuotesProvider.notifier);
      String mensaje = '';

      if (action == 'crear_y_anadir') {
        // CREAR NUEVO PRESUPUESTO
        final nombre = result['nombre'] as String;
        final orderId = DateTime.now().millisecondsSinceEpoch.toString();
        final nombreFinal = nombre.isNotEmpty ? nombre : 'Presupuesto #$orderId';

        await notifier.crearPresupuesto(
          orderId: orderId,
          nombre: nombreFinal,
        );

        await notifier.anadirItem(
          orderId: orderId,
          item: LocalQuoteItem(
            productId: product.id,
            productName: product.name,
            quantity: cantidad,
            price: precio,
          ),
        );

        mensaje = '$cantidad x ${product.name} añadido a "$nombreFinal"';
      } else if (action == 'anadir_existente') {
        // AÑADIR A PRESUPUESTO EXISTENTE
        final orderId = result['orderId'] as String;
        final nombre = result['nombre'] as String;

        await notifier.anadirItem(
          orderId: orderId,
          item: LocalQuoteItem(
            productId: product.id,
            productName: product.name,
            quantity: cantidad,
            price: precio,
          ),
        );

        mensaje = '$cantidad x ${product.name} añadido a "$nombre"';
      }

      if (mounted && mensaje.isNotEmpty) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(mensaje),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'VER',
              textColor: Colors.white,
              onPressed: _goToQuotesKeepingTabs,
            ),
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error en _addToQuote búsqueda: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAddingToQuote = false);
      }
    }
  }
}


class _SearchStockDetailsText extends StatelessWidget {
  final Product product;

  const _SearchStockDetailsText({required this.product});

  @override
  Widget build(BuildContext context) {
    final cleanDetails = product.stockDetailsText?.trim();
    if (cleanDetails == null || cleanDetails.isEmpty) {
      return const SizedBox.shrink();
    }

    const textColor = Color(0xFF1565C0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F8FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBFD7F2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.inventory_2_outlined,
            size: 13,
            color: textColor,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              'Stock: $cleanDetails',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.8,
                color: textColor,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProductImageBusqueda extends StatelessWidget {
  final Product p;

  const ProductImageBusqueda({
    super.key,
    required this.p,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: ColoredBox(
          color: Colors.white,
          child: CachedNetworkImage(
            imageUrl: p.imageUrl,
            fit: BoxFit.contain,
            placeholder: (context, url) => const ColoredBox(color: Colors.white),
            errorWidget: (context, url, error) => const Icon(
              Icons.broken_image,
              color: Colors.grey,
            ),
          ),
        ),
      ),
    );
  }
}
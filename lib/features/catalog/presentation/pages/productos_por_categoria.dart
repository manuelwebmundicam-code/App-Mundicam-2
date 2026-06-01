import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mundicam/core/cache/image_cache_service.dart';
import 'package:mundicam/core/cache/product_cache_service.dart';
import 'package:mundicam/core/firebase/firebase_service.dart';
import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/features/cart/presentation/providers/cart_provider.dart';
import 'package:mundicam/features/catalog/data/models/producto.dart';
import 'package:mundicam/features/catalog/presentation/pages/producto_detalles_page.dart';
import 'package:mundicam/features/catalog/presentation/providers/category_provider.dart';
import 'package:mundicam/features/catalog/presentation/providers/filter_provider.dart';
import 'package:mundicam/features/catalog/presentation/providers/products_paginated_provider.dart';
import 'package:mundicam/features/catalog/presentation/widgets/filtro_selector.dart';
import 'package:mundicam/features/quotes/presentation/providers/local_quote_provider.dart';
import 'package:mundicam/features/quotes/data/models/local_quote_model.dart';
import 'package:mundicam/shared/theme/app_theme.dart';

import '../../../quotes/presentation/widgets/quote_selection_dialog.dart';

class ProductosPorCategoriaScreen extends ConsumerStatefulWidget {
  final int categoryId;
  final String categoryName;
  final VoidCallback? onGoCart;
  final VoidCallback? onGoQuotes;

  const ProductosPorCategoriaScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
    this.onGoCart,
    this.onGoQuotes,
  });

  @override
  ConsumerState<ProductosPorCategoriaScreen> createState() => _ProductosPorCategoriaScreenState();
}

class _ProductosPorCategoriaScreenState extends ConsumerState<ProductosPorCategoriaScreen> {
  static const Duration _suggestionsCacheTtl = Duration(minutes: 3);
  static int? _lastOpenedCategoryId;
  static bool _preserveFiltersForNextCategoryOpen = false;

  final FirebaseService _firebase = FirebaseService();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _scrollTimer;
  Timer? _searchDebounce;
  Timer? _suggestionsDebounce;
  bool _isLoadingMore = false;
  bool _isLoadingSuggestions = false;
  bool _showScrollTopButton = false;
  int _suggestionsToken = 0;
  List<_CatalogSearchSuggestion> _searchSuggestions = [];

  @override
  void initState() {
    super.initState();

    final previousCategoryId = _lastOpenedCategoryId;
    final preserveFilters = _preserveFiltersForNextCategoryOpen;
    _lastOpenedCategoryId = widget.categoryId;
    _preserveFiltersForNextCategoryOpen = false;

    final currentFilters = ref.read(productFilterProvider);
    final shouldClearFiltersFromOtherCategory = !preserveFilters &&
        previousCategoryId != null &&
        previousCategoryId != widget.categoryId &&
        currentFilters.hasActiveFilters;

    _searchController.text = currentFilters.search;

    _scrollController.addListener(_onScrollThrottled);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (shouldClearFiltersFromOtherCategory) {
        _searchController.clear();
        ref.read(productFilterProvider.notifier).reset();
      }

      _prewarmCategorySearchCache();
    });
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _searchDebounce?.cancel();
    _suggestionsDebounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScrollThrottled() {
    if (_scrollTimer?.isActive ?? false) return;
    _scrollTimer = Timer(const Duration(milliseconds: 100), () {
      if (!_scrollController.hasClients) return;

      final currentOffset = _scrollController.position.pixels;
      final shouldShowScrollTopButton = currentOffset > 650;

      if (shouldShowScrollTopButton != _showScrollTopButton && mounted) {
        setState(() {
          _showScrollTopButton = shouldShowScrollTopButton;
        });
      }

      if (currentOffset >= _scrollController.position.maxScrollExtent - 300) {
        final notifier = ref.read(
          productsPaginatedProvider(widget.categoryId).notifier,
        );
        if (!notifier.isLoading && notifier.hasMore && !_isLoadingMore) {
          _isLoadingMore = true;
          notifier.loadNextPage().then((_) {
            _isLoadingMore = false;
          });
        }
      }
    });
  }

  Future<void> _scrollToTop() async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (!_scrollController.hasClients) return;

    if (_showScrollTopButton && mounted) {
      setState(() {
        _showScrollTopButton = false;
      });
    }

    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }


  List<String> _prewarmTermsForCategory(String categoryName) {
    final compact = _compactForSearch(categoryName);

    if (compact.contains('complement') ||
        compact.contains('accesorio') ||
        compact.contains('energia')) {
      return const ['rj45', 'cat6', 'pila', 'fuente'];
    }

    if (compact.contains('video') ||
        compact.contains('cctv') ||
        compact.contains('camara') ||
        compact.contains('iphd')) {
      return const ['domo', 'bullet', 'nvr', 'dahua'];
    }

    if (compact.contains('incendio')) {
      return const ['detector', 'sirena', 'central'];
    }

    if (compact.contains('intrusion') || compact.contains('alarma')) {
      return const ['ajax', 'sensor', 'mando'];
    }

    if (compact.contains('network') || compact.contains('red') || compact.contains('wifi')) {
      return const ['switch', 'poe', 'router'];
    }

    return const [];
  }

  void _prewarmCategorySearchCache() {
    final terms = _prewarmTermsForCategory(widget.categoryName);
    if (terms.isEmpty) return;

    final cache = ProductCacheService();
    final prewarmKey = 'prewarm|cat:${widget.categoryId}|${widget.categoryName.toLowerCase().trim()}';
    if (!cache.shouldPrewarm(prewarmKey)) return;
    cache.markPrewarmRun(prewarmKey);

    Future<void>.delayed(const Duration(milliseconds: 850), () async {
      if (!mounted) return;

      for (final term in terms.take(3)) {
        try {
          await ApiService()
              .getProductosCatalogoFiltrado(
            categoryId: widget.categoryId,
            search: term,
            page: 1,
            perPage: 12,
            orderBy: 'date',
          )
              .timeout(const Duration(milliseconds: 1500));
        } catch (_) {
          // Precarga silenciosa: nunca debe afectar al usuario.
        }
      }
    });
  }

  void _reloadCurrentCategory({
    bool scrollTop = true,
  }) {
    _isLoadingMore = false;

    final notifier = ref.read(
      productsPaginatedProvider(widget.categoryId).notifier,
    );

    notifier.clearCacheForCurrentCategory();
    unawaited(notifier.loadFirstPage(forceRefresh: true));

    if (scrollTop) {
      unawaited(_scrollToTop());
    }
  }

  void _onFiltersChanged(MundiFilters next) {
    _searchDebounce?.cancel();

    final nextSearch = next.search.trim();
    if (_searchController.text.trim() != nextSearch) {
      _searchController.text = next.search;
      _searchController.selection = TextSelection.fromPosition(
        TextPosition(offset: _searchController.text.length),
      );
    }

    _reloadCurrentCategory();
  }

  void _onSearchChanged(String value) {
    // El texto escrito solo alimenta el autocompletado.
    // No aplicamos búsqueda al listado hasta que el usuario confirme
    // con Enter/lupa o pulse una sugerencia. Así la categoría actual
    // no desaparece mientras se escribe una búsqueda fuera de contexto.
    _searchDebounce?.cancel();
    setState(() {});
    _scheduleSearchSuggestions(value);
  }

  void _scheduleSearchSuggestions(String value) {
    _suggestionsDebounce?.cancel();

    final clean = value.trim();
    if (clean.length < 3) {
      _suggestionsToken++;
      if (_searchSuggestions.isNotEmpty || _isLoadingSuggestions) {
        setState(() {
          _searchSuggestions = [];
          _isLoadingSuggestions = false;
        });
      }
      return;
    }

    final quickSuggestions = _fallbackQuickSuggestions(clean);
    if (quickSuggestions.isNotEmpty) {
      setState(() {
        _searchSuggestions = quickSuggestions;
        _isLoadingSuggestions = true;
      });
    }

    _suggestionsDebounce = Timer(const Duration(milliseconds: 300), () async {
      final token = ++_suggestionsToken;
      if (!mounted) return;

      if (_searchSuggestions.isEmpty) {
        setState(() => _isLoadingSuggestions = true);
      }

      try {
        final suggestions = await _buildSmartSuggestions(clean).timeout(
          const Duration(seconds: 4),
        );

        if (!mounted || token != _suggestionsToken) return;
        setState(() {
          _searchSuggestions = suggestions.isEmpty ? quickSuggestions : suggestions;
          _isLoadingSuggestions = false;
        });
      } catch (_) {
        if (!mounted || token != _suggestionsToken) return;
        setState(() {
          _searchSuggestions = quickSuggestions;
          _isLoadingSuggestions = false;
        });
      }
    });
  }

  void _hideSearchSuggestions() {
    _suggestionsDebounce?.cancel();
    _suggestionsToken++;
    if (_searchSuggestions.isEmpty && !_isLoadingSuggestions) return;
    setState(() {
      _searchSuggestions = [];
      _isLoadingSuggestions = false;
    });
  }

  String _suggestionsCacheKey(String query) {
    return 'search_suggestions|cat:${widget.categoryId}|name:${widget.categoryName.toLowerCase().trim()}|q:${query.toLowerCase().trim()}';
  }

  List<_CatalogSearchSuggestion>? _readSuggestionsCache(String key) {
    return ProductCacheService().getMemory<List<_CatalogSearchSuggestion>>(key);
  }

  void _writeSuggestionsCache(String key, List<_CatalogSearchSuggestion> suggestions) {
    ProductCacheService().cacheMemory<List<_CatalogSearchSuggestion>>(
      key,
      suggestions,
      ttl: _suggestionsCacheTtl,
    );
  }

  Future<List<_CatalogSearchSuggestion>> _buildSmartSuggestions(
      String rawQuery,
      ) async {
    final cleanQuery = rawQuery.trim();
    if (cleanQuery.length < 3) return [];

    final cacheKey = _suggestionsCacheKey(cleanQuery);
    final cachedSuggestions = _readSuggestionsCache(cacheKey);
    if (cachedSuggestions != null) {
      return cachedSuggestions;
    }

    final categoryContext = widget.categoryName;
    final queryIntents = _detectSearchIntents(cleanQuery);
    final categoryIntents = _detectSearchIntents(categoryContext);
    final tokens = _meaningfulTokens(cleanQuery);
    final skuLike = _looksLikeSku(cleanQuery);
    final searchTerms = _buildProductSearchTerms(
      cleanQuery: cleanQuery,
      tokens: tokens,
      skuLike: skuLike,
    );

    final localProductsById = <int, Product>{};
    final globalProductsById = <int, Product>{};

    Future<void> addProducts({
      required int? categoryId,
      required Map<int, Product> target,
      required int perPage,
    }) async {
      final timeout = queryIntents.contains('accessory')
          ? const Duration(milliseconds: 900)
          : const Duration(milliseconds: 1400);

      for (final term in searchTerms.take(2)) {
        try {
          final result = await ApiService().getProductosCatalogoFiltrado(
            categoryId: categoryId,
            search: term,
            page: 1,
            perPage: perPage,
            orderBy: 'date',
          ).timeout(timeout);
          for (final product in result.products) {
            target[product.id] = product;
          }
        } catch (_) {
          // Las sugerencias no deben bloquear la búsqueda principal.
        }
      }
    }

    await addProducts(
      categoryId: widget.categoryId,
      target: localProductsById,
      perPage: 10,
    );

    final localScoredProducts = localProductsById.values
        .map(
          (product) => _ScoredProduct(
        product: product,
        score: _scoreSuggestionProduct(
          product,
          cleanQuery,
          tokens,
          queryIntents,
          skuLike,
        ),
      ),
    )
        .where((item) => item.score > 0)
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final shouldSearchGlobal = localScoredProducts.length < 3 ||
        _hasClearExternalIntent(
          queryIntents: queryIntents,
          categoryIntents: categoryIntents,
          categoryName: categoryContext,
        );

    if (shouldSearchGlobal) {
      await addProducts(
        categoryId: null,
        target: globalProductsById,
        perPage: 10,
      );

      // Evitamos duplicar productos que ya están dentro de la categoría actual.
      for (final id in localProductsById.keys) {
        globalProductsById.remove(id);
      }
    }

    final globalScoredProducts = globalProductsById.values
        .map(
          (product) => _ScoredProduct(
        product: product,
        score: _scoreSuggestionProduct(
          product,
          cleanQuery,
          tokens,
          queryIntents,
          skuLike,
        ) +
            8,
      ),
    )
        .where((item) => item.score > 0)
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final redirectTarget = shouldSearchGlobal
        ? await _resolveRedirectCategoryForQuery(cleanQuery, queryIntents)
        : null;

    final suggestionTarget = redirectTarget != null &&
        redirectTarget.id != widget.categoryId
        ? redirectTarget
        : null;

    final suggestions = <_CatalogSearchSuggestion>[];
    final usedKeys = <String>{};

    void addSuggestion(_CatalogSearchSuggestion suggestion) {
      final key = suggestion.uniqueKey;
      if (usedKeys.contains(key)) return;
      usedKeys.add(key);
      suggestions.add(suggestion);
    }

    final externalAccessorySearch = queryIntents.contains('accessory') &&
        suggestionTarget != null &&
        suggestionTarget.id != widget.categoryId;

    // Si el usuario está en una familia equivocada y busca un componente
    // (cable, RJ45, pila, fuente...), priorizamos el salto al apartado correcto
    // y las sugerencias de búsqueda. No mostramos productos destacados de la
    // familia actual/global porque suelen ser cámaras, grabadores o monitores
    // cuya ficha menciona RJ45/cable/alimentación, pero no son el componente.
    if (suggestionTarget != null) {
      addSuggestion(
        _CatalogSearchSuggestion.redirect(
          title: 'Buscar “$cleanQuery” en ${suggestionTarget.name}',
          subtitle: 'Parece más relacionado con ${suggestionTarget.name}',
          value: cleanQuery,
          targetCategoryId: suggestionTarget.id,
          targetCategoryName: suggestionTarget.name,
        ),
      );
    }

    if (!externalAccessorySearch) {
      for (final scored in localScoredProducts.take(3)) {
        addSuggestion(
          _CatalogSearchSuggestion.product(
            scored.product,
            skuLike: skuLike,
          ),
        );
      }

      if (globalScoredProducts.isNotEmpty) {
        for (final scored in globalScoredProducts.take(localScoredProducts.isEmpty ? 4 : 2)) {
          addSuggestion(
            _CatalogSearchSuggestion.product(
              scored.product,
              skuLike: skuLike,
              global: true,
            ),
          );
        }
      }
    }

    final brandSuggestions = await _buildBrandSuggestions(cleanQuery);
    for (final brandSuggestion in brandSuggestions.take(3)) {
      addSuggestion(brandSuggestion);
    }

    final suggestionsCategoryName = suggestionTarget?.name ?? widget.categoryName;

    for (final text in _technicalCompletionsFor(
      cleanQuery,
      suggestionsCategoryName,
    )) {
      final hasRedirectTarget = suggestionTarget != null;
      final accessoryIntent = queryIntents.contains('accessory');

      // En accesorios/componentes la sugerencia debe acompañar lo que escribe
      // el usuario. Si escribe “cable rj45”, debe poder buscar exactamente eso,
      // no convertirlo en una sugerencia genérica que abra cámaras por accidente.
      final suggestionValue = accessoryIntent
          ? text
          : hasRedirectTarget
          ? cleanQuery
          : text;

      addSuggestion(
        _CatalogSearchSuggestion.query(
          title: text,
          subtitle: hasRedirectTarget
              ? 'Buscar en $suggestionsCategoryName'
              : 'Buscar en $suggestionsCategoryName',
          value: suggestionValue,
          targetCategoryId: suggestionTarget?.id,
          targetCategoryName: suggestionTarget?.name,
        ),
      );
      if (suggestions.length >= 8) break;
    }

    if (suggestions.isEmpty) {
      for (final fallback in _fallbackQuickSuggestions(cleanQuery)) {
        addSuggestion(fallback);
        if (suggestions.length >= 8) break;
      }
    }

    final finalSuggestions = suggestions.take(8).toList();
    _writeSuggestionsCache(cacheKey, finalSuggestions);
    return finalSuggestions;
  }

  List<_CatalogSearchSuggestion> _fallbackQuickSuggestions(String rawQuery) {
    final cleanQuery = rawQuery.trim();
    if (cleanQuery.length < 3) return [];

    final suggestions = <_CatalogSearchSuggestion>[];
    final used = <String>{};

    void addQuery(String title) {
      final cleanTitle = title.trim();
      if (cleanTitle.isEmpty) return;
      final key = cleanTitle.toLowerCase();
      if (used.contains(key)) return;
      used.add(key);
      suggestions.add(
        _CatalogSearchSuggestion.query(
          title: cleanTitle,
          subtitle: 'Buscar en ${widget.categoryName}',
          value: cleanTitle,
        ),
      );
    }

    for (final text in _technicalCompletionsFor(cleanQuery, widget.categoryName)) {
      addQuery(text);
      if (suggestions.length >= 6) break;
    }

    if (suggestions.isEmpty) {
      addQuery(cleanQuery);
    }

    return suggestions.take(6).toList();
  }

  Future<List<_CatalogSearchSuggestion>> _buildBrandSuggestions(String rawQuery) async {
    final cleanQuery = rawQuery.trim();
    if (cleanQuery.length < 3) return [];

    final normalizedQuery = _compactForSearch(cleanQuery);
    if (normalizedQuery.length < 3) return [];

    try {
      final marcas = await ApiService()
          .getMarcas(hideEmpty: true)
          .timeout(const Duration(seconds: 2));

      final scored = <_ScoredBrand>[];
      final used = <String>{};

      for (final marca in marcas) {
        final idRaw = marca['id'];
        final id = _intFromDynamic(idRaw);
        final name = marca['name']?.toString().trim() ?? '';
        if (id == null || id <= 0 || name.isEmpty) continue;

        final normalizedName = _compactForSearch(name);
        if (normalizedName.length < 3) continue;
        if (used.contains(normalizedName)) continue;

        int score = 0;
        if (normalizedName == normalizedQuery) {
          score = 100;
        } else if (normalizedName.startsWith(normalizedQuery)) {
          score = 80;
        } else if (normalizedName.contains(normalizedQuery)) {
          score = 55;
        }

        if (score <= 0) continue;
        used.add(normalizedName);
        scored.add(_ScoredBrand(id: id, name: name, score: score));
      }

      scored.sort((a, b) => b.score.compareTo(a.score));

      return scored
          .take(4)
          .map(
            (brand) => _CatalogSearchSuggestion.brand(
          brandName: brand.name,
          brandId: brand.id,
          categoryName: widget.categoryName,
        ),
      )
          .toList();
    } catch (_) {
      return [];
    }
  }

  int? _intFromDynamic(dynamic value) {
    if (value is int && value > 0) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  bool _hasClearExternalIntent({
    required Set<String> queryIntents,
    required Set<String> categoryIntents,
    required String categoryName,
  }) {
    if (queryIntents.isEmpty) return false;

    final normalizedCategory = _compactForSearch(categoryName);

    // Si el usuario busca un componente/accesorio desde una familia de producto
    // (por ejemplo VIDEO IP HD), no debe quedarse ahí mostrando cámaras solo
    // porque la ficha mencione RJ45, batería o fuente en la descripción.
    if (queryIntents.contains('accessory')) {
      final isAlreadyAccessoryContext = categoryIntents.contains('accessory') ||
          normalizedCategory.contains('complement') ||
          normalizedCategory.contains('accesorio') ||
          normalizedCategory.contains('energia') ||
          normalizedCategory.contains('alimentacion') ||
          normalizedCategory.contains('networking') ||
          normalizedCategory.contains('redes');
      return !isAlreadyAccessoryContext;
    }

    if (categoryIntents.isEmpty) return false;

    // Si el usuario está en Incendio y escribe "bullet 4mp", la intención es vídeo.
    // En ese caso buscamos globalmente y ofrecemos salto a la familia correcta.
    final overlap = queryIntents.intersection(categoryIntents);
    if (overlap.isNotEmpty) return false;

    if (normalizedCategory.contains('video') || normalizedCategory.contains('iphd')) {
      return false;
    }

    return true;
  }

  Future<_SearchRedirectTarget?> _resolveRedirectCategoryForQuery(
      String query,
      Set<String> intents,
      ) async {
    if (intents.isEmpty) return null;

    try {
      final categories = await ref.read(categoriesProvider.future).timeout(
        const Duration(seconds: 4),
      );
      if (categories.isEmpty) return null;

      final ordered = [...categories];
      final queryCompact = _compactForSearch(query);
      final powerAccessory = _isPowerAccessoryQuery(query);
      final connectivityAccessory = _isConnectivityAccessoryQuery(query);

      int scoreCategory(dynamic category) {
        final name = category.name.toString();
        final compact = _compactForSearch(name);
        int score = 0;

        if (intents.contains('accessory')) {
          if (compact.contains('complement') || compact.contains('accesorio')) score += 120;
          if (compact.contains('energia') || compact.contains('alimentacion')) {
            score += powerAccessory ? 115 : 55;
          }
          if (compact.contains('networking') || compact.contains('redes') || compact.contains('net')) {
            score += connectivityAccessory ? 110 : 55;
          }
          if (compact.contains('cable') || compact.contains('conector')) score += 90;
          if (compact.contains('intrusion') && (queryCompact.contains('pila') || queryCompact.contains('bateria'))) score += 45;
          if (compact.contains('video') || compact.contains('iphd') || compact.contains('cctv')) score -= 80;
        }

        if (intents.contains('video')) {
          if (compact.contains('videoip') || compact.contains('iphd')) score += 100;
          if (compact.contains('cctv') || compact.contains('video')) score += 70;
        }
        if (intents.contains('software')) {
          if (compact.contains('videoip') || compact.contains('iphd')) score += 90;
          if (compact.contains('software')) score += 80;
        }
        if (intents.contains('incendio')) {
          if (compact.contains('incendio')) score += 100;
        }
        if (intents.contains('intrusion')) {
          if (compact.contains('intrusion') || compact.contains('alarma')) score += 100;
        }
        if (intents.contains('networking')) {
          if (compact.contains('networking') || compact.contains('redes') || compact.contains('net')) score += 100;
        }

        return score;
      }

      ordered.sort((a, b) => scoreCategory(b).compareTo(scoreCategory(a)));
      if (scoreCategory(ordered.first) <= 0) return null;

      final id = ordered.first.id;
      final name = ordered.first.name.toString();
      if (id <= 0 || name.trim().isEmpty) return null;

      return _SearchRedirectTarget(id: id, name: name);
    } catch (_) {
      return null;
    }
  }

  List<String> _buildProductSearchTerms({
    required String cleanQuery,
    required List<String> tokens,
    required bool skuLike,
  }) {
    final terms = <String>{cleanQuery};

    if (skuLike) {
      terms.add(cleanQuery.replaceAll(' ', ''));
    }

    final focused = tokens.where((token) {
      final normalized = _normalizeForSearch(token);
      return normalized.length >= 2 &&
          !{
            'camara',
            'camaras',
            'camera',
            'cctv',
            'video',
            'ip',
            'hd',
            'para',
            'con',
          }.contains(normalized);
    }).toList();

    if (focused.isNotEmpty) {
      terms.add(focused.join(' '));
    }

    return terms.toList();
  }

  void _handleSuggestionTap(_CatalogSearchSuggestion suggestion) {
    _hideSearchSuggestions();
    FocusScope.of(context).unfocus();

    if (suggestion.type == _CatalogSearchSuggestionType.brand &&
        suggestion.brandId != null &&
        suggestion.brandId! > 0 &&
        suggestion.brandName != null &&
        suggestion.brandName!.trim().isNotEmpty) {
      _searchController.clear();
      ref.read(productFilterProvider.notifier).clearSearch();
      ref.read(productFilterProvider.notifier).setBrand(
        name: suggestion.brandName!.trim(),
        id: suggestion.brandId!,
      );
      return;
    }

    if (suggestion.targetCategoryId != null &&
        suggestion.targetCategoryId! > 0 &&
        suggestion.targetCategoryId != widget.categoryId) {
      ref.read(productFilterProvider.notifier).reset();
      ref.read(productFilterProvider.notifier).setSearch(suggestion.value);
      _preserveFiltersForNextCategoryOpen = true;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ProductosPorCategoriaScreen(
            categoryId: suggestion.targetCategoryId!,
            categoryName: suggestion.targetCategoryName ?? 'Catálogo',
            onGoCart: widget.onGoCart,
            onGoQuotes: widget.onGoQuotes,
          ),
        ),
      );
      return;
    }

    final product = suggestion.product;
    if (product != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ProductDetailScreen(
            product: product,
            onGoCart: widget.onGoCart,
            onGoQuotes: widget.onGoQuotes,
            contextCategoryName: suggestion.global ? 'Catálogo MundiCam' : widget.categoryName,
          ),
        ),
      );
      return;
    }

    _searchController.text = suggestion.value;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: _searchController.text.length),
    );
    ref.read(productFilterProvider.notifier).setSearch(suggestion.value);
  }

  String _normalizeForSearch(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('ä', 'a')
        .replaceAll('â', 'a')
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ì', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('î', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ò', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ù', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('û', 'u')
        .replaceAll('ñ', 'n');
  }

  String _compactForSearch(String value) {
    return _normalizeForSearch(value)
        .replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  List<String> _meaningfulTokens(String value) {
    final normalized = _normalizeForSearch(value)
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    final stopWords = <String>{
      'de',
      'del',
      'la',
      'el',
      'los',
      'las',
      'para',
      'con',
      'en',
      'un',
      'una',
    };

    return normalized
        .split(RegExp(r'\s+'))
        .map((token) => token.trim())
        .where((token) => token.length >= 2 && !stopWords.contains(token))
        .toList();
  }

  bool _looksLikeSku(String value) {
    if (_detectSearchIntents(value).contains('accessory')) return false;
    final compact = value.replaceAll(' ', '');
    final hasDigit = RegExp(r'\d').hasMatch(compact);
    final hasSkuSeparator = RegExp(r'[-_/()]').hasMatch(compact);
    final hasUpperPrefix = RegExp(r'^[A-Za-z]{2,}[-_]').hasMatch(compact);
    return compact.length >= 4 &&
        (hasDigit && (hasSkuSeparator || hasUpperPrefix || compact.length >= 7));
  }

  Set<String> _detectSearchIntents(String value) {
    final normalized = _normalizeForSearch(value);
    final compact = _compactForSearch(value);
    final intents = <String>{};

    bool containsAny(List<String> values) {
      return values.any((term) => compact.contains(_compactForSearch(term)));
    }

    if (containsAny([
      'cable',
      'cables',
      'conector',
      'conectores',
      'rj45',
      'rj 45',
      'rj-45',
      'latiguillo',
      'latiguillos',
      'utp',
      'ftp',
      'cat5',
      'cat6',
      'cat7',
      'bnc',
      'coaxial',
      'patch',
      'pila',
      'pilas',
      'bateria',
      'baterias',
      'batería',
      'baterías',
      'fuente',
      'fuentes',
      'alimentador',
      'alimentadores',
      'alimentacion',
      'alimentación',
      'transformador',
      'adaptador',
      'cargador',
    ])) {
      intents.add('accessory');
    }

    if (containsAny([
      'camara',
      'camaras',
      'camera',
      'domo',
      'bullet',
      'turret',
      'ptz',
      'nvr',
      'xvr',
      'dvr',
      'cctv',
      'video',
      'anpr',
      'lpr',
      '8mp',
      '4mp',
      '5mp',
      'iphd',
    ])) {
      intents.add('video');
    }

    if (containsAny([
      'software',
      'licencia',
      'licencias',
      'hikcentral',
      'dss',
      'dmss',
      'ivss',
    ])) {
      intents.add('software');
    }

    if (containsAny([
      'incendio',
      'fuego',
      'detector',
      'sirena',
      'teletek',
      'central incendio',
    ])) {
      intents.add('incendio');
    }

    if (containsAny([
      'intrusion',
      'intrusión',
      'alarma',
      'ajax',
      'lares',
      'ksenia',
      'sensor',
      'contacto',
      'mando',
    ])) {
      intents.add('intrusion');
    }

    if (containsAny([
      'switch',
      'router',
      'networking',
      'red',
      'redes',
      'poe',
      'wifi',
      'tp link',
      'tplink',
      'ruijie',
      'ubiquiti',
    ])) {
      intents.add('networking');
    }

    if (normalized.contains('ip software')) {
      intents.add('software');
    }

    return intents;
  }

  List<String> _variantsForToken(String token) {
    final normalized = _normalizeForSearch(token);
    final compact = _compactForSearch(token);

    final variants = <String>{compact};

    switch (compact) {
      case 'cam':
      case 'camar':
      case 'camara':
      case 'camaras':
      case 'camera':
        variants.addAll(['camara', 'camaras', 'camera', 'cctv', 'video']);
        break;
      case 'domo':
      case 'dome':
        variants.addAll(['domo', 'dome', 'turret', 'minidomo']);
        break;
      case 'bullet':
      case 'tubular':
        variants.addAll(['bullet', 'tubular']);
        break;
      case 'grabador':
      case 'grabadores':
        variants.addAll(['grabador', 'nvr', 'xvr', 'dvr']);
        break;
      case 'matricula':
      case 'matriculas':
        variants.addAll(['matricula', 'anpr', 'lpr']);
        break;
      case 'wifi':
      case 'wi':
        variants.addAll(['wifi', 'wi-fi', 'wireless']);
        break;
      case 'rj45':
      case 'rj':
        variants.addAll(['rj45', 'rj 45', 'rj-45', 'conectorrj45', 'latiguillorj45']);
        break;
      case 'cable':
      case 'cables':
      case 'latiguillo':
      case 'latiguillos':
        variants.addAll(['cable', 'cables', 'latiguillo', 'latiguillos', 'utp', 'ftp']);
        break;
      case 'conector':
      case 'conectores':
        variants.addAll(['conector', 'conectores', 'rj45', 'bnc']);
        break;
      case 'pila':
      case 'pilas':
      case 'bateria':
      case 'baterias':
        variants.addAll(['pila', 'pilas', 'bateria', 'baterias', 'batería', 'baterías']);
        break;
      case 'fuente':
      case 'fuentes':
      case 'alimentador':
      case 'alimentacion':
        variants.addAll(['fuente', 'fuentes', 'alimentador', 'alimentacion', 'alimentación', 'transformador']);
        break;
      case '8':
      case '8mp':
        variants.addAll(['8mp', '8mpx', '8megapixel', '4k']);
        break;
      case '4':
      case '4mp':
        variants.addAll(['4mp', '4mpx', '4megapixel']);
        break;
      case '5':
      case '5mp':
        variants.addAll(['5mp', '5mpx', '5megapixel']);
        break;
    }

    if (normalized.endsWith('s') && compact.length > 3) {
      variants.add(compact.substring(0, compact.length - 1));
    }

    return variants.toList();
  }

  bool _isConnectivityAccessoryQuery(String value) {
    final compact = _compactForSearch(value);
    return RegExp(r'(cable|cables|rj45|rj45|latiguillo|utp|ftp|cat5|cat6|cat7|bnc|coaxial|patch|conector)').hasMatch(compact);
  }

  bool _isPowerAccessoryQuery(String value) {
    final compact = _compactForSearch(value);
    return RegExp(r'(pila|pilas|bateria|baterias|fuente|fuentes|alimentador|alimentacion|transformador|adaptador|cargador)').hasMatch(compact);
  }

  bool _isAccessoryWord(String value) {
    final compact = _compactForSearch(value);
    return RegExp(r'(cable|latiguillo|conector|rj45|utp|ftp|cat5|cat6|cat7|bnc|coaxial|patch|pila|pilas|bateria|baterias|fuente|alimentador|alimentacion|transformador|adaptador|cargador)').hasMatch(compact);
  }

  bool _isMainDeviceNoiseForAccessorySearch(String productName) {
    final compactName = _compactForSearch(productName);

    final hasMainDeviceWord = RegExp(
      r'(camara|camera|nvr|xvr|dvr|grabador|monitor|pantalla|joystick|posicionador|central|detector|panel|teclado|sirena|router|switch|antena)',
    ).hasMatch(compactName);

    if (!hasMainDeviceWord) return false;

    // Un accesorio real puede llamarse “Cable para cámara” o “Fuente para NVR”.
    // Lo permitimos si el término de accesorio aparece claramente al principio.
    final accessoryMatch = RegExp(
      r'(cable|latiguillo|conector|bobina|pila|bateria|fuente|alimentador|transformador|adaptador|cargador)',
    ).firstMatch(compactName);

    if (accessoryMatch == null) return true;

    return accessoryMatch.start > 10;
  }

  bool _hasStrongAccessoryProductMatch(
      Product product,
      String rawQuery,
      List<String> tokens,
      ) {
    final compactQuery = _compactForSearch(rawQuery);

    // Para componentes/accesorios NO usamos descripción ni atributos técnicos
    // como coincidencia principal. Una cámara puede mencionar RJ45, cable o
    // alimentación en la ficha, pero eso no significa que sea un cable, pila o
    // fuente. La coincidencia fuerte debe estar en nombre/SKU/marca.
    final strongText = _compactForSearch([
      product.name,
      product.sku,
      product.brandName ?? '',
    ].join(' '));

    if (_isMainDeviceNoiseForAccessorySearch(product.name)) {
      return false;
    }

    if (_isConnectivityAccessoryQuery(rawQuery)) {
      final hasAccessoryName = RegExp(
        r'(cable|latiguillo|conector|rj45|utp|ftp|cat5|cat6|cat7|bnc|coaxial|patch|bobina)',
      ).hasMatch(strongText);
      if (!hasAccessoryName) return false;
    }

    if (_isPowerAccessoryQuery(rawQuery)) {
      final hasPowerName = RegExp(
        r'(pila|pilas|bateria|baterias|fuente|alimentador|alimentacion|transformador|adaptador|cargador|batt)',
      ).hasMatch(strongText);
      if (!hasPowerName) return false;
    }

    final accessoryTokens = tokens.where(_isAccessoryWord).toList();
    if (accessoryTokens.isEmpty) return false;

    final specificTokens = accessoryTokens.where((token) {
      final compact = _compactForSearch(token);
      return RegExp(r'(rj45|cat5|cat6|cat7|bnc|coaxial|utp|ftp|pila|bateria|baterias|fuente|alimentador)').hasMatch(compact);
    }).toList();

    for (final token in specificTokens) {
      final compact = _compactForSearch(token);
      if (compact == 'rj' || compact == '45') continue;
      if (!_textContainsTokenVariant(strongText, token)) {
        // “cable rj45” puede coincidir con “latiguillo cable red” aunque no
        // escriba RJ45 literalmente, pero no con una cámara o monitor.
        if (_isConnectivityAccessoryQuery(rawQuery) &&
            RegExp(r'(cable|latiguillo|conector|bobina)').hasMatch(strongText)) {
          continue;
        }
        return false;
      }
    }

    return strongText.contains(compactQuery) ||
        accessoryTokens.any((token) => _textContainsTokenVariant(strongText, token));
  }

  bool _textContainsTokenVariant(String compactText, String token) {
    return _variantsForToken(token).any(compactText.contains);
  }

  int _scoreSuggestionProduct(
      Product product,
      String rawQuery,
      List<String> tokens,
      Set<String> intents,
      bool skuLike,
      ) {
    final compactQuery = _compactForSearch(rawQuery);
    final compactSku = _compactForSearch(product.sku);
    final compactName = _compactForSearch(product.name);
    final compactBrand = _compactForSearch(product.brandName ?? '');
    final compactStrongText = _compactForSearch([
      product.name,
      product.sku,
      product.brandName ?? '',
      ...product.attributes.expand((attr) => [attr.name, ...attr.options]),
    ].join(' '));
    final compactText = _compactForSearch([
      product.name,
      product.sku,
      product.shortDescription,
      product.description,
      product.brandName ?? '',
      ...product.attributes.expand((attr) => [attr.name, ...attr.options]),
    ].join(' '));

    if (intents.contains('accessory') && !skuLike) {
      if (!_hasStrongAccessoryProductMatch(product, rawQuery, tokens)) {
        return 0;
      }
    }

    int score = 0;

    if (compactSku.isNotEmpty) {
      if (compactSku == compactQuery) score += 120;
      if (compactSku.startsWith(compactQuery)) score += 90;
      if (compactSku.contains(compactQuery)) score += 65;
    }

    if (compactName.startsWith(compactQuery)) score += 60;
    if (compactName.contains(compactQuery)) score += 45;
    if (compactBrand.isNotEmpty && compactBrand.contains(compactQuery)) {
      score += 30;
    }

    int matchedTokens = 0;
    for (final token in tokens) {
      final targetText = intents.contains('accessory') ? compactStrongText : compactText;
      if (_textContainsTokenVariant(targetText, token)) {
        matchedTokens++;
        score += intents.contains('accessory') && _isAccessoryWord(token) ? 22 : 14;
      }
    }

    if (tokens.length >= 2 && matchedTokens < tokens.length && !skuLike) {
      // En accesorios aceptamos coincidencia fuerte de familia aunque no estén
      // todas las palabras literales, por ejemplo "cable rj45" vs "latiguillo RJ45".
      if (!intents.contains('accessory') ||
          !_hasStrongAccessoryProductMatch(product, rawQuery, tokens)) {
        return 0;
      }
    }

    if (intents.contains('accessory') &&
        RegExp(r'(cable|latiguillo|conector|rj45|utp|ftp|cat5|cat6|cat7|bnc|coaxial|patch|pila|bateria|fuente|alimentador|transformador|adaptador)').hasMatch(compactStrongText)) {
      score += 35;
    }

    if (intents.contains('video') &&
        RegExp(r'(camara|camera|cctv|video|domo|dome|turret|bullet|nvr|xvr|dvr|ptz|anpr|lpr|mp)').hasMatch(compactText)) {
      score += 18;
    }

    if (intents.contains('software') &&
        RegExp(r'(software|licencia|hikcentral|dss|dmss|ivss)').hasMatch(compactText)) {
      score += 18;
    }

    if (product.isInstock) score += 3;

    return score;
  }

  List<String> _technicalCompletionsFor(String query, String categoryName) {
    final compact = _compactForSearch(query);
    final intents = _detectSearchIntents('$query $categoryName');
    final suggestions = <String>[];

    void addAll(List<String> values) {
      for (final value in values) {
        if (!suggestions.contains(value)) suggestions.add(value);
      }
    }

    if (intents.contains('accessory')) {
      final typed = query.trim();
      if (typed.length >= 3) {
        addAll([typed]);
      }

      if (_isConnectivityAccessoryQuery(query)) {
        final hasRj45 = compact.contains('rj45') || compact.contains('rj');
        final hasCat6 = compact.contains('cat6');
        final hasCable = compact.contains('cable');
        final hasLatiguillo = compact.contains('latiguillo');

        if (hasRj45 && hasCable) {
          addAll(['cable RJ45', 'latiguillo RJ45', 'conector RJ45']);
        } else if (hasRj45) {
          addAll(['conector RJ45', 'latiguillo RJ45', 'cable RJ45']);
        } else if (hasCat6) {
          addAll(['cable UTP Cat6', 'bobina Cat6', 'latiguillo Cat6']);
        } else if (hasLatiguillo) {
          addAll(['latiguillo RJ45', 'latiguillo Cat6', 'latiguillo cable red']);
        } else if (hasCable) {
          addAll(['cable de red', 'cable UTP Cat6', 'cable coaxial']);
        } else {
          addAll(['conector RJ45', 'latiguillo RJ45', 'cable UTP Cat6']);
        }
      } else if (_isPowerAccessoryQuery(query)) {
        if (compact.contains('pila') || compact.contains('bateria')) {
          addAll(['pila litio', 'batería', 'pila para detector']);
        } else if (compact.contains('fuente') || compact.contains('aliment')) {
          addAll(['fuente alimentación 12V', 'alimentador CCTV', 'transformador 12V']);
        } else {
          addAll(['pila litio', 'batería', 'fuente alimentación 12V']);
        }
      } else {
        addAll([
          'accesorios instalación',
          'complementos seguridad',
          'fuente alimentación',
          'conector RJ45',
          'cable de red',
        ]);
      }
    }

    if (intents.contains('software') || compact.contains('lic')) {
      if (compact.contains('dahua')) {
        addAll(['licencia Dahua', 'DSS Dahua', 'DMSS Dahua']);
      } else if (compact.contains('hik')) {
        addAll(['licencia Hikvision', 'HikCentral', 'HikCentral Professional']);
      } else {
        addAll([
          'licencia Dahua',
          'licencia Hikvision',
          'HikCentral',
          'DSS',
          'DMSS',
        ]);
      }
    }

    if (intents.contains('video') && !intents.contains('accessory')) {
      if (compact.contains('8') || compact.contains('8mp')) {
        addAll([
          'cámara IP 8MP',
          'cámara domo 8MP',
          'cámara bullet 8MP',
          'cámara Dahua 8MP',
          'cámara Hikvision 8MP',
        ]);
      } else if (compact.contains('dom')) {
        addAll([
          'cámara domo IP',
          'domo Dahua',
          'domo Hikvision',
          'domo WiFi',
          'domo 8MP',
        ]);
      } else if (compact.contains('bul') || compact.contains('tub')) {
        addAll([
          'cámara bullet IP',
          'cámara tubular Dahua',
          'cámara tubular Hikvision',
          'bullet 8MP',
        ]);
      } else if (compact.contains('nvr') || compact.contains('grab')) {
        addAll([
          'grabador NVR',
          'NVR Dahua',
          'NVR Hikvision',
          'grabador 16 canales',
        ]);
      } else if (compact.contains('anpr') || compact.contains('matri')) {
        addAll([
          'cámara ANPR',
          'cámara lectura matrículas',
          'ANPR Dahua',
          'ANPR Hikvision',
        ]);
      } else if (compact.contains('cam')) {
        addAll([
          'cámara IP',
          'cámara domo',
          'cámara bullet',
          'cámara WiFi',
          'cámara 8MP',
        ]);
      }
    }

    if (suggestions.isEmpty && query.trim().length >= 3) {
      suggestions.add(query.trim());
    }

    return suggestions.take(6).toList();
  }

  void _applySearchNow() {
    _hideSearchSuggestions();
    FocusScope.of(context).unfocus();
    _searchDebounce?.cancel();

    final cleanSearch = _searchController.text.trim();
    if (cleanSearch.length >= 3) {
      final queryIntents = _detectSearchIntents(cleanSearch);
      final categoryIntents = _detectSearchIntents(widget.categoryName);
      if (_hasClearExternalIntent(
        queryIntents: queryIntents,
        categoryIntents: categoryIntents,
        categoryName: widget.categoryName,
      )) {
        unawaited(_redirectSearchIfNeeded(cleanSearch, queryIntents));
        return;
      }
    }

    ref.read(productFilterProvider.notifier).setSearch(cleanSearch);
  }

  Future<void> _redirectSearchIfNeeded(
      String cleanSearch,
      Set<String> queryIntents,
      ) async {
    final target = await _resolveRedirectCategoryForQuery(cleanSearch, queryIntents);
    if (!mounted || target == null || target.id == widget.categoryId) {
      ref.read(productFilterProvider.notifier).setSearch(cleanSearch);
      return;
    }

    ref.read(productFilterProvider.notifier).reset();
    ref.read(productFilterProvider.notifier).setSearch(cleanSearch);
    _preserveFiltersForNextCategoryOpen = true;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProductosPorCategoriaScreen(
          categoryId: target.id,
          categoryName: target.name,
          onGoCart: widget.onGoCart,
          onGoQuotes: widget.onGoQuotes,
        ),
      ),
    );
  }

  void _clearSearch() {
    _hideSearchSuggestions();
    _searchDebounce?.cancel();
    FocusScope.of(context).unfocus();

    final previousFilters = ref.read(productFilterProvider);

    _searchController.clear();
    ref.read(productFilterProvider.notifier).clearSearch();

    if (previousFilters.search.trim().isEmpty) {
      _reloadCurrentCategory();
    }

    setState(() {});
  }

  void _resetFilters() {
    _hideSearchSuggestions();
    _searchDebounce?.cancel();
    FocusScope.of(context).unfocus();

    final previousFilters = ref.read(productFilterProvider);

    _searchController.clear();
    ref.read(productFilterProvider.notifier).reset();

    if (!previousFilters.hasActiveFilters) {
      _reloadCurrentCategory();
    }

    setState(() {});
  }

  Future<void> _refreshProducts() async {
    _isLoadingMore = false;

    final notifier = ref.read(
      productsPaginatedProvider(widget.categoryId).notifier,
    );

    notifier.clearCacheForCurrentCategory();
    await notifier.loadFirstPage(forceRefresh: true);
  }

  void _openFilters() {
    _hideSearchSuggestions();
    _searchDebounce?.cancel();
    FocusScope.of(context).unfocus();

    // Abrir filtros no debe convertir lo que se está escribiendo en una
    // búsqueda aplicada. Si el usuario quiere filtrar por el texto escrito,
    // debe confirmar la búsqueda o pulsar una sugerencia.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scaffoldKey.currentState?.openEndDrawer();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(productFilterProvider, (previous, next) {
      if (previous != next) {
        _onFiltersChanged(next);
      }
    });

    final productosState = ref.watch(
      productsPaginatedProvider(widget.categoryId),
    );
    final notifier = ref.watch(
      productsPaginatedProvider(widget.categoryId).notifier,
    );
    final filters = ref.watch(productFilterProvider);
    final hasActiveFilters = filters.hasActiveFilters;
    final totalItems = notifier.totalItems;
    final loadedItems = productosState.length;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF5F6F8),
      endDrawer: FiltroSelector(
        parentCategoryId: widget.categoryId,
        categoryName: widget.categoryName,
        productosEnPantalla: productosState,
      ),
      appBar: _CatalogCategoryAppBar(
        title: widget.categoryName,
        onBack: () => Navigator.of(context).pop(),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return ScaleTransition(
            scale: animation,
            child: FadeTransition(
              opacity: animation,
              child: child,
            ),
          );
        },
        child: _showScrollTopButton
            ? _ScrollToTopButton(
          key: const ValueKey('scroll_top_button'),
          onTap: _scrollToTop,
        )
            : const SizedBox.shrink(
          key: ValueKey('scroll_top_button_hidden'),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _refreshProducts,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: _CatalogControls(
                controller: _searchController,
                categoryName: widget.categoryName,
                filters: filters,
                totalItems: totalItems,
                loadedItems: loadedItems,
                isLoading: notifier.isLoading || !notifier.hasLoadedFirstPage,
                suggestions: _searchSuggestions,
                isLoadingSuggestions: _isLoadingSuggestions,
                onChanged: _onSearchChanged,
                onSubmitted: _applySearchNow,
                onClearSearch: _clearSearch,
                onOpenFilters: _openFilters,
                onSuggestionTap: _handleSuggestionTap,
              ),
            ),
            if (hasActiveFilters)
              SliverToBoxAdapter(
                child: _ActiveFiltersBar(
                  categoryName: widget.categoryName,
                  filters: filters,
                  onClearAll: _resetFilters,
                ),
              ),
            if (productosState.isEmpty &&
                (!notifier.hasLoadedFirstPage || notifier.isLoading))
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _InitialProductsLoadingState(),
              )
            else if (productosState.isEmpty && notifier.lastError != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _ProductsErrorState(
                  onRetry: _refreshProducts,
                ),
              )
            else if (productosState.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyProductsState(
                    onReset: _resetFilters,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  sliver: SliverList.separated(
                    itemCount: productosState.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      return ProductTile(
                        key: ValueKey(productosState[index].id),
                        p: productosState[index],
                        firebase: _firebase,
                        categoryName: widget.categoryName,
                        onGoCart: widget.onGoCart,
                        onGoQuotes: widget.onGoQuotes,
                      );
                    },
                  ),
                ),
            if (productosState.isNotEmpty && notifier.hasMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 6, 20, 24),
                  child: Center(
                    child: SizedBox(
                      height: 30,
                      width: 30,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              )
            else if (productosState.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 26),
                  child: Text(
                    totalItems > 0
                        ? 'Mostrando $loadedItems de $totalItems productos'
                        : 'Mostrando $loadedItems productos',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF8A8A8A),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScrollToTopButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ScrollToTopButton({
    super.key,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 2, bottom: 12),
      child: Material(
        color: AppColors.primary,
        shape: const CircleBorder(),
        elevation: 7,
        shadowColor: Colors.black.withValues(alpha: 0.28),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const SizedBox(
            width: 48,
            height: 48,
            child: Icon(
              Icons.keyboard_arrow_up_rounded,
              color: Colors.white,
              size: 31,
            ),
          ),
        ),
      ),
    );
  }
}

class _CatalogCategoryAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback onBack;

  const _CatalogCategoryAppBar({
    required this.title,
    required this.onBack,
  });

  @override
  Size get preferredSize => const Size.fromHeight(86);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(30),
            bottomRight: Radius.circular(30),
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 86,
            child: Row(
              children: [
                const SizedBox(width: 4),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: onBack,
                    tooltip: 'Volver',
                    splashRadius: 22,
                  ),
                ),
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      letterSpacing: 1.05,
                      color: Colors.white,
                      fontFamily: 'Oswald',
                      height: 1.05,
                    ),
                  ),
                ),
                const SizedBox(width: 52),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CatalogControls extends StatelessWidget {
  final TextEditingController controller;
  final String categoryName;
  final MundiFilters filters;
  final int totalItems;
  final int loadedItems;
  final bool isLoading;
  final List<_CatalogSearchSuggestion> suggestions;
  final bool isLoadingSuggestions;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;
  final VoidCallback onClearSearch;
  final VoidCallback onOpenFilters;
  final ValueChanged<_CatalogSearchSuggestion> onSuggestionTap;

  const _CatalogControls({
    required this.controller,
    required this.categoryName,
    required this.filters,
    required this.totalItems,
    required this.loadedItems,
    required this.isLoading,
    required this.suggestions,
    required this.isLoadingSuggestions,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClearSearch,
    required this.onOpenFilters,
    required this.onSuggestionTap,
  });

  @override
  Widget build(BuildContext context) {
    final String resultText = _resultText();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 14, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE7E7E7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          TextField(
            controller: controller,
            textInputAction: TextInputAction.search,
            onChanged: onChanged,
            onSubmitted: (_) => onSubmitted(),
            decoration: InputDecoration(
              hintText: 'Buscar en ${categoryName.toLowerCase()}',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: controller.text.trim().isNotEmpty
                  ? IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: onClearSearch,
              )
                  : null,
              filled: true,
              fillColor: const Color(0xFFF8F9FB),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE1E4EA)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE1E4EA)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: AppColors.primary,
                  width: 1.4,
                ),
              ),
            ),
          ),
          if (isLoadingSuggestions || suggestions.isNotEmpty) ...[
            const SizedBox(height: 10),
            _SearchSuggestionsPanel(
              suggestions: suggestions,
              isLoading: isLoadingSuggestions,
              onTap: onSuggestionTap,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  resultText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onOpenFilters,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: filters.hasActiveFilters
                        ? AppColors.primary
                        : const Color(0xFFF0F2F5),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: filters.hasActiveFilters
                          ? AppColors.primary
                          : const Color(0xFFD9DEE7),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.tune_rounded,
                        size: 17,
                        color: filters.hasActiveFilters
                            ? Colors.white
                            : AppColors.textPrimary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Filtros',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          color: filters.hasActiveFilters
                              ? Colors.white
                              : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _resultText() {
    if (isLoading && loadedItems == 0) {
      return 'Cargando productos...';
    }
    if (totalItems > 0) {
      return '$totalItems productos encontrados';
    }
    if (loadedItems > 0) {
      return '$loadedItems productos cargados';
    }
    return 'Sin resultados';
  }
}



enum _CatalogSearchSuggestionType { product, query, redirect, brand }

class _CatalogSearchSuggestion {
  final _CatalogSearchSuggestionType type;
  final String title;
  final String subtitle;
  final String value;
  final Product? product;
  final bool skuLike;
  final bool global;
  final int? targetCategoryId;
  final String? targetCategoryName;
  final String? brandName;
  final int? brandId;

  const _CatalogSearchSuggestion({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.value,
    this.product,
    this.skuLike = false,
    this.global = false,
    this.targetCategoryId,
    this.targetCategoryName,
    this.brandName,
    this.brandId,
  });

  factory _CatalogSearchSuggestion.product(
      Product product, {
        bool skuLike = false,
        bool global = false,
      }) {
    final sku = product.sku.trim();
    final brand = product.brandName?.trim();
    final subtitleParts = <String>[
      if (global) 'Encontrado en todo el catálogo',
      if (skuLike && sku.isNotEmpty) sku,
      if (brand != null && brand.isNotEmpty) brand,
      if (product.shortDescription.trim().isNotEmpty &&
          product.shortDescription.trim() != 'Sin descripción')
        product.shortDescription.trim(),
    ];

    return _CatalogSearchSuggestion(
      type: _CatalogSearchSuggestionType.product,
      title: product.name,
      subtitle: subtitleParts.take(2).join(' · '),
      value: sku.isNotEmpty ? sku : product.name,
      product: product,
      skuLike: skuLike,
      global: global,
    );
  }

  factory _CatalogSearchSuggestion.query({
    required String title,
    required String subtitle,
    String? value,
    int? targetCategoryId,
    String? targetCategoryName,
  }) {
    return _CatalogSearchSuggestion(
      type: _CatalogSearchSuggestionType.query,
      title: title,
      subtitle: subtitle,
      value: value ?? title,
      targetCategoryId: targetCategoryId,
      targetCategoryName: targetCategoryName,
    );
  }

  factory _CatalogSearchSuggestion.redirect({
    required String title,
    required String subtitle,
    required String value,
    required int targetCategoryId,
    required String targetCategoryName,
  }) {
    return _CatalogSearchSuggestion(
      type: _CatalogSearchSuggestionType.redirect,
      title: title,
      subtitle: subtitle,
      value: value,
      targetCategoryId: targetCategoryId,
      targetCategoryName: targetCategoryName,
    );
  }

  factory _CatalogSearchSuggestion.brand({
    required String brandName,
    required int brandId,
    required String categoryName,
  }) {
    return _CatalogSearchSuggestion(
      type: _CatalogSearchSuggestionType.brand,
      title: brandName.toUpperCase(),
      subtitle: 'Marca · Ver productos $brandName en $categoryName',
      value: brandName,
      brandName: brandName,
      brandId: brandId,
    );
  }

  String get uniqueKey {
    if (product != null) return 'product:${product!.id}';
    if (brandId != null) return 'brand:$brandId';
    if (targetCategoryId != null) return 'redirect:$targetCategoryId:${value.toLowerCase().trim()}';
    return 'query:${value.toLowerCase().trim()}';
  }
}

class _SearchRedirectTarget {
  final int id;
  final String name;

  const _SearchRedirectTarget({required this.id, required this.name});
}

class _ScoredProduct {
  final Product product;
  final int score;

  const _ScoredProduct({
    required this.product,
    required this.score,
  });
}

class _ScoredBrand {
  final int id;
  final String name;
  final int score;

  const _ScoredBrand({
    required this.id,
    required this.name,
    required this.score,
  });
}

class _SearchSuggestionsPanel extends StatelessWidget {
  final List<_CatalogSearchSuggestion> suggestions;
  final bool isLoading;
  final ValueChanged<_CatalogSearchSuggestion> onTap;

  const _SearchSuggestionsPanel({
    required this.suggestions,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1E4EA)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: isLoading && suggestions.isEmpty
          ? const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            ),
            SizedBox(width: 10),
            Text(
              'Buscando sugerencias...',
              style: TextStyle(
                fontSize: 12.5,
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      )
          : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (suggestions.any(
                (item) => item.type == _CatalogSearchSuggestionType.redirect,
          ))
            const _SuggestionSectionLabel('MEJOR APARTADO'),
          ...suggestions
              .where(
                (item) =>
            item.type == _CatalogSearchSuggestionType.redirect,
          )
              .map((item) => _SuggestionTile(
            suggestion: item,
            onTap: onTap,
          )),
          if (suggestions.any(
                (item) => item.type == _CatalogSearchSuggestionType.product,
          ))
            const _SuggestionSectionLabel('DESTACADOS'),
          ...suggestions
              .where(
                (item) =>
            item.type == _CatalogSearchSuggestionType.product,
          )
              .map((item) => _SuggestionTile(
            suggestion: item,
            onTap: onTap,
          )),
          if (suggestions.any(
                (item) => item.type == _CatalogSearchSuggestionType.brand,
          ))
            const _SuggestionSectionLabel('MARCAS RELACIONADAS'),
          ...suggestions
              .where(
                (item) =>
            item.type == _CatalogSearchSuggestionType.brand,
          )
              .map((item) => _SuggestionTile(
            suggestion: item,
            onTap: onTap,
          )),
          if (suggestions.any(
                (item) => item.type == _CatalogSearchSuggestionType.query,
          ))
            const _SuggestionSectionLabel('SUGERENCIAS'),
          ...suggestions
              .where(
                (item) =>
            item.type == _CatalogSearchSuggestionType.query,
          )
              .map((item) => _SuggestionTile(
            suggestion: item,
            onTap: onTap,
          )),
        ],
      ),
    );
  }
}

class _SuggestionSectionLabel extends StatelessWidget {
  final String text;

  const _SuggestionSectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.7,
          color: Color(0xFF6B7280),
        ),
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  final _CatalogSearchSuggestion suggestion;
  final ValueChanged<_CatalogSearchSuggestion> onTap;

  const _SuggestionTile({
    required this.suggestion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final product = suggestion.product;

    return InkWell(
      onTap: () => onTap(suggestion),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
        child: Row(
          children: [
            if (product != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(
                  imageUrl: product.imageUrl,
                  width: 42,
                  height: 42,
                  fit: BoxFit.contain,
                  cacheManager: ImageCacheService.cacheManager,
                  placeholder: (_, _) => Container(
                    color: const Color(0xFFF0F2F5),
                  ),
                  errorWidget: (_, _, _) => const Icon(
                    Icons.broken_image_outlined,
                    color: Color(0xFF9CA3AF),
                    size: 22,
                  ),
                ),
              )
            else
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  suggestion.type == _CatalogSearchSuggestionType.redirect
                      ? Icons.subdirectory_arrow_right_rounded
                      : suggestion.type == _CatalogSearchSuggestionType.brand
                      ? Icons.sell_outlined
                      : Icons.north_west_rounded,
                  size: 17,
                  color: AppColors.primary,
                ),
              ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    suggestion.title,
                    maxLines: product != null ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.2,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                      height: 1.16,
                    ),
                  ),
                  if (suggestion.subtitle.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      suggestion.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              product != null
                  ? Icons.open_in_new_rounded
                  : suggestion.type == _CatalogSearchSuggestionType.redirect
                  ? Icons.subdirectory_arrow_right_rounded
                  : suggestion.type == _CatalogSearchSuggestionType.brand
                  ? Icons.sell_outlined
                  : Icons.search_rounded,
              size: 18,
              color: const Color(0xFF9CA3AF),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveFiltersBar extends StatelessWidget {
  final String categoryName;
  final MundiFilters filters;
  final VoidCallback onClearAll;

  const _ActiveFiltersBar({
    required this.categoryName,
    required this.filters,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <String>[
      categoryName,
      if (filters.brand.trim().isNotEmpty) 'Marca: ${filters.brand.trim()}',
      if (filters.search.trim().isNotEmpty) 'Búsqueda: ${filters.search.trim()}',
      if (filters.hasOrder) _orderLabel(filters.orderBy),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7F7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF0D4D4)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.filter_alt_outlined,
            size: 18,
            color: AppColors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              chips.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onClearAll,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                'Quitar',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _orderLabel(String value) {
    switch (value) {
      case 'price_asc':
        return 'Precio bajo';
      case 'price_desc':
        return 'Precio alto';
      case 'date':
        return 'Más recientes';
      default:
        return '';
    }
  }
}

class _InitialProductsLoadingState extends StatelessWidget {
  const _InitialProductsLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 34,
        height: 34,
        child: CircularProgressIndicator(
          strokeWidth: 3,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _ProductsErrorState extends StatelessWidget {
  final Future<void> Function() onRetry;

  const _ProductsErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: Color(0xFFFFF1F1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                size: 44,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No se pudieron cargar los productos',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Oswald',
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Revisa la conexión o vuelve a intentarlo.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 22),
            ElevatedButton.icon(
              onPressed: () => unawaited(onRetry()),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyProductsState extends StatelessWidget {
  final VoidCallback onReset;

  const _EmptyProductsState({required this.onReset});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 112,
              height: 112,
              decoration: const BoxDecoration(
                color: Color(0xFFF8EAEA),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.search_off_rounded,
                size: 54,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'No hay productos con estos filtros',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Oswald',
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Prueba a limpiar la selección o cambiar la búsqueda aplicada.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Limpiar filtros'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProductTile extends ConsumerStatefulWidget {
  final Product p;
  final FirebaseService firebase;
  final String? categoryName;
  final VoidCallback? onGoCart;
  final VoidCallback? onGoQuotes;

  const ProductTile({
    super.key,
    required this.p,
    required this.firebase,
    this.categoryName,
    this.onGoCart,
    this.onGoQuotes,
  });

  @override
  ConsumerState<ProductTile> createState() => _ProductTileState();
}

class _ProductTileState extends ConsumerState<ProductTile> {
  int cantidad = 1;
  bool _isAddingToQuote = false;

  double _precioDouble(Product p) {
    return double.tryParse(p.price.replaceAll(',', '.').trim()) ?? 0;
  }

  String _formatearPrecioCompleto(double precio) {
    if (precio <= 0) return 'Bajo consulta';
    final parts = precio.toStringAsFixed(2).split('.');
    final enteros = parts[0];
    final decimales = parts.length > 1 ? parts[1] : '00';
    final buffer = StringBuffer();
    for (int i = 0; i < enteros.length; i++) {
      if (i > 0 && (enteros.length - i) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(enteros[i]);
    }
    return '${buffer.toString()},$decimales €';
  }

  bool get _tieneStock => widget.p.isInstock;
  bool get _puedeComprar => _tieneStock && cantidad > 0;

  void _goToQuotesKeepingTabs() {
    if (widget.onGoQuotes != null) {
      widget.onGoQuotes!();
      return;
    }
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Producto añadido al presupuesto'),
        backgroundColor: AppColors.primary,
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final precio = _precioDouble(widget.p);

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE7E7E7)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
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
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => ProductDetailScreen(
                        product: widget.p,
                        onGoCart: widget.onGoCart,
                        onGoQuotes: widget.onGoQuotes,
                        contextCategoryName: widget.categoryName,
                      ),
                    ),
                  );
                },
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Hero(
                      tag: 'prod_${widget.p.id}',
                      child: ProductImage(
                        p: widget.p,
                        firebase: widget.firebase,
                      ),
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
                                  widget.p.name,
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
                              _stockChip(),
                            ],
                          ),
                          if (widget.p.shortDescription.trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              widget.p.shortDescription,
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
                            _formatearPrecioCompleto(precio),
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
                  _quantitySelector(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: ElevatedButton.icon(
                        onPressed: _puedeComprar
                            ? () {
                          ref
                              .read(cartProvider.notifier)
                              .addProduct(widget.p, cantidad);
                          ScaffoldMessenger.of(context).clearSnackBars();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '$cantidad x ${widget.p.name} añadido al carrito',
                              ),
                              backgroundColor: AppColors.primary,
                              duration: const Duration(seconds: 1),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                            : null,
                        icon: Icon(
                          _tieneStock ? Icons.shopping_cart_outlined : Icons.block_rounded,
                          size: 17,
                          color: Colors.white,
                        ),
                        label: Text(
                          _tieneStock ? 'AÑADIR CARRITO' : 'SIN STOCK',
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
                          backgroundColor: _tieneStock ? AppColors.primary : Colors.grey.shade400,
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
                  onPressed: _isAddingToQuote ? null : () => _addToQuote(widget.p),
                  icon: _isAddingToQuote
                      ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                      : const Icon(Icons.description_outlined, size: 17),
                  label: Text(
                    _isAddingToQuote ? 'AÑADIENDO...' : 'AÑADIR AL PRESUPUESTO',
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
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.textPrimary,
                    disabledForegroundColor: Colors.grey.shade500,
                    side: const BorderSide(
                      color: Color(0xFFD9DEE7),
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
      ),
    );
  }

  Widget _quantitySelector() {
    return Opacity(
      opacity: _tieneStock ? 1.0 : 0.55,
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
            _qtyBtn(Icons.remove, _tieneStock, () {
              if (cantidad > 1) {
                setState(() => cantidad--);
              }
            }),
            SizedBox(
              width: 34,
              child: Text(
                '$cantidad',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: _tieneStock ? AppColors.textPrimary : Colors.grey,
                ),
              ),
            ),
            _qtyBtn(
              Icons.add,
              _tieneStock,
                  () => setState(() => cantidad++),
              isPrimary: _tieneStock,
            ),
          ],
        ),
      ),
    );
  }

  Widget _stockChip() {
    final Color bgColor = _tieneStock ? const Color(0xFFEAF7EE) : const Color(0xFFFDECEC);
    final Color textColor = _tieneStock ? const Color(0xFF218047) : const Color(0xFFC62828);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: textColor.withValues(alpha: 0.18)),
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
            _tieneStock ? 'En stock' : 'Sin stock',
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
      IconData icon,
      bool enabled,
      VoidCallback onTap, {
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
        // Crear nuevo presupuesto
        final nombre = result['nombre'] as String;
        final orderId = DateTime.now().millisecondsSinceEpoch.toString();
        final nombreFinal = nombre.isNotEmpty ? nombre : 'Presupuesto #$orderId';

        await notifier.crearPresupuesto(orderId: orderId, nombre: nombreFinal);
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
        // Añadir a presupuesto existente
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
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            action: SnackBarAction(
              label: 'VER',
              textColor: Colors.white,
              onPressed: _goToQuotesKeepingTabs,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error en _addToQuote: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAddingToQuote = false);
    }
  }
}

class ProductImage extends StatelessWidget {
  final Product p;
  final FirebaseService firebase;

  const ProductImage({
    super.key,
    required this.p,
    required this.firebase,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7E7E7)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: CachedNetworkImage(
          imageUrl: p.imageUrl,
          fit: BoxFit.contain,
          cacheManager: ImageCacheService.cacheManager,
          memCacheWidth: 192,
          memCacheHeight: 192,
          cacheKey: p.imageUrl,
          placeholder: (_, _) => Container(color: Colors.grey[100]),
          errorWidget: (_, _, _) => const Icon(
            Icons.broken_image,
            color: Colors.grey,
            size: 30,
          ),
          fadeOutDuration: const Duration(milliseconds: 150),
          fadeInDuration: const Duration(milliseconds: 150),
        ),
      ),
    );
  }
}
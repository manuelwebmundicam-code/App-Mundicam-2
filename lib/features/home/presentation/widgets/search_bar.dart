import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/features/catalog/data/models/category_model.dart';
import 'package:mundicam/features/catalog/data/models/producto.dart';
import 'package:mundicam/features/catalog/presentation/pages/busqueda_resultados_page.dart';
import 'package:mundicam/features/catalog/presentation/pages/producto_detalles_page.dart';
import 'package:mundicam/features/catalog/presentation/pages/productos_por_categoria.dart';
import 'package:mundicam/shared/theme/app_theme.dart';

class SearchBarWidget extends StatefulWidget {
  final VoidCallback? onGoCart;
  final VoidCallback? onGoQuotes;

  const SearchBarWidget({
    super.key,
    this.onGoCart,
    this.onGoQuotes,
  });

  @override
  State<SearchBarWidget> createState() => _SearchBarWidgetState();
}

class _SearchBarWidgetState extends State<SearchBarWidget> {
  final TextEditingController _controller = TextEditingController();
  Timer? _suggestionsDebounce;
  int _suggestionsToken = 0;
  bool _loadingSuggestions = false;
  List<CategoryModel> _categorySuggestions = const <CategoryModel>[];
  List<Product> _productSuggestions = const <Product>[];
  List<CategoryModel>? _allSuggestionCategoriesCache;
  DateTime? _allSuggestionCategoriesCachedAt;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (!mounted) return;
    setState(() {});
    _scheduleSuggestions(_controller.text);
  }

  @override
  void dispose() {
    _suggestionsDebounce?.cancel();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _buscar(String value) {
    final query = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (query.isEmpty) return;

    _hideSuggestions();
    FocusScope.of(context).unfocus();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BusquedaResultadosPage(
          query: query,
          onGoCart: widget.onGoCart,
          onGoQuotes: widget.onGoQuotes,
        ),
      ),
    );
  }

  void _scheduleSuggestions(String value) {
    _suggestionsDebounce?.cancel();

    final query = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (!_shouldShowSuggestionsForQuery(query)) {
      _suggestionsToken++;
      if (_categorySuggestions.isNotEmpty ||
          _productSuggestions.isNotEmpty ||
          _loadingSuggestions) {
        setState(() {
          _categorySuggestions = const <CategoryModel>[];
          _productSuggestions = const <Product>[];
          _loadingSuggestions = false;
        });
      }
      return;
    }

    setState(() {
      _loadingSuggestions = true;
      // Mantenemos las sugerencias anteriores unos milisegundos mientras entra la
      // nueva búsqueda para evitar parpadeos y pantallas vacías.
    });

    final delay = _looksLikeSku(query)
        ? const Duration(milliseconds: 170)
        : const Duration(milliseconds: 380);

    _suggestionsDebounce = Timer(delay, () async {
      final token = ++_suggestionsToken;
      if (!mounted) return;

      try {
        final api = ApiService();
        final products = await _fetchSuggestionProducts(api, query)
            .timeout(const Duration(seconds: 4), onTimeout: () => const <Product>[])
            .catchError((_) => const <Product>[]);

        if (!mounted || token != _suggestionsToken) return;

        setState(() {
          // Senior rule: el panel predictivo no carga categorías. Las categorías
          // eran ruido, ralentizaban la búsqueda y no ayudan cuando el usuario
          // quiere ver productos con imagen. Los filtros/categorías se mantienen
          // en las pantallas de catálogo, no aquí.
          _productSuggestions = products.take(_looksLikeSku(query) ? 4 : 7).toList();
          _categorySuggestions = const <CategoryModel>[];
          _loadingSuggestions = false;
        });
      } catch (_) {
        if (!mounted || token != _suggestionsToken) return;
        setState(() {
          _categorySuggestions = const <CategoryModel>[];
          _productSuggestions = const <Product>[];
          _loadingSuggestions = false;
        });
      }
    });
  }

  bool _shouldShowSuggestionsForQuery(String query) {
    final clean = query.trim();
    if (clean.isEmpty) return false;
    if (_looksLikeSku(clean)) return clean.length >= 2;
    return clean.length >= 3;
  }

  Future<List<Product>> _fetchSuggestionProducts(ApiService api, String query) async {
    final cleanQuery = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (!_shouldShowSuggestionsForQuery(cleanQuery)) {
      return const <Product>[];
    }

    final limit = _looksLikeSku(cleanQuery) ? 8 : 10;

    try {
      final direct = await api.buscarProductosPredictivo(
        cleanQuery,
        limit: limit,
      );
      final ranked = _rankAndFilterProducts(direct, cleanQuery);
      if (ranked.isNotEmpty || _looksLikeSku(cleanQuery)) {
        return ranked;
      }

      // Fallback ligero para búsquedas compuestas que algunos endpoints antiguos
      // no resuelven bien, por ejemplo "dahua 6mp" o "turret dahua".
      final fallback = _bestFallbackProductQuery(cleanQuery);
      if (fallback == null || fallback.toLowerCase() == cleanQuery.toLowerCase()) {
        return const <Product>[];
      }

      final fallbackProducts = await api.buscarProductosPredictivo(
        fallback,
        limit: limit,
      );
      final fallbackRanked = _rankAndFilterProducts(fallbackProducts, cleanQuery);
      if (fallbackRanked.isNotEmpty) return fallbackRanked;
      return const <Product>[];
    } catch (_) {
      return const <Product>[];
    }
  }

  Future<List<CategoryModel>> _fetchSuggestionCategories(
    ApiService api,
    String query,
  ) async {
    final cleanQuery = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (!_shouldShowSuggestionsForQuery(cleanQuery)) return const <CategoryModel>[];

    final now = DateTime.now();
    final cacheStillValid = _allSuggestionCategoriesCache != null &&
        _allSuggestionCategoriesCachedAt != null &&
        now.difference(_allSuggestionCategoriesCachedAt!).inMinutes < 10;

    final allCategories = cacheStillValid
        ? _allSuggestionCategoriesCache!
        : await api.getCategorias(hideEmpty: true, parentOnly: false);

    if (!cacheStillValid) {
      _allSuggestionCategoriesCache = allCategories;
      _allSuggestionCategoriesCachedAt = now;
    }

    final scored = allCategories
        .where((category) => category.id > 0 && category.name.trim().isNotEmpty)
        .map((category) => _ScoredSuggestionCategory(
              category: category,
              score: _categorySuggestionScore(category, cleanQuery),
            ))
        .where((item) => item.score > 0)
        .toList()
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        final byCount = b.category.count.compareTo(a.category.count);
        if (byCount != 0) return byCount;
        return a.category.name.compareTo(b.category.name);
      });

    return scored.map((item) => item.category).take(6).toList();
  }

  String? _bestFallbackProductQuery(String query) {
    final compactQuery = _compact(query);
    final tokens = _tokens(query)
        .where((token) => !_isWeakSearchToken(token))
        .toList();

    // Senior rule: para búsquedas con intención técnica no caemos al nombre de
    // marca si eso puede sacar productos irrelevantes. Ejemplo: "camara ajax"
    // no debe acabar buscando solo "ajax" y mostrando kits de alarma.
    final technicalToken = tokens.firstWhere(
      (token) => RegExp(r'\d').hasMatch(token),
      orElse: () => '',
    );
    if (technicalToken.isNotEmpty) return technicalToken;

    if (compactQuery.contains('nvr')) return 'nvr';
    if (compactQuery.contains('grab')) return 'grabador';
    if (compactQuery.contains('turret') || compactQuery.contains('turet')) return 'turret';
    if (compactQuery.contains('dom')) return 'domo';
    if (compactQuery.contains('bullet') || compactQuery.contains('tubular')) return 'bullet';
    if (_queryHasCameraIntent(query)) return 'camara';

    if (tokens.isEmpty) return null;
    final preferred = tokens.firstWhere(
      (token) => RegExp(r'[a-z]').hasMatch(token) && token.length >= 4,
      orElse: () => tokens.first,
    );
    return preferred;
  }

  bool _isWeakSearchToken(String token) {
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
    return token.length < 3 || weak.contains(token);
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

  List<Product> _rankAndFilterProducts(Iterable<Product> products, String query) {
    final skuLike = _looksLikeSku(query);
    final scored = products
        .where((product) => product.id > 0)
        .map((product) => _ScoredSuggestionProduct(
      product: product,
      score: _productSuggestionScore(product, query),
    ))
        .where((item) => item.score > 0)
        .toList();

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.product.name.compareTo(b.product.name);
    });

    return scored
        .map((item) => item.product)
        .take(skuLike ? 6 : 8)
        .toList();
  }

  List<String> _suggestionSearchTerms(String query) {
    final clean = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    final compact = _compact(clean);
    final terms = <String>[];

    void add(String value) {
      final v = value.trim();
      if (v.length < 2) return;
      if (!terms.map((e) => e.toLowerCase()).contains(v.toLowerCase())) {
        terms.add(v);
      }
    }

    add(clean);

    if (compact.contains('dom')) {
      add('domo');
      add('cámara domo');
      add('domo IP');
      add('domo Dahua');
      add('domo Hikvision');
    }
    if (compact.contains('turret') || compact.contains('turet')) {
      add('turret');
      add('cámara turret');
      add('turret IP');
    }
    if (compact.contains('bullet') || compact.contains('tubular')) {
      add('bullet');
      add('cámara bullet');
      add('cámara tubular');
    }
    if (compact.contains('nvr') || compact.contains('grab')) {
      add('NVR');
      add('grabador');
    }

    return terms;
  }

  int _productSuggestionScore(Product product, String query) {
    final q = _compact(query);
    if (q.length < 2) return 0;

    final name = _compact(product.name);
    final sku = _compact(product.sku);
    final brand = _compact(product.brandName ?? '');
    final description = _compact(product.shortDescription);
    final categories = _compact(product.categoryNames.join(' '));
    final attributes = _compact(product.attributes.map((a) => '${a.name} ${a.options.join(' ')}').join(' '));
    final fullText = '$name $sku $brand $description $categories $attributes';

    // V8 senior precision: cuando el usuario pide cámaras, no basta con que el
    // texto largo mencione cámaras en una descripción. Debe ser un producto de
    // cámara por nombre, SKU, categoría o atributo. Esto evita que "camaras ajax"
    // enseñe kits de alarma, hubs o detectores solo porque sean marca AJAX.
    if (_queryHasCameraIntent(query) &&
        !_isPrimaryCameraProduct(
          name: name,
          sku: sku,
          categories: categories,
          attributes: attributes,
        )) {
      return 0;
    }

    if (_looksLikeSku(query)) {
      if (sku.isEmpty) return 0;
      if (sku == q) return 2400;
      if (sku.startsWith(q)) return 1900;
      if (sku.contains(q)) return 1500;
      return 0;
    }

    // Senior rule: las sugerencias generales deben ser precisas. No mostramos
    // productos que solo coinciden con una marca si falta la intención principal
    // de la búsqueda. Ejemplo: "camara ajax" no debe mostrar kits de alarma AJAX.
    if (!_productMatchesStrictQuery(fullText, query)) return 0;

    var score = 0;
    if (sku.isNotEmpty && sku == q) score += 1400;
    if (sku.isNotEmpty && sku.contains(q)) score += 900;
    if (name == q) score += 800;
    if (name.startsWith(q)) score += 620;
    if (name.contains(q)) score += 520;
    if (brand == q) score += 520;
    if (brand.contains(q)) score += 420;
    if (categories.contains(q)) score += 260;
    if (attributes.contains(q)) score += 240;
    if (description.contains(q)) score += 120;

    final tokens = _tokens(query).where((token) => !_isWeakSearchToken(token)).toList();
    var tokenHits = 0;
    for (final token in tokens) {
      if (sku.contains(token)) {
        score += 230;
        tokenHits++;
      }
      if (name.contains(token)) {
        score += 180;
        tokenHits++;
      }
      if (brand.contains(token)) {
        score += 150;
        tokenHits++;
      }
      if (categories.contains(token)) {
        score += 110;
        tokenHits++;
      }
      if (attributes.contains(token)) {
        score += 100;
        tokenHits++;
      }
      if (description.contains(token)) {
        score += 45;
        tokenHits++;
      }
    }

    if (tokens.length >= 2 && tokenHits >= tokens.length) score += 260;

    if (q.contains('dom') &&
        (name.contains('domo') || description.contains('domo') || fullText.contains('dome'))) {
      score += 320;
    }
    if ((q.contains('turret') || q.contains('turet')) && fullText.contains('turret')) {
      score += 320;
    }
    if ((q.contains('bullet') || q.contains('tubular')) &&
        (fullText.contains('bullet') || fullText.contains('tubular'))) {
      score += 320;
    }
    if (q.contains('nvr') && fullText.contains('nvr')) score += 280;
    if (q.contains('6mp') && fullText.contains('6mp')) score += 220;
    if (q.contains('4k') && fullText.contains('4k')) score += 220;

    if (product.imageUrl.trim().isNotEmpty) score += 12;
    if (product.isInstock) score += 8;

    return score;
  }

  bool _productMatchesStrictQuery(String fullText, String query) {
    final text = fullText;
    final tokens = _strictSearchTokens(query);
    if (tokens.isEmpty) return true;

    for (final token in tokens) {
      if (token == 'camara' || token == 'camaras' || token == 'camera' || token == 'cameras') {
        if (!_textHasCameraConcept(text)) return false;
        continue;
      }
      if (token == 'ip') {
        if (!text.contains('ip') && !text.contains('ipc')) return false;
        continue;
      }
      if (!text.contains(token)) return false;
    }

    if (_queryHasCameraIntent(query) && !_textHasCameraConcept(text)) return false;
    if (_queryHasNvrIntent(query) && !_textHasNvrConcept(text)) return false;
    if (_queryHasTurretIntent(query) && !text.contains('turret')) return false;
    if (_queryHasDomoIntent(query) && !(text.contains('domo') || text.contains('dome') || text.contains('minidomo'))) return false;
    if (_queryHasBulletIntent(query) && !(text.contains('bullet') || text.contains('tubular'))) return false;

    return true;
  }

  List<String> _strictSearchTokens(String query) {
    const stop = <String>{
      'de', 'del', 'la', 'el', 'los', 'las', 'una', 'uno', 'para', 'con',
      'por', 'en', 'y', 'o', 'the', 'a', 'an',
    };
    return query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map(_compact)
        .where((token) => token.length >= 2 && !stop.contains(token))
        .toList();
  }

  bool _queryHasCameraIntent(String query) {
    final q = _compact(query);
    return q.contains('camara') || q.contains('camera');
  }

  bool _queryHasNvrIntent(String query) {
    final q = _compact(query);
    return q.contains('nvr') || q.contains('grabador') || q.contains('videograbador');
  }

  bool _queryHasTurretIntent(String query) {
    final q = _compact(query);
    return q.contains('turret') || q.contains('turet');
  }

  bool _queryHasDomoIntent(String query) {
    final q = _compact(query);
    return q.contains('domo') || q.contains('minidomo') || q.contains('dome');
  }

  bool _queryHasBulletIntent(String query) {
    final q = _compact(query);
    return q.contains('bullet') || q.contains('tubular');
  }

  bool _textHasCameraConcept(String text) {
    return text.contains('camara') ||
        text.contains('camaras') ||
        text.contains('camera') ||
        text.contains('ipc') ||
        text.contains('hac') ||
        text.contains('hdw') ||
        text.contains('hfw') ||
        text.contains('domo') ||
        text.contains('minidomo') ||
        text.contains('dome') ||
        text.contains('turret') ||
        text.contains('bullet') ||
        text.contains('tubular');
  }

  bool _isPrimaryCameraProduct({
    required String name,
    required String sku,
    required String categories,
    required String attributes,
  }) {
    final primaryText = '$name $sku $categories $attributes';

    final strongCameraSku = sku.startsWith('ipc') ||
        sku.startsWith('hac') ||
        sku.contains('hdw') ||
        sku.contains('hfw');
    final strongCameraName = name.contains('camara') ||
        name.contains('camaras') ||
        name.contains('camera') ||
        name.contains('motioncam') ||
        name.contains('minidomo') ||
        name.contains('domo') ||
        name.contains('turret') ||
        name.contains('bullet') ||
        name.contains('tubular');
    final hasStrongCameraSignal = strongCameraSku ||
        strongCameraName ||
        categories.contains('camara') ||
        categories.contains('camaras') ||
        categories.contains('videoip') ||
        categories.contains('cctv') ||
        categories.contains('turret') ||
        categories.contains('domo') ||
        categories.contains('bullet') ||
        attributes.contains('lente') ||
        attributes.contains('resolucion');

    if (!hasStrongCameraSignal) return false;

    final accessoryOnly = name.contains('junctionbox') ||
        name.contains('junction box') ||
        name.contains('caja de conexiones') ||
        name.contains('caja conexiones') ||
        name.contains('caja para') ||
        name.contains('soporte') ||
        name.contains('base') ||
        name.contains('bracket') ||
        name.contains('adaptador') ||
        name.contains('montaje') ||
        name.contains('carcasa');
    if (accessoryOnly && !strongCameraSku && !name.contains('motioncam')) return false;

    final looksLikeAlarmAccessory =
        primaryText.contains('kitalarma') ||
        primaryText.contains('kitdealarma') ||
        primaryText.contains('alarmas') ||
        primaryText.contains('alarma') ||
        primaryText.contains('hub') ||
        primaryText.contains('central') ||
        primaryText.contains('detector') ||
        primaryText.contains('sensor') ||
        primaryText.contains('sirena') ||
        primaryText.contains('teclado') ||
        primaryText.contains('mando') ||
        primaryText.contains('contacto') ||
        primaryText.contains('repetidor');

    final explicitCameraInNameOrCategory =
        name.contains('camara') ||
        name.contains('camaras') ||
        name.contains('camera') ||
        name.contains('domo') ||
        name.contains('turret') ||
        name.contains('bullet') ||
        categories.contains('camara') ||
        categories.contains('camaras') ||
        categories.contains('turret') ||
        categories.contains('domo') ||
        categories.contains('bullet');

    // Un kit/alarma puede mencionar cámaras en el nombre, pero para búsquedas
    // tipo "camaras ajax" no debe aparecer salvo que sea una cámara real por SKU
    // o categoría inequívoca de cámaras. Preferimos no enseñar nada antes que
    // mezclar kits de alarma en una búsqueda de cámaras.
    if (looksLikeAlarmAccessory) {
      final cameraSku = sku.startsWith('ipc') || sku.startsWith('hac');
      final cameraCategory = categories.contains('camarasip') ||
          categories.contains('camaraip') ||
          categories.contains('camarasturret') ||
          categories.contains('camarasbullet') ||
          categories.contains('camarasdomo') ||
          categories.contains('cctvhd');
      if (!cameraSku && !cameraCategory) return false;
    }

    return true;
  }

  bool _textHasNvrConcept(String text) {
    return text.contains('nvr') ||
        text.contains('grabador') ||
        text.contains('videograbador');
  }

  bool _looksLikeSku(String value) {
    final raw = value.trim();
    if (raw.length < 4) return false;

    // Senior rule: si el usuario escribe una frase con espacios, NO es SKU.
    // Ejemplos de búsqueda general: "dahua 6mp", "camara ajax",
    // "nvr dahua", "turret 2.8mm". Antes esto caía por SKU por tener
    // letras+números y dejaba el panel vacío.
    if (RegExp(r'\s').hasMatch(raw)) return false;

    final upper = raw.toUpperCase();
    final compact = upper.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (compact.length < 5) return false;
    if (!RegExp(r'[A-Z]').hasMatch(compact) || !RegExp(r'\d').hasMatch(compact)) {
      return false;
    }

    // Referencias reales MundiCam suelen venir con guiones o prefijos claros.
    if (raw.contains('-') || raw.contains('_')) return true;

    const knownPrefixes = <String>[
      'IPC', 'HAC', 'NVR', 'XVR', 'DHI', 'DH', 'MC', 'PFA', 'PFM', 'PFH',
      'HIK', 'DS', 'AJ', 'AX', 'NVS', 'HDBW', 'HDW', 'TIOC', 'KIT',
    ];
    return knownPrefixes.any(compact.startsWith);
  }

  bool _isRelevantCategory(CategoryModel category, String query) {
    final q = _compact(query);
    final name = _compact(category.name);
    if (q.length < 3 || name.isEmpty) return false;
    return name.contains(q) || _tokens(query).every(name.contains);
  }

  List<String> _tokens(String value) {
    return value
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map(_compact)
        .where((token) => token.length >= 3)
        .toList();
  }

  String _compact(String value) {
    return value
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('ä', 'a')
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ì', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ò', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ù', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  void _hideSuggestions() {
    _suggestionsDebounce?.cancel();
    _suggestionsToken++;
    if (_categorySuggestions.isEmpty &&
        _productSuggestions.isEmpty &&
        !_loadingSuggestions) {
      return;
    }
    setState(() {
      _categorySuggestions = const <CategoryModel>[];
      _productSuggestions = const <Product>[];
      _loadingSuggestions = false;
    });
  }

  void _openCategory(CategoryModel category, {String? initialSearch}) {
    _hideSuggestions();
    FocusScope.of(context).unfocus();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductosPorCategoriaScreen(
          categoryId: category.id,
          categoryName: category.name,
          initialSearch: initialSearch,
          onGoCart: widget.onGoCart,
          onGoQuotes: widget.onGoQuotes,
        ),
      ),
    );
  }

  void _openSmartCategoryOrSearch() {
    final query = _controller.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (query.isEmpty) return;

    final smart = _bestCategoryForQuery(query);
    if (smart != null) {
      _openCategory(smart, initialSearch: query);
      return;
    }

    _buscar(query);
  }

  CategoryModel? _bestCategoryForQuery(String query) {
    if (_categorySuggestions.isEmpty) return null;

    final scored = _categorySuggestions
        .map((category) => _ScoredSuggestionCategory(
      category: category,
      score: _categorySuggestionScore(category, query),
    ))
        .where((item) => item.score > 0)
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return scored.isNotEmpty ? scored.first.category : _categorySuggestions.first;
  }

  int _categorySuggestionScore(CategoryModel category, String query) {
    final compactQuery = _compact(query);
    final name = _compact(category.name);
    final slug = _compact(category.slug);
    final text = '$name $slug';
    var score = 0;

    if (name == compactQuery || slug == compactQuery) score += 700;
    if (name.startsWith(compactQuery) || slug.startsWith(compactQuery)) score += 520;
    if (name.contains(compactQuery) || slug.contains(compactQuery)) score += 420;

    final tokens = _tokens(query).where((token) => !_isWeakSearchToken(token)).toList();
    var hits = 0;
    for (final token in tokens) {
      if (text.contains(token)) {
        score += 180;
        hits++;
      }
    }
    if (tokens.length >= 2 && hits >= tokens.length) score += 260;

    if (compactQuery.contains('camara') && name.contains('camara')) score += 180;
    if (compactQuery.contains('ip') && name.contains('ip')) score += 170;
    if (compactQuery.contains('dom') && (name.contains('domo') || name.contains('minidomo'))) score += 230;
    if ((compactQuery.contains('turret') || compactQuery.contains('turet')) && name.contains('turret')) score += 260;
    if ((compactQuery.contains('bullet') || compactQuery.contains('tubular')) &&
        (name.contains('bullet') || name.contains('tubular'))) score += 240;
    if ((compactQuery.contains('nvr') || compactQuery.contains('grab')) &&
        (name.contains('grabador') || name.contains('nvr'))) score += 240;

    if (category.count > 0) score += category.count.clamp(0, 80).toInt();
    return score;
  }

  void _openProduct(Product product) {
    // No vaciamos las sugerencias al abrir la ficha.
    // Así, al volver atrás, el usuario ve el mismo resultado con imagen y SKU,
    // en lugar de quedarse solo con la tarjeta genérica de "Buscar en catálogo".
    FocusScope.of(context).unfocus();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductDetailScreen(
          product: product,
          contextCategoryName: 'Catálogo MundiCam',
          onGoCart: widget.onGoCart,
          onGoQuotes: widget.onGoQuotes,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.trim().isNotEmpty;
    final query = _controller.text.trim();
    final showSuggestions = _shouldShowSuggestionsForQuery(query);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Container(
            height: 50,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(17),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.16),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              keyboardType: TextInputType.text,
              onSubmitted: _buscar,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontFamily: 'Oswald',
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: 'Buscar por producto, marca, tecnología...',
                hintStyle: TextStyle(
                  color: Colors.white.withOpacity(0.78),
                  fontFamily: 'Oswald',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                prefixIcon: IconButton(
                  icon: const Icon(
                    Icons.search_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  onPressed: () => _buscar(_controller.text),
                ),
                suffixIcon: hasText
                    ? IconButton(
                  icon: const Icon(
                    Icons.clear_rounded,
                    color: Colors.white70,
                    size: 20,
                  ),
                  onPressed: () {
                    _controller.clear();
                    _hideSuggestions();
                  },
                )
                    : IconButton(
                  icon: const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  onPressed: () => _buscar(_controller.text),
                ),
                filled: true,
                fillColor: Colors.transparent,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(17),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 4,
                ),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: showSuggestions
                ? Padding(
              key: const ValueKey('home_search_suggestions'),
              padding: const EdgeInsets.only(top: 8),
              child: _HomeSearchSuggestionsPanel(
                query: query,
                loading: _loadingSuggestions,
                products: _productSuggestions,
                isSkuQuery: _looksLikeSku(query),
                onSearchAll: () => _buscar(_controller.text),
                onProductTap: _openProduct,
              ),
            )
                : const SizedBox.shrink(
              key: ValueKey('home_search_suggestions_empty'),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeSearchSuggestionsPanel extends StatelessWidget {
  final String query;
  final bool loading;
  final List<Product> products;
  final bool isSkuQuery;
  final VoidCallback onSearchAll;
  final ValueChanged<Product> onProductTap;

  const _HomeSearchSuggestionsPanel({
    required this.query,
    required this.loading,
    required this.products,
    required this.isSkuQuery,
    required this.onSearchAll,
    required this.onProductTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E7EC)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isSkuQuery)
                  InkWell(
                    onTap: onSearchAll,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: const Icon(
                              Icons.search_rounded,
                              color: AppColors.primary,
                              size: 19,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Ver todos los productos de “$query”',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Oswald',
                                fontSize: 13.5,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF111827),
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.keyboard_return_rounded,
                            size: 17,
                            color: Color(0xFF9CA3AF),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: AppColors.primary,
                      backgroundColor: Color(0xFFF1F3F6),
                    ),
                  ),
                if (products.isNotEmpty) ...[
                  _SuggestionsTitle(isSkuQuery ? 'PRODUCTO' : 'PRODUCTOS RELACIONADOS'),
                  for (final product in products.take(isSkuQuery ? 1 : 6))
                    _ProductSuggestionTile(
                      product: product,
                      query: query,
                      onTap: () => onProductTap(product),
                    ),
                ],
                if (!loading && products.isEmpty && isSkuQuery)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: Text(
                      'No se ha encontrado ese SKU. Revisa la referencia.',
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SuggestionsTitle extends StatelessWidget {
  final String text;

  const _SuggestionsTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF6B7280),
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

class _CategorySuggestionTile extends StatelessWidget {
  final CategoryModel category;
  final VoidCallback onTap;

  const _CategorySuggestionTile({
    required this.category,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
        child: Row(
          children: [
            const Icon(
              Icons.folder_open_rounded,
              color: AppColors.primary,
              size: 17,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                category.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF111827),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Icon(
              Icons.north_west_rounded,
              color: Color(0xFF9CA3AF),
              size: 15,
            ),
          ],
        ),
      ),
    );
  }
}


class _ScoredSuggestionProduct {
  final Product product;
  final int score;

  const _ScoredSuggestionProduct({
    required this.product,
    required this.score,
  });
}

class _ScoredSuggestionCategory {
  final CategoryModel category;
  final int score;

  const _ScoredSuggestionCategory({
    required this.category,
    required this.score,
  });
}

class _ProductSuggestionTile extends StatelessWidget {
  final Product product;
  final String query;
  final VoidCallback onTap;

  const _ProductSuggestionTile({
    required this.product,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = product.sku.trim().isNotEmpty
        ? 'SKU: ${product.sku}'
        : _cleanSnippet(product.shortDescription);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: CachedNetworkImage(
                imageUrl: product.imageUrl,
                width: 38,
                height: 38,
                fit: BoxFit.cover,
                fadeInDuration: Duration.zero,
                memCacheWidth: 96,
                memCacheHeight: 96,
                placeholder: (_, _) => Container(
                  width: 38,
                  height: 38,
                  color: const Color(0xFFF1F3F6),
                ),
                errorWidget: (_, _, _) => Container(
                  width: 38,
                  height: 38,
                  color: const Color(0xFFF1F3F6),
                  child: const Icon(
                    Icons.inventory_2_outlined,
                    color: Color(0xFF9CA3AF),
                    size: 17,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HighlightedSuggestionText(
                    text: product.name,
                    query: query,
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _cleanSnippet(String value) {
    return value
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class _HighlightedSuggestionText extends StatelessWidget {
  final String text;
  final String query;

  const _HighlightedSuggestionText({
    required this.text,
    required this.query,
  });

  @override
  Widget build(BuildContext context) {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      return _plain(text);
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = cleanQuery.toLowerCase();
    final index = lowerText.indexOf(lowerQuery);
    if (index < 0) {
      return _plain(text);
    }

    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: const TextStyle(
          fontSize: 13,
          color: Color(0xFF111827),
          fontWeight: FontWeight.w800,
          height: 1.15,
        ),
        children: [
          TextSpan(text: text.substring(0, index)),
          TextSpan(
            text: text.substring(index, index + cleanQuery.length),
            style: const TextStyle(color: AppColors.primary),
          ),
          TextSpan(text: text.substring(index + cleanQuery.length)),
        ],
      ),
    );
  }

  Widget _plain(String value) {
    return Text(
      value,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 13,
        color: Color(0xFF111827),
        fontWeight: FontWeight.w800,
        height: 1.15,
      ),
    );
  }
}

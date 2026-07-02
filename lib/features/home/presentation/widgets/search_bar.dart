import 'dart:async';

import 'package:flutter/material.dart';

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
    if (query.length < 2 || !_looksLikeSku(query)) {
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

    // Solo mostramos sugerencias predictivas cuando el usuario escribe un SKU.
    setState(() {
      _loadingSuggestions = true;
      _categorySuggestions = const <CategoryModel>[];
      _productSuggestions = const <Product>[];
    });

    _suggestionsDebounce = Timer(const Duration(milliseconds: 180), () async {
      final token = ++_suggestionsToken;
      if (!mounted) return;

      try {
        final api = ApiService();
        final results = await Future.wait<dynamic>([
          api.getCategorias(hideEmpty: true).timeout(const Duration(seconds: 5)),
          _fetchSuggestionProducts(api, query).timeout(const Duration(seconds: 8)),
        ]);

        if (!mounted || token != _suggestionsToken) return;

        final categories = (results[0] as List<CategoryModel>)
            .where((category) => _isRelevantCategory(category, query))
            .take(3)
            .toList();
        final products = (results[1] as List<Product>).take(5).toList();

        setState(() {
          _categorySuggestions = categories;
          _productSuggestions = products;
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

  Future<List<Product>> _fetchSuggestionProducts(ApiService api, String query) async {
    final cleanQuery = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleanQuery.length < 2) return const <Product>[];

    try {
      final direct = await api.buscarProductosPredictivo(
        cleanQuery,
        limit: _looksLikeSku(cleanQuery) ? 12 : 12,
      );
      final filteredDirect = _rankAndFilterProducts(direct, cleanQuery);
      if (filteredDirect.isNotEmpty || _looksLikeSku(cleanQuery)) {
        return filteredDirect;
      }
    } catch (_) {
      // Continuamos con términos ampliados.
    }

    final byId = <int, Product>{};
    for (final term in _suggestionSearchTerms(cleanQuery).take(5)) {
      try {
        final products = await api.buscarProductosPredictivo(term, limit: 8).timeout(
          const Duration(seconds: 6),
        );
        for (final product in products) {
          if (product.id <= 0) continue;
          byId[product.id] = product;
        }
        if (byId.length >= 12) break;
      } catch (_) {
        // Las sugerencias son apoyo visual. La búsqueda al pulsar sigue funcionando.
      }
    }

    return _rankAndFilterProducts(byId.values, cleanQuery);
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
    final fullText = '$name $sku $brand $description';

    if (_looksLikeSku(query)) {
      if (sku.isEmpty) return 0;
      if (sku == q) return 2000;
      if (sku.startsWith(q)) return 1700;
      if (sku.contains(q)) return 1400;
      // Si el usuario escribe un SKU, no mostramos productos por nombre,
      // descripción o coincidencias indirectas. Evita resultados tipo cables,
      // kits o switches que no corresponden al código escrito.
      return 0;
    }

    var score = 0;
    if (sku.isNotEmpty && sku == q) score += 1000;
    if (sku.isNotEmpty && sku.contains(q)) score += 700;
    if (name == q) score += 500;
    if (name.startsWith(q)) score += 420;
    if (name.contains(q)) score += 360;
    if (brand.contains(q)) score += 260;
    if (description.contains(q)) score += 80;

    for (final token in _tokens(query)) {
      if (token.length < 2) continue;
      if (sku.contains(token)) score += 150;
      if (name.contains(token)) score += 120;
      if (brand.contains(token)) score += 90;
      if (description.contains(token)) score += 35;
    }

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
    if (product.imageUrl.trim().isNotEmpty) score += 12;
    if (product.isInstock) score += 8;

    return score;
  }

  bool _looksLikeSku(String value) {
    final clean = value.trim();
    if (clean.length < 4) return false;
    return RegExp(r'[A-Za-z]').hasMatch(clean) &&
        (RegExp(r'\d').hasMatch(clean) || clean.contains('-') || clean.contains('_'));
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

    final q = _compact(query);
    final scored = _categorySuggestions
        .map((category) => _ScoredSuggestionCategory(
      category: category,
      score: _categorySuggestionScore(category, q),
    ))
        .where((item) => item.score > 0)
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return scored.isNotEmpty ? scored.first.category : _categorySuggestions.first;
  }

  int _categorySuggestionScore(CategoryModel category, String compactQuery) {
    final name = _compact(category.name);
    var score = 0;
    if (name.contains(compactQuery)) score += 100;
    if (compactQuery.contains('dom') && (name.contains('domo') || name.contains('minidomo'))) score += 90;
    if ((compactQuery.contains('turret') || compactQuery.contains('turet')) && name.contains('turret')) score += 90;
    if ((compactQuery.contains('bullet') || compactQuery.contains('tubular')) &&
        (name.contains('bullet') || name.contains('tubular'))) score += 90;
    if ((compactQuery.contains('nvr') || compactQuery.contains('grab')) &&
        (name.contains('grabador') || name.contains('nvr'))) score += 90;
    if (name.contains('camara')) score += 8;
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
    final showSuggestions = query.length >= 2 && _looksLikeSku(query);

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
                  color: AppColors.primary.withValues(alpha: 0.16),
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
                  color: Colors.white.withValues(alpha: 0.78),
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
                categories: _categorySuggestions,
                products: _productSuggestions,
                onSearchAll: () => _buscar(_controller.text),
                onSmartSearch: _openSmartCategoryOrSearch,
                onCategoryTap: (category) => _openCategory(category),
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
  final List<CategoryModel> categories;
  final List<Product> products;
  final VoidCallback onSearchAll;
  final VoidCallback onSmartSearch;
  final ValueChanged<CategoryModel> onCategoryTap;
  final ValueChanged<Product> onProductTap;

  const _HomeSearchSuggestionsPanel({
    required this.query,
    required this.loading,
    required this.categories,
    required this.products,
    required this.onSearchAll,
    required this.onSmartSearch,
    required this.onCategoryTap,
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
            color: Colors.black.withValues(alpha: 0.08),
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
                            color: AppColors.primary.withValues(alpha: 0.08),
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
                            'Buscar “$query” en catálogo',
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
                if (_smartSearchLabel(query) != null)
                  _SmartSearchShortcut(
                    label: _smartSearchLabel(query)!,
                    onTap: onSmartSearch,
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
                if (categories.isNotEmpty) ...[
                  const _SuggestionsTitle('APARTADOS'),
                  for (final category in categories)
                    _CategorySuggestionTile(
                      category: category,
                      onTap: () => onCategoryTap(category),
                    ),
                ],
                if (products.isNotEmpty) ...[
                  const _SuggestionsTitle('PRODUCTOS'),
                  for (final product in products.take(5))
                    _ProductSuggestionTile(
                      product: product,
                      query: query,
                      onTap: () => onProductTap(product),
                    ),
                ],
                if (!loading && categories.isEmpty && products.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: Text(
                      'Pulsa buscar para ver todos los resultados.',
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

String? _smartSearchLabel(String query) {
  final q = query
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '');

  if (q.contains('dom')) return 'Ver cámaras domo relacionadas';
  if (q.contains('turret') || q.contains('turet')) return 'Ver cámaras turret relacionadas';
  if (q.contains('bullet') || q.contains('tubular')) return 'Ver cámaras bullet/tubulares';
  if (q.contains('nvr') || q.contains('grab')) return 'Ver grabadores relacionados';
  return null;
}

class _SmartSearchShortcut extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SmartSearchShortcut({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 7),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: AppColors.primary,
                size: 16,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Oswald',
                  color: AppColors.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const Icon(
              Icons.arrow_forward_rounded,
              color: AppColors.primary,
              size: 18,
            ),
          ],
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
              child: Image.network(
                product.imageUrl,
                width: 38,
                height: 38,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/features/catalog/data/models/category_model.dart';
import 'package:mundicam/features/catalog/data/models/producto.dart';
import 'package:mundicam/features/catalog/presentation/pages/productos_por_categoria.dart';
import 'package:mundicam/features/catalog/presentation/providers/filter_provider.dart';
import 'package:mundicam/shared/theme/app_theme.dart';

class FiltroSelector extends ConsumerStatefulWidget {
  final int parentCategoryId;
  final String categoryName;

  /// Se mantiene para no romper llamadas existentes desde ProductosPorCategoriaScreen.
  /// Se usa como fuente rápida y fiable para calcular marcas visibles en subcategorías pequeñas.
  final List<Product> productosEnPantalla;

  const FiltroSelector({
    super.key,
    required this.parentCategoryId,
    required this.categoryName,
    required this.productosEnPantalla,
  });

  @override
  ConsumerState<FiltroSelector> createState() => _FiltroSelectorState();
}

class _FiltroSelectorState extends ConsumerState<FiltroSelector> {
  final ApiService _apiService = ApiService();

  static const Duration _cacheTtl = Duration(minutes: 3);
  static const int _maxCacheEntries = 60;
  static final Map<String, _FilterDataCacheEntry> _filterCache = {};

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _availableBrands = [];
  List<CategoryModel> _availableSubcategories = [];
  int _previewTotal = 0;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFilterData();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<MundiFilters>(productFilterProvider, (previous, next) {
      if (previous != next) {
        _loadFilterData();
      }
    });

    final filtroState = ref.watch(productFilterProvider);

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.90,
      backgroundColor: const Color(0xFFF5F6F8),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _header(filtroState),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () => _loadFilterData(forceRefresh: true),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  children: [
                    if (_error != null) ...[
                      _errorCard(_error!),
                      const SizedBox(height: 14),
                    ],
                    _sectionCard(
                      title: 'ORDENAR POR',
                      icon: Icons.swap_vert_rounded,
                      child: Column(
                        children: [
                          _buildSortTile(
                            'Más recientes',
                            'date',
                            Icons.access_time_rounded,
                          ),
                          _buildDivider(),
                          _buildSortTile(
                            'Precio: más barato primero',
                            'price_asc',
                            Icons.trending_up_rounded,
                          ),
                          _buildDivider(),
                          _buildSortTile(
                            'Precio: más caro primero',
                            'price_desc',
                            Icons.trending_down_rounded,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _sectionCard(
                      title: 'FILTRAR POR MARCA',
                      icon: Icons.sell_outlined,
                      subtitle: 'Marcas disponibles para ${widget.categoryName}',
                      child: _loading && _availableBrands.isEmpty
                          ? _loadingBox('Cargando marcas...')
                          : _availableBrands.isEmpty
                          ? _emptyInfo(
                        'No hay marcas compatibles en los productos cargados.',
                        Icons.info_outline,
                      )
                          : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (filtroState.hasBrand) ...[
                            _allBrandsTile(),
                            const SizedBox(height: 10),
                          ],
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _availableBrands
                                .map(_buildMarcaChip)
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _sectionCard(
                      title: 'SUBCATEGORÍAS',
                      icon: Icons.category_rounded,
                      subtitle: 'Subfamilias dentro de ${widget.categoryName}',
                      child: _loading && _availableSubcategories.isEmpty
                          ? _loadingBox('Cargando subcategorías...')
                          : _availableSubcategories.isEmpty
                          ? _emptyInfo(
                        'No hay más subcategorías.',
                        Icons.folder_off_outlined,
                      )
                          : Column(
                        children: _availableSubcategories
                            .map(_buildSubcategoryRow)
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _bottomButtons(filtroState),
          ],
        ),
      ),
    );
  }

  Future<void> _loadFilterData({
    bool forceRefresh = false,
  }) async {
    final requestToken = ++_loadToken;
    final filters = ref.read(productFilterProvider);
    final cacheKey = _buildCacheKey(filters);

    if (!forceRefresh) {
      final cached = _readCache(cacheKey);
      if (cached != null) {
        if (!mounted || requestToken != _loadToken) return;
        setState(() {
          _availableBrands = cached.availableBrands;
          _availableSubcategories = cached.availableSubcategories;
          _previewTotal = cached.previewTotal;
          _loading = false;
          _error = null;
        });
        return;
      }
    }

    if (mounted && requestToken == _loadToken) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final search = filters.search.trim();
      final effectiveSearch = search.isEmpty ? null : search;
      final effectiveBrandId = filters.brandId ??
          await _apiService
              .getMarcaIdPorNombre(
            filters.brand.trim().isEmpty ? null : filters.brand.trim(),
          )
              .timeout(const Duration(seconds: 3));

      final brands = await _loadBrandsFast(search: effectiveSearch);
      final subcategories = await _loadSubcategoriesFast();

      CatalogProductsResult? preview;
      try {
        preview = await _apiService
            .getProductosCatalogoFiltrado(
          categoryId: widget.parentCategoryId,
          brandId: effectiveBrandId,
          search: effectiveSearch,
          page: 1,
          perPage: 1,
          orderBy: filters.orderBy,
        )
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        preview = null;
      }

      final previewTotal = preview?.totalItems ?? 0;

      final cacheEntry = _FilterDataCacheEntry(
        availableBrands: brands,
        availableSubcategories: subcategories,
        previewTotal: previewTotal,
        createdAt: DateTime.now(),
      );

      _writeCache(cacheKey, cacheEntry);

      if (!mounted || requestToken != _loadToken) return;
      setState(() {
        _availableBrands = brands;
        _availableSubcategories = subcategories;
        _previewTotal = previewTotal;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted || requestToken != _loadToken) return;
      setState(() {
        _loading = false;
        _error = 'No se pudieron cargar los filtros.';
      });
    }
  }

  Future<List<Map<String, dynamic>>> _loadBrandsFast({
    String? search,
  }) async {
    // Primero usa el cálculo contextual de la API, que devuelve marcas con ID
    // y contadores reales del contexto. No usamos la primera página visible
    // para no volver a mostrar solo 30 productos en categorías de 800+.
    try {
      final brands = await _apiService
          .getMarcasDisponiblesCatalogo(
        categoryId: widget.parentCategoryId,
        search: search,
      )
          .timeout(const Duration(seconds: 8));

      final list = List<Map<String, dynamic>>.from(brands)
          .where((brand) => _brandNameFromMap(brand).isNotEmpty)
          .where((brand) => _brandIdFromMap(brand) != null)
          .where((brand) => _brandCountFromMap(brand) > 0)
          .toList();

      list.sort(
            (a, b) => _brandNameFromMap(a).toLowerCase().compareTo(
          _brandNameFromMap(b).toLowerCase(),
        ),
      );

      if (list.isNotEmpty) return list;
    } catch (_) {
      // Si falla el cálculo contextual, recuperamos marcas globales con ID
      // para que la selección de marca siga funcionando.
    }

    try {
      final brands = await _apiService
          .getMarcas(hideEmpty: true)
          .timeout(const Duration(seconds: 8));

      final list = List<Map<String, dynamic>>.from(brands)
          .where((brand) => _brandNameFromMap(brand).isNotEmpty)
          .where((brand) => _brandIdFromMap(brand) != null)
          .toList();

      list.sort(
            (a, b) => _brandNameFromMap(a).toLowerCase().compareTo(
          _brandNameFromMap(b).toLowerCase(),
        ),
      );

      return list;
    } catch (_) {
      return [];
    }
  }

  Future<List<CategoryModel>> _loadSubcategoriesFast() async {
    try {
      final subcategories = await _apiService
          .getSubcategoriasDe(widget.parentCategoryId)
          .timeout(const Duration(seconds: 8));

      final list = subcategories.where((category) => category.count > 0).toList()
        ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );

      return list;
    } catch (_) {
      return [];
    }
  }

  String _buildCacheKey(MundiFilters filters) {
    return [
      'cat:${widget.parentCategoryId}',
      'brandId:${filters.brandId ?? 0}',
      'brand:${filters.brand.trim().toLowerCase()}',
      'search:${filters.search.trim().toLowerCase()}',
      'order:${filters.orderBy}',
    ].join('|');
  }

  static _FilterDataCacheEntry? _readCache(String key) {
    final entry = _filterCache[key];
    if (entry == null) return null;
    if (!entry.isValid) {
      _filterCache.remove(key);
      return null;
    }
    return entry;
  }

  static void _writeCache(String key, _FilterDataCacheEntry entry) {
    _filterCache[key] = entry;
    if (_filterCache.length <= _maxCacheEntries) return;

    final entries = _filterCache.entries.toList()
      ..sort((a, b) => a.value.createdAt.compareTo(b.value.createdAt));
    final amountToRemove = _filterCache.length - _maxCacheEntries;

    for (final item in entries.take(amountToRemove)) {
      _filterCache.remove(item.key);
    }
  }

  int? _brandIdFromMap(Map<String, dynamic> brand) {
    final raw = brand['id'];
    if (raw is int && raw > 0) return raw;
    return int.tryParse(raw?.toString() ?? '');
  }

  String _brandNameFromMap(Map<String, dynamic> brand) {
    return brand['name']?.toString().trim() ?? '';
  }

  int _brandCountFromMap(Map<String, dynamic> brand) {
    final raw = brand['available_count'] ?? brand['count'];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  void _seleccionarMarca(Map<String, dynamic> brand) {
    final brandId = _brandIdFromMap(brand);
    final brandName = _brandNameFromMap(brand);

    if (brandId == null || brandId <= 0 || brandName.isEmpty) {
      return;
    }

    final current = ref.read(productFilterProvider);
    if (current.brandId == brandId ||
        current.brand.trim().toLowerCase() == brandName.toLowerCase()) {
      ref.read(productFilterProvider.notifier).clearBrand();
      return;
    }

    ref.read(productFilterProvider.notifier).setBrand(
      name: brandName,
      id: brandId,
    );
  }

  void _irAProductos(CategoryModel cat) {
    final categoryId = cat.id;
    if (categoryId == null || categoryId <= 0) {
      return;
    }

    // Las subcategorías son navegación, no un filtro acumulado.
    // Cambio mínimo: abrimos la subcategoría encima de la categoría actual para que
    // la flecha superior pueda volver a la categoría anterior.
    _filterCache.clear();
    ref.read(productFilterProvider.notifier).reset();

    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute(
        builder: (_) => ProductosPorCategoriaScreen(
          categoryId: categoryId,
          categoryName: cat.name,
        ),
      ),
    );
  }

  void _limpiarFiltros() {
    // Restablecer limpia el estado global y cierra el drawer.
    // La pantalla de productos se sincroniza al detectar el cambio de filtros
    // y al cerrarse el drawer, sin recalcular marcas dentro del propio panel.
    _filterCache.clear();
    ref.read(productFilterProvider.notifier).reset();

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _aplicarYCerrar() => Navigator.pop(context);

  void _cerrarDrawer() => Navigator.pop(context);

  Widget _header(MundiFilters filtroState) {
    final contextParts = <String>[
      widget.categoryName,
      if (filtroState.brand.trim().isNotEmpty) filtroState.brand.trim(),
      if (filtroState.search.trim().isNotEmpty) '“${filtroState.search.trim()}”',
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 10, 16),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.28),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.tune_rounded,
              color: Colors.white,
              size: 23,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Filtros del catálogo',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    fontFamily: 'Oswald',
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  contextParts.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          if (filtroState.hasActiveFilters && _previewTotal > 0)
            Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$_previewTotal',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          IconButton(
            icon: const Icon(
              Icons.close_rounded,
              color: Colors.white,
              size: 23,
            ),
            onPressed: _cerrarDrawer,
          ),
        ],
      ),
    );
  }

  Widget _errorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF1C7C7)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.primary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textPrimary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE7E7E7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: AppColors.primary),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                    letterSpacing: 0.65,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 7),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _loadingBox(String text) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE7E7E7)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyInfo(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE7E7E7)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[500]),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF6B7280),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortTile(String label, String value, IconData icon) {
    final currentSort = ref.watch(productFilterProvider).orderBy;
    final isSelected = currentSort == value;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        if (isSelected) {
          ref.read(productFilterProvider.notifier).clearOrderBy();
        } else {
          ref.read(productFilterProvider.notifier).setOrderBy(value);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.07)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? AppColors.primary : const Color(0xFF6B7280),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? AppColors.primary : AppColors.textPrimary,
                ),
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle_rounded,
                size: 21,
                color: AppColors.primary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 44,
      color: Colors.grey.shade200,
    );
  }

  Widget _allBrandsTile() {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => ref.read(productFilterProvider.notifier).clearBrand(),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE1E4EA)),
        ),
        child: const Row(
          children: [
            Icon(
              Icons.clear_rounded,
              color: AppColors.primary,
              size: 18,
            ),
            SizedBox(width: 9),
            Expanded(
              child: Text(
                'Todas las marcas',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarcaChip(Map<String, dynamic> brand) {
    final selectedFilter = ref.watch(productFilterProvider);
    final brandId = _brandIdFromMap(brand);
    final marcaNombre = _brandNameFromMap(brand);
    final count = _brandCountFromMap(brand);

    if (marcaNombre.isEmpty || count <= 0) {
      return const SizedBox.shrink();
    }

    final isSelected =
        (brandId != null && brandId > 0 && selectedFilter.brandId == brandId) ||
            selectedFilter.brand.trim().toLowerCase() == marcaNombre.toLowerCase();

    return GestureDetector(
      onTap: () {
        _seleccionarMarca(brand);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: isSelected ? AppColors.primary : const Color(0xFFD9DEE7),
            width: isSelected ? 1.6 : 1,
          ),
          boxShadow: isSelected
              ? [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.18),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sell_outlined,
              size: 14,
              color: isSelected ? Colors.white : AppColors.primary,
            ),
            const SizedBox(width: 6),
            Text(
              marcaNombre,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '($count)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: isSelected ? Colors.white70 : const Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubcategoryRow(CategoryModel cat) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _irAProductos(cat),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.folder_rounded,
              size: 20,
              color: AppColors.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                cat.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (cat.count > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${cat.count}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                  ),
                ),
              ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 21,
              color: Color(0xFF6B7280),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomButtons(MundiFilters filtroState) {
    final hasFilters = filtroState.hasActiveFilters;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 50,
              child: OutlinedButton(
                onPressed: hasFilters ? _limpiarFiltros : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  disabledForegroundColor: Colors.grey.shade400,
                  side: const BorderSide(color: Color(0xFFD9DEE7)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: const Text(
                  'Restablecer',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _aplicarYCerrar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: Text(
                  _previewTotal > 0 ? 'Ver productos ($_previewTotal)' : 'Ver productos',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterDataCacheEntry {
  final List<Map<String, dynamic>> availableBrands;
  final List<CategoryModel> availableSubcategories;
  final int previewTotal;
  final DateTime createdAt;

  const _FilterDataCacheEntry({
    required this.availableBrands,
    required this.availableSubcategories,
    required this.previewTotal,
    required this.createdAt,
  });

  bool get isValid {
    return DateTime.now().difference(createdAt) < _FiltroSelectorState._cacheTtl;
  }
}

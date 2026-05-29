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
  /// En esta versión no se usa para recalcular filtros: la fuente de verdad sigue siendo WooCommerce.
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
      backgroundColor: const Color(0xFFF4F7FB),
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
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                  children: [
                    if (_error != null) ...[
                      _errorCard(_error!),
                      const SizedBox(height: 12),
                    ],
                    _sectionCard(
                      title: 'Ordenar por',
                      icon: Icons.swap_vert_rounded,
                      child: Column(
                        children: [
                          _buildSortTile(
                            'Más recientes',
                            'date',
                            Icons.access_time_rounded,
                          ),
                          const SizedBox(height: 8),
                          _buildSortTile(
                            'Precio bajo primero',
                            'price_asc',
                            Icons.trending_up_rounded,
                          ),
                          const SizedBox(height: 8),
                          _buildSortTile(
                            'Precio alto primero',
                            'price_desc',
                            Icons.trending_down_rounded,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _sectionCard(
                      title: 'Filtrar por marca',
                      icon: Icons.sell_outlined,
                      subtitle: 'Marcas disponibles para ${widget.categoryName}',
                      child: _loading && _availableBrands.isEmpty
                          ? _loadingBox('Cargando marcas...')
                          : _availableBrands.isEmpty
                          ? _emptyInfo(
                        'No hay marcas compatibles en este contexto.',
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
                            spacing: 7,
                            runSpacing: 8,
                            children: _availableBrands
                                .map(_buildMarcaChip)
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _sectionCard(
                      title: 'Subcategorías',
                      icon: Icons.folder_special_rounded,
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
        // No vaciamos lo que ya hay: así el panel no se queda bloqueado visualmente
        // cada vez que se cambia el orden.
        _loading = _availableBrands.isEmpty && _availableSubcategories.isEmpty;
        _error = null;
      });
    }

    try {
      final search = filters.search.trim();
      final effectiveSearch = search.isEmpty ? null : search;

      final brandIdFuture = _resolveBrandIdQuick(filters);
      final brandsFuture = _loadBrandsFast(search: effectiveSearch);
      final subcategoriesFuture = _loadSubcategoriesFast();

      final effectiveBrandId = await brandIdFuture;

      final previewFuture = _loadPreviewTotalFast(
        brandId: effectiveBrandId,
        search: effectiveSearch,
        orderBy: filters.orderBy,
      );

      final brands = await brandsFuture;
      final subcategories = await subcategoriesFuture;
      final previewTotal = await previewFuture;

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

  Future<int?> _resolveBrandIdQuick(MundiFilters filters) async {
    if (filters.brandId != null && filters.brandId! > 0) {
      return filters.brandId;
    }

    final brandName = filters.brand.trim();
    if (brandName.isEmpty) return null;

    try {
      return await _apiService
          .getMarcaIdPorNombre(brandName)
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      return null;
    }
  }

  Future<int> _loadPreviewTotalFast({
    required int? brandId,
    required String? search,
    required String orderBy,
  }) async {
    try {
      final preview = await _apiService
          .getProductosCatalogoFiltrado(
        categoryId: widget.parentCategoryId,
        brandId: brandId,
        search: search,
        page: 1,
        perPage: 1,
        orderBy: orderBy,
      )
          .timeout(const Duration(seconds: 3));

      return preview.totalItems;
    } catch (_) {
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> _loadBrandsFast({
    String? search,
  }) async {
    List<Map<String, dynamic>> cleanBrandList(List<Map<String, dynamic>> brands) {
      final list = brands
          .where((brand) => _brandNameFromMap(brand).isNotEmpty)
          .where((brand) => _brandIdFromMap(brand) != null)
          .where((brand) => _brandCountFromMap(brand) > 0)
          .toList();

      list.sort(
            (a, b) => _brandNameFromMap(a).toLowerCase().compareTo(
          _brandNameFromMap(b).toLowerCase(),
        ),
      );

      return list;
    }

    try {
      final brands = await _apiService
          .getMarcasDisponiblesCatalogo(
        categoryId: widget.parentCategoryId,
        search: search,
      )
          .timeout(const Duration(seconds: 3));

      final list = cleanBrandList(List<Map<String, dynamic>>.from(brands));
      if (list.isNotEmpty) return list;
    } catch (_) {
      // No bloqueamos el panel de filtros si falla el cálculo contextual.
    }

    // Fallback importante: si una búsqueda genérica como “camara” no devuelve
    // counts de marcas a tiempo, mostramos las marcas disponibles de la familia
    // principal. Es preferible ofrecer marcas filtrables a dejar el panel vacío.
    if (search != null && search.trim().isNotEmpty) {
      try {
        final brands = await _apiService
            .getMarcasDisponiblesCatalogo(
          categoryId: widget.parentCategoryId,
          search: null,
        )
            .timeout(const Duration(seconds: 3));

        final list = cleanBrandList(List<Map<String, dynamic>>.from(brands));
        if (list.isNotEmpty) return list;
      } catch (_) {
        // Último fallback debajo.
      }
    }

    try {
      final brands = await _apiService
          .getMarcas(hideEmpty: true)
          .timeout(const Duration(seconds: 3));

      final list = List<Map<String, dynamic>>.from(brands)
          .where((brand) => _brandNameFromMap(brand).isNotEmpty)
          .where((brand) => _brandIdFromMap(brand) != null)
          .map((brand) {
        final count = _brandCountFromMap(brand);
        return <String, dynamic>{
          ...brand,
          // Evita que la UI oculte todas las marcas si WooCommerce no trae
          // count en este endpoint de fallback.
          if (count <= 0) 'available_count': 1,
        };
      })
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
          .timeout(const Duration(seconds: 3));

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
    // El orden no cambia marcas ni subcategorías ni el total de productos.
    // Si lo metemos en la clave, cada pulsación en "precio bajo/alto" vuelve a
    // pedir filtros a la API y ralentiza el panel sin necesidad.
    return [
      'cat:${widget.parentCategoryId}',
      'brandId:${filters.brandId ?? 0}',
      'brand:${filters.brand.trim().toLowerCase()}',
      'search:${filters.search.trim().toLowerCase()}',
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
    _filterCache.clear();
    ref.read(productFilterProvider.notifier).reset();

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _aplicarYCerrar() => Navigator.pop(context);

  void _cerrarDrawer() => Navigator.pop(context);

  String _normalize(String value) {
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

  IconData _subcategoryIcon(String name) {
    final n = _normalize(name);

    if (n.contains('camara') || n.contains('cctv') || n.contains('video')) {
      return Icons.videocam_rounded;
    }

    if (n.contains('grabador') || n.contains('nvr') || n.contains('xvr')) {
      return Icons.dns_rounded;
    }

    if (n.contains('software') || n.contains('licencia')) {
      return Icons.terminal_rounded;
    }

    if (n.contains('radar')) {
      return Icons.radar_rounded;
    }

    if (n.contains('videoportero') || n.contains('portero')) {
      return Icons.doorbell_rounded;
    }

    if (n.contains('accesorio') ||
        n.contains('soporte') ||
        n.contains('caja') ||
        n.contains('alimentacion') ||
        n.contains('cable')) {
      return Icons.extension_rounded;
    }

    if (n.contains('detector') || n.contains('sensor')) {
      return Icons.sensors_rounded;
    }

    if (n.contains('central')) {
      return Icons.settings_input_component_rounded;
    }

    return Icons.folder_rounded;
  }

  Widget _header(MundiFilters filtroState) {
    final contextParts = <String>[
      widget.categoryName,
      if (filtroState.brand.trim().isNotEmpty) filtroState.brand.trim(),
      if (filtroState.search.trim().isNotEmpty) '“${filtroState.search.trim()}”',
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 15, 8, 15),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.24),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
              ),
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
                  'Filtros',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    fontFamily: 'Oswald',
                    letterSpacing: 0.2,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  contextParts.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.76),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (filtroState.hasActiveFilters && _previewTotal > 0)
            Container(
              margin: const EdgeInsets.only(right: 2),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$_previewTotal',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
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
        borderRadius: BorderRadius.circular(20),
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
                fontWeight: FontWeight.w600,
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
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE6EAF0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 17, color: AppColors.primary),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                    letterSpacing: 0.72,
                    fontFamily: 'Oswald',
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
                fontSize: 11.2,
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ],
          const SizedBox(height: 13),
          child,
        ],
      ),
    );
  }

  Widget _loadingBox(String text) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6EAF0)),
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
                fontWeight: FontWeight.w600,
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
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6EAF0)),
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
                fontWeight: FontWeight.w600,
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
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        if (isSelected) {
          ref.read(productFilterProvider.notifier).clearOrderBy();
        } else {
          ref.read(productFilterProvider.notifier).setOrderBy(value);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.08)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.24)
                : const Color(0xFFE6EAF0),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 31,
              height: 31,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: isSelected ? AppColors.primary : const Color(0xFFE6EAF0),
                ),
              ),
              child: Icon(
                icon,
                size: 17,
                color: isSelected ? Colors.white : const Color(0xFF6B7280),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13.2,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                  color: isSelected ? AppColors.primary : AppColors.textPrimary,
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: isSelected
                  ? const Icon(
                Icons.check_circle_rounded,
                key: ValueKey('selected'),
                size: 21,
                color: AppColors.primary,
              )
                  : const Icon(
                Icons.chevron_right_rounded,
                key: ValueKey('unselected'),
                size: 21,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _allBrandsTile() {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => ref.read(productFilterProvider.notifier).clearBrand(),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7F7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF0D4D4)),
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
                  fontSize: 13.2,
                  fontWeight: FontWeight.w900,
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

    if (marcaNombre.isEmpty) {
      return const SizedBox.shrink();
    }

    final isSelected =
        (brandId != null && brandId > 0 && selectedFilter.brandId == brandId) ||
            selectedFilter.brand.trim().toLowerCase() ==
                marcaNombre.toLowerCase();

    return GestureDetector(
      onTap: () {
        _seleccionarMarca(brand);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.primary : const Color(0xFFDDE3EC),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.18),
              blurRadius: 9,
              offset: const Offset(0, 3),
            ),
          ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sell_outlined,
              size: 13,
              color: isSelected ? Colors.white : AppColors.primary,
            ),
            const SizedBox(width: 6),
            Text(
              marcaNombre,
              style: TextStyle(
                fontSize: 11.8,
                fontWeight: FontWeight.w900,
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubcategoryRow(CategoryModel cat) {
    final icon = _subcategoryIcon(cat.name);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _irAProductos(cat),
      child: Container(
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE6EAF0)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 18,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                cat.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.2,
                  fontWeight: FontWeight.w800,
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
              color: Color(0xFF9CA3AF),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomButtons(MundiFilters filtroState) {
    final hasFilters = filtroState.hasActiveFilters;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          top: BorderSide(color: Color(0xFFE6EAF0)),
        ),
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
          SizedBox(
            width: 112,
            height: 50,
            child: OutlinedButton(
              onPressed: hasFilters ? _limpiarFiltros : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                disabledForegroundColor: Colors.grey.shade400,
                backgroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFFD9DEE7)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Restablecer',
                maxLines: 2,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 11.5,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _aplicarYCerrar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  _previewTotal > 0
                      ? 'Ver $_previewTotal productos'
                      : 'Ver productos',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14.2,
                    fontFamily: 'Oswald',
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
    return DateTime.now().difference(createdAt) <
        _FiltroSelectorState._cacheTtl;
  }
}

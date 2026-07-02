import 'package:flutter/foundation.dart';
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
  final List<Product> productosEnPantalla;
  final VoidCallback? onApplyFilters;

  const FiltroSelector({
    super.key,
    required this.parentCategoryId,
    required this.categoryName,
    required this.productosEnPantalla,
    this.onApplyFilters,
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
  List<CatalogFilterGroup> _availableFilterGroups = [];
  List<CategoryModel> _availableSubcategories = [];
  int _loadToken = 0;
  late MundiFilters _draftFilters;
  bool _applyingFiltersAndClosing = false;

  @override
  void initState() {
    super.initState();
    _draftFilters = ref.read(productFilterProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFilterData();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<MundiFilters>(productFilterProvider, (previous, next) {
      if (_applyingFiltersAndClosing) {
        return;
      }

      if (previous != next) {
        setState(() {
          _draftFilters = next;
        });
        _loadFilterData();
      }
    });

    final filtroState = _draftFilters;

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.92,
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
                      title: 'Categorías del producto',
                      icon: Icons.folder_special_rounded,
                      subtitle: 'Subfamilias dentro de ${widget.categoryName}',
                      child: _loading && _availableSubcategories.isEmpty
                          ? _loadingBox('Cargando categorías...')
                          : _availableSubcategories.isEmpty
                          ? _emptyInfo(
                        'No hay más subcategorías en este apartado.',
                        Icons.folder_off_outlined,
                      )
                          : Column(
                        children: _availableSubcategories
                            .map(_buildSubcategoryRow)
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_loading && _availableFilterGroups.isEmpty)
                      _sectionCard(
                        title: 'Filtros',
                        icon: Icons.tune_rounded,
                        child: _loadingBox('Cargando filtros de la web...'),
                      )
                    else if (!_loading && _availableFilterGroups.isEmpty)
                      _sectionCard(
                        title: 'Filtros',
                        icon: Icons.tune_rounded,
                        child: _emptyInfo(
                          'No hay filtros compatibles en este contexto.',
                          Icons.info_outline,
                        ),
                      )
                    else
                      ..._availableFilterGroups.expand(
                            (group) => [
                          _buildFilterGroupCard(group),
                          const SizedBox(height: 12),
                        ],
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
          _availableFilterGroups = cached.availableFilterGroups;
          _availableSubcategories = cached.availableSubcategories;
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

      // Primera carga: no usamos timeout corto aquí.
      // La primera vez WooCommerce tiene que cargar términos de varios atributos
      // y puede tardar más que en un refresh posterior. Si cortamos a los pocos
      // segundos, aparece el mensaje de error aunque la API termine respondiendo.
      final groups = await _apiService.getCatalogFiltersForCategory(
        categoryId: widget.parentCategoryId,
        brandId: filters.brandId,
        search: effectiveSearch,
        forceRefresh: forceRefresh,
      );

      final subcategories = await _loadSubcategoriesFast();

      final cacheEntry = _FilterDataCacheEntry(
        availableFilterGroups: groups,
        availableSubcategories: subcategories,
        createdAt: DateTime.now(),
      );

      _writeCache(cacheKey, cacheEntry);

      if (!mounted || requestToken != _loadToken) return;
      setState(() {
        _availableFilterGroups = groups;
        _availableSubcategories = subcategories;
        _loading = false;
        _error = null;
      });

      if (kDebugMode) {
        debugPrint(
          '📊 Filtros web cargados: ${groups.length} grupos, '
              '${subcategories.length} subcats',
        );
      }
    } catch (e) {
      if (!mounted || requestToken != _loadToken) return;
      setState(() {
        _loading = false;
        _error = 'No se pudieron cargar los filtros.';
      });
      if (kDebugMode) {
        debugPrint('❌ Error loading web filters: $e');
      }
    }
  }

  Future<List<CategoryModel>> _loadSubcategoriesFast() async {
    try {
      final subcategories = await _apiService.getSubcategoriasDe(
        widget.parentCategoryId,
      );

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
      'attrs:${_attributesCachePart(filters.attributeTermIds)}',
    ].join('|');
  }

  static String _attributesCachePart(Map<String, int> attrs) {
    if (attrs.isEmpty) return '';
    final keys = attrs.keys.toList()..sort();
    return keys.map((key) => '$key:${attrs[key]}').join(',');
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

  void _toggleOption(CatalogFilterGroup group, CatalogFilterOption option) {
    if (option.id <= 0 || option.name.trim().isEmpty) return;

    // Cambio local dentro del drawer: no tocamos el provider global hasta
    // pulsar "Ver productos". Así se pueden marcar varios filtros sin
    // lanzar una recarga por cada clic.
    setState(() {
      if (_isBrandGroup(group)) {
        final isSelected = _draftFilters.brandId == option.id ||
            _draftFilters.brand.trim().toLowerCase() ==
                option.name.trim().toLowerCase();

        if (isSelected) {
          _draftFilters = _draftFilters.copyWith(
            brand: '',
            clearBrandId: true,
          );
        } else {
          _draftFilters = _draftFilters.copyWith(
            brand: option.name.trim(),
            brandId: option.id,
          );
        }
        return;
      }

      final cleanTaxonomy = group.taxonomy.trim();
      final cleanLabel = option.name.trim();
      if (cleanTaxonomy.isEmpty || cleanLabel.isEmpty) return;

      final currentTermId = _draftFilters.attributeTermIds[cleanTaxonomy];
      final nextTerms = Map<String, int>.from(_draftFilters.attributeTermIds);
      final nextLabels = Map<String, String>.from(_draftFilters.attributeLabels);
      final nextGroupLabels =
      Map<String, String>.from(_draftFilters.attributeGroupLabels);

      if (currentTermId == option.id) {
        nextTerms.remove(cleanTaxonomy);
        nextLabels.remove(cleanTaxonomy);
        nextGroupLabels.remove(cleanTaxonomy);
      } else {
        nextTerms[cleanTaxonomy] = option.id;
        nextLabels[cleanTaxonomy] = cleanLabel;
        nextGroupLabels[cleanTaxonomy] =
        group.title.trim().isEmpty ? cleanTaxonomy : group.title.trim();
      }

      _draftFilters = _draftFilters.copyWith(
        attributeTermIds: nextTerms,
        attributeLabels: nextLabels,
        attributeGroupLabels: nextGroupLabels,
      );
    });
  }

  void _clearGroup(CatalogFilterGroup group) {
    setState(() {
      if (_isBrandGroup(group)) {
        _draftFilters = _draftFilters.copyWith(
          brand: '',
          clearBrandId: true,
        );
        return;
      }

      final cleanTaxonomy = group.taxonomy.trim();
      if (cleanTaxonomy.isEmpty) return;

      final nextTerms = Map<String, int>.from(_draftFilters.attributeTermIds)
        ..remove(cleanTaxonomy);
      final nextLabels = Map<String, String>.from(_draftFilters.attributeLabels)
        ..remove(cleanTaxonomy);
      final nextGroupLabels =
      Map<String, String>.from(_draftFilters.attributeGroupLabels)
        ..remove(cleanTaxonomy);

      _draftFilters = _draftFilters.copyWith(
        attributeTermIds: nextTerms,
        attributeLabels: nextLabels,
        attributeGroupLabels: nextGroupLabels,
      );
    });
  }

  bool _isOptionSelected(
      MundiFilters filters,
      CatalogFilterGroup group,
      CatalogFilterOption option,
      ) {
    if (_isBrandGroup(group)) {
      return filters.brandId == option.id ||
          filters.brand.trim().toLowerCase() == option.name.trim().toLowerCase();
    }

    return filters.attributeTermIds[group.taxonomy] == option.id;
  }

  bool _isGroupSelected(MundiFilters filters, CatalogFilterGroup group) {
    if (_isBrandGroup(group)) {
      return filters.hasBrand;
    }

    return filters.attributeTermIds.containsKey(group.taxonomy);
  }

  void _irAProductos(CategoryModel cat) {
    final categoryId = cat.id;
    if (categoryId <= 0) return;

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
    setState(() {
      _draftFilters = const MundiFilters();
    });
  }

  void _aplicarYCerrar() {
    _applyingFiltersAndClosing = true;

    ref.read(productFilterProvider.notifier).update(
      brand: _draftFilters.brand,
      brandId: _draftFilters.brandId,
      search: _draftFilters.search,
      orderBy: _draftFilters.orderBy,
      attributeTermIds: Map<String, int>.from(_draftFilters.attributeTermIds),
      attributeLabels: Map<String, String>.from(_draftFilters.attributeLabels),
      attributeGroupLabels:
      Map<String, String>.from(_draftFilters.attributeGroupLabels),
    );

    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onApplyFilters?.call();
    });
  }

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

  bool _isBrandGroup(CatalogFilterGroup group) {
    final normalized = _normalize(
      '${group.taxonomy} ${group.title} ${group.key}',
    ).replaceAll(RegExp(r'[^a-z0-9]+'), '');

    return normalized.contains('pamarcas') ||
        normalized.contains('pamarca') ||
        normalized.contains('productbrand') ||
        normalized.contains('pafabricante') ||
        normalized.contains('fabricante') ||
        normalized.contains('marca') ||
        normalized.contains('brand');
  }

  IconData _iconForFilterGroup(CatalogFilterGroup group) {
    switch (group.taxonomy) {
      case 'pa_marcas':
        return Icons.sell_outlined;
      case 'pa_resolucion':
        return Icons.high_quality_rounded;
      case 'pa_lente':
        return Icons.camera_alt_outlined;
      case 'pa_proteccion':
        return Icons.shield_outlined;
      case 'pa_microfono-integrado':
        return Icons.mic_none_rounded;
      case 'pa_wifi':
        return Icons.wifi_rounded;
      case 'pa_ancho-de-banda':
        return Icons.speed_rounded;
      case 'pa_grabacion-main-stream':
        return Icons.videocam_outlined;
      case 'pa_protocolo':
        return Icons.hub_outlined;
      case 'pa_smd':
        return Icons.memory_rounded;
      default:
        return Icons.tune_rounded;
    }
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
      ...filtroState.attributeLabels.values.where((value) => value.trim().isNotEmpty),
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

  Widget _buildFilterGroupCard(CatalogFilterGroup group) {
    final filters = _draftFilters;
    final groupSelected = _isGroupSelected(filters, group);

    return _sectionCard(
      title: group.title,
      icon: _iconForFilterGroup(group),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (groupSelected) ...[
            _clearGroupTile(group),
            const SizedBox(height: 8),
          ],
          ...group.options.map((option) => _buildFilterOptionRow(group, option)),
        ],
      ),
    );
  }

  Widget _clearGroupTile(CatalogFilterGroup group) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _clearGroup(group),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7F7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFF0D4D4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.clear_rounded, color: AppColors.primary, size: 17),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Todos los ${group.title.toLowerCase()}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
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

  Widget _buildFilterOptionRow(
      CatalogFilterGroup group,
      CatalogFilterOption option,
      ) {
    final selectedFilter = _draftFilters;
    final isSelected = _isOptionSelected(selectedFilter, group, option);

    return InkWell(
      onTap: () => _toggleOption(group, option),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : Colors.white,
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : const Color(0xFFD1D5DB),
                  width: 1,
                ),
              ),
              child: isSelected
                  ? const Icon(
                Icons.check,
                size: 11,
                color: Colors.white,
              )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                option.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.2,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${option.count}',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B7280),
                ),
              ),
            ),
          ],
        ),
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
    final currentSort = _draftFilters.orderBy;
    final isSelected = currentSort == value;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        setState(() {
          _draftFilters = _draftFilters.copyWith(
            orderBy: isSelected ? '' : value,
          );
        });
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
                child: const Text(
                  'Ver productos',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
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
  final List<CatalogFilterGroup> availableFilterGroups;
  final List<CategoryModel> availableSubcategories;
  final DateTime createdAt;

  const _FilterDataCacheEntry({
    required this.availableFilterGroups,
    required this.availableSubcategories,
    required this.createdAt,
  });

  bool get isValid {
    return DateTime.now().difference(createdAt) <
        _FiltroSelectorState._cacheTtl;
  }
}

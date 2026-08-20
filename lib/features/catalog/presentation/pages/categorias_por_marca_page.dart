import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/features/catalog/data/models/category_model.dart';
import 'package:mundicam/features/catalog/presentation/pages/productos_por_categoria.dart';
import 'package:mundicam/features/catalog/presentation/providers/filter_provider.dart';
import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/shared/widgets/professional_page_app_bar.dart';

class CategoriasPorMarcaPage extends ConsumerStatefulWidget {
  final int brandId;
  final String brandName;
  final String brandTaxonomy;
  final VoidCallback? onGoCart;
  final VoidCallback? onGoQuotes;

  const CategoriasPorMarcaPage({
    super.key,
    required this.brandId,
    required this.brandName,
    this.brandTaxonomy = '',
    this.onGoCart,
    this.onGoQuotes,
    this.parentCategoryId = 0,
    this.parentCategoryName = '',
    this.initialCategories,
  });

  // Compatibilidad con llamadas antiguas. En v1.9.92 se carga el árbol entero
  // de la marca y se navega dentro de una sola pantalla.
  final int parentCategoryId;
  final String parentCategoryName;
  final List<CategoryModel>? initialCategories;

  @override
  ConsumerState<CategoriasPorMarcaPage> createState() =>
      _CategoriasPorMarcaPageState();
}

class _CategoriasPorMarcaPageState
    extends ConsumerState<CategoriasPorMarcaPage> {
  final ApiService _api = ApiService();
  late Future<List<CategoryModel>> _treeFuture;
  final Set<int> _expandedIds = <int>{};

  @override
  void initState() {
    super.initState();
    _treeFuture = _loadFullTree();
  }

  Future<List<CategoryModel>> _loadFullTree({bool forceRefresh = false}) {
    // IMPORTANTE: parent=null hace que PHP 1.9.57 devuelva TODO el árbol de
    // categorías usado por ESTA marca (raíces + hijos + nietos), ya filtrado
    // por WooCommerce. Así las flechas no necesitan otra petición por nivel.
    return _api.getCategoriasPorMarca(
      brandId: widget.brandId,
      brandName: widget.brandName,
      brandTaxonomy: widget.brandTaxonomy,
      parent: null,
      forceRefresh: forceRefresh,
    );
  }

  Future<void> _refresh() async {
    final next = _loadFullTree(forceRefresh: true);
    setState(() {
      _expandedIds.clear();
      _treeFuture = next;
    });
    await next;
  }

  void _openProducts(CategoryModel category) {
    // La marca se fija ANTES de navegar. Esto evita que la pantalla de productos
    // tenga que modificar el provider durante su initState.
    final filters = ref.read(productFilterProvider);
    final notifier = ref.read(productFilterProvider.notifier);

    final sameBrand =
        filters.brandId == widget.brandId &&
        filters.brand.trim().toLowerCase() ==
            widget.brandName.trim().toLowerCase();

    if (!sameBrand ||
        filters.search.isNotEmpty ||
        filters.orderBy.isNotEmpty ||
        filters.attributeTermIds.isNotEmpty) {
      notifier.reset();
      notifier.setBrand(
        name: widget.brandName,
        id: widget.brandId,
      );
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProductosPorCategoriaScreen(
          categoryId: category.id,
          categoryName: category.name,
          initialBrandId: widget.brandId,
          initialBrandName: widget.brandName,
          initialBrandTaxonomy: widget.brandTaxonomy,
          onGoCart: widget.onGoCart,
          onGoQuotes: widget.onGoQuotes,
        ),
      ),
    );
  }

  Map<int, List<CategoryModel>> _groupByParent(
    List<CategoryModel> categories,
  ) {
    final grouped = <int, List<CategoryModel>>{};
    for (final category in categories) {
      grouped.putIfAbsent(category.parent, () => <CategoryModel>[]);
      grouped[category.parent]!.add(category);
    }

    // No reordenamos aquí. PHP ya devuelve cada nivel siguiendo menu_order.
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: ProfessionalPageAppBar(
        title: widget.brandName.toUpperCase(),
        subtitle: 'CATEGORÍAS',
        icon: Icons.category_outlined,
        onBack: () => Navigator.of(context).pop(),
        onRefresh: _refresh,
      ),
      body: FutureBuilder<List<CategoryModel>>(
        future: _treeFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          if (snapshot.hasError) {
            return _BrandCategoriesError(onRetry: _refresh);
          }

          final allCategories = snapshot.data ?? const <CategoryModel>[];
          if (allCategories.isEmpty) {
            return _BrandCategoriesEmpty(brandName: widget.brandName);
          }

          final byParent = _groupByParent(allCategories);
          final roots = byParent[0] ?? const <CategoryModel>[];

          if (roots.isEmpty) {
            return _BrandCategoriesEmpty(brandName: widget.brandName);
          }

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _refresh,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 26),
              itemCount: roots.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                return _buildNode(
                  roots[index],
                  byParent,
                  depth: 0,
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildNode(
    CategoryModel category,
    Map<int, List<CategoryModel>> byParent, {
    required int depth,
  }) {
    final children = byParent[category.id] ?? const <CategoryModel>[];
    final hasChildren = children.isNotEmpty;
    final expanded = _expandedIds.contains(category.id);

    return Padding(
      padding: EdgeInsets.only(left: depth == 0 ? 0 : 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BrandCategoryRow(
            category: category,
            depth: depth,
            hasChildren: hasChildren,
            expanded: expanded,
            onTap: () {
              if (!hasChildren) {
                _openProducts(category);
                return;
              }

              setState(() {
                if (expanded) {
                  _expandedIds.remove(category.id);
                } else {
                  _expandedIds.add(category.id);
                }
              });
            },
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: expanded && hasChildren
                ? depth == 0
                    ? Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: const Color(0xFFE7E7E7),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.025),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            for (var i = 0; i < children.length; i++) ...[
                              _buildNode(
                                children[i],
                                byParent,
                                depth: depth + 1,
                              ),
                              if (i < children.length - 1)
                                const SizedBox(height: 7),
                            ],
                          ],
                        ),
                      )
                    : Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 7, left: 9),
                        padding: const EdgeInsets.fromLTRB(7, 8, 7, 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFE6EAF0),
                          ),
                        ),
                        child: Column(
                          children: [
                            for (var i = 0; i < children.length; i++) ...[
                              _buildNode(
                                children[i],
                                byParent,
                                depth: depth + 1,
                              ),
                              if (i < children.length - 1)
                                const SizedBox(height: 7),
                            ],
                          ],
                        ),
                      )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _BrandCategoryRow extends StatelessWidget {
  final CategoryModel category;
  final int depth;
  final bool hasChildren;
  final bool expanded;
  final VoidCallback onTap;

  const _BrandCategoryRow({
    required this.category,
    required this.depth,
    required this.hasChildren,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isRoot = depth == 0;
    final radius = isRoot ? 20.0 : 16.0;
    final iconAssetPath =
        isRoot ? _getIconAssetForCategory(category.name) : null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Ink(
          decoration: BoxDecoration(
            color: isRoot || depth >= 2
                ? Colors.white
                : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: isRoot
                  ? const Color(0xFFE5E7EB)
                  : depth >= 2
                      ? const Color(0xFFE4E9F0)
                      : const Color(0xFFE6EAF0),
            ),
            boxShadow: isRoot
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.025),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : const [],
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isRoot ? 16 : 12,
              vertical: isRoot ? 15 : 12,
            ),
            child: Row(
              children: [
                if (isRoot) ...[
                  Container(
                    width: 58,
                    height: 58,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8EAEA),
                      shape: BoxShape.circle,
                    ),
                    child: iconAssetPath != null
                        ? Padding(
                            padding: const EdgeInsets.all(6),
                            child: Image.asset(
                              iconAssetPath,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(
                                  _getIconForCategory(category.name),
                                  size: 30,
                                  color: AppColors.primary,
                                );
                              },
                            ),
                          )
                        : Icon(
                            _getIconForCategory(category.name),
                            size: 30,
                            color: AppColors.primary,
                          ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    isRoot ? category.name.toUpperCase() : category.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Oswald',
                      fontSize: isRoot ? 16.5 : 13.2,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                      letterSpacing: isRoot ? 0.35 : 0,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: hasChildren && expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: isRoot ? 30 : 22,
                    color: hasChildren
                        ? AppColors.primary
                        : const Color(0xFF9CA3AF),
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

String? _getIconAssetForCategory(String name) {
  final n = _normalizeCategoryName(name);

  if (n.contains('video cctv') ||
      n.contains('cctv hd') ||
      n == 'cctv') {
    return 'assets/images/category_video_cctv.png';
  }

  if (n.contains('video ip') ||
      n.contains('ip hd') ||
      n.contains('cctv ip')) {
    return 'assets/images/category_video_ip.png';
  }

  if (n.contains('complementos') || n.contains('complemento')) {
    return 'assets/images/category_complementos.png';
  }

  if (n.contains('intrusion') ||
      n.contains('alarma') ||
      n.contains('alarmas')) {
    return 'assets/images/category_intrusion.png';
  }

  if (n.contains('acceso') ||
      n.contains('accesos') ||
      n.contains('control acceso')) {
    return 'assets/images/category_accesos.png';
  }

  if (n.contains('incendio') || n.contains('fuego')) {
    return 'assets/images/category_incendio.png';
  }

  if (n.contains('networking') ||
      n.contains('network') ||
      n.contains('redes')) {
    return 'assets/images/category_networking.png';
  }

  if (n.contains('drone') ||
      n.contains('drones') ||
      n.contains('dron')) {
    return 'assets/images/category_drones.png';
  }

  if (n.contains('energia') || n.contains('solar')) {
    return 'assets/images/category_energia.png';
  }

  if (n.contains('antihurto') ||
      n.contains('anti hurto') ||
      n.contains('hurto')) {
    return 'assets/images/category_antihurto.png';
  }

  if (n.contains('outlet')) {
    return 'assets/images/category_outlet.png';
  }

  return null;
}

String _normalizeCategoryName(String name) {
  return name
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

IconData _getIconForCategory(String name) {
  final n = _normalizeCategoryName(name);

  if (n.contains('video ip') || n.contains('ip hd') || n.contains('cctv ip')) {
    return Icons.videocam_rounded;
  }
  if (n.contains('video') || n.contains('cctv')) {
    return Icons.videocam_outlined;
  }
  if (n.contains('intrusion') || n.contains('alarma')) {
    return Icons.sensor_occupied_rounded;
  }
  if (n.contains('incendio') || n.contains('fuego')) {
    return Icons.local_fire_department_rounded;
  }
  if (n.contains('acceso')) {
    return Icons.key_rounded;
  }
  if (n.contains('network') ||
      n.contains('red') ||
      n.contains('wifi') ||
      n.contains('switch') ||
      n.contains('router')) {
    return Icons.router_rounded;
  }
  if (n.contains('antihurto') || n.contains('hurto')) {
    return Icons.security_rounded;
  }
  if (n.contains('complement') || n.contains('accesorio')) {
    return Icons.handyman_rounded;
  }
  if (n.contains('energia') ||
      n.contains('solar') ||
      n.contains('bateria') ||
      n.contains('fuente')) {
    return Icons.battery_charging_full_rounded;
  }
  if (n.contains('drone') || n.contains('dron')) {
    return Icons.flight_rounded;
  }
  if (n.contains('outlet')) {
    return Icons.sell_rounded;
  }

  return Icons.category_rounded;
}

class _BrandCategoriesError extends StatelessWidget {
  final Future<void> Function() onRetry;

  const _BrandCategoriesError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 54,
              color: AppColors.primary,
            ),
            const SizedBox(height: 15),
            const Text(
              'No se pudieron cargar las categorías de la marca',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Oswald',
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => onRetry(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('REINTENTAR'),
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

class _BrandCategoriesEmpty extends StatelessWidget {
  final String brandName;

  const _BrandCategoriesEmpty({
    required this.brandName,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          'No hay categorías con productos de $brandName.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF667085),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

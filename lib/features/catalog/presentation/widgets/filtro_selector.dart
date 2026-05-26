import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mundicam/features/catalog/presentation/providers/filter_provider.dart';
import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/features/catalog/data/models/category_model.dart';
import 'package:mundicam/features/catalog/data/models/producto.dart';
import 'package:mundicam/features/catalog/presentation/pages/productos_por_categoria.dart';
import 'package:mundicam/shared/theme/app_theme.dart';

class FiltroSelector extends ConsumerStatefulWidget {
  final int parentCategoryId;
  final String categoryName;
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

  final Set<int> _expandidas = {};
  final Map<int, List<CategoryModel>> _cache = {};
  final Set<int> _cargando = {};

  String? _ultimaMarca;

  @override
  void initState() {
    super.initState();
    _ultimaMarca = ref.read(productFilterProvider).brand;
    _cargarSubcategorias(widget.parentCategoryId);
  }

  Future<void> _cargarSubcategorias(int categoriaId) async {
    if (_cargando.contains(categoriaId)) return;

    final marcaActual = ref.read(productFilterProvider).brand;
    if (_ultimaMarca != marcaActual) {
      _cache.clear();
      _expandidas.clear();
      _ultimaMarca = marcaActual;
    }

    setState(() => _cargando.add(categoriaId));

    final subs = await _apiService.getSubcategoriasDe(categoriaId);
    final conProductos = subs.where((c) => c.count > 0).toList();

    if (mounted) {
      setState(() {
        _cache[categoriaId] = conProductos;
        _cargando.remove(categoriaId);
      });
    }
  }

  void _toggleCategoria(int categoriaId) {
    setState(() {
      if (_expandidas.contains(categoriaId)) {
        _expandidas.remove(categoriaId);
      } else {
        _expandidas.add(categoriaId);
        _cargarSubcategorias(categoriaId);
      }
    });
  }

  void _irAProductos(CategoryModel cat) {
    ref.read(productFilterProvider.notifier).reset();
    Navigator.pop(context);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ProductosPorCategoriaScreen(
          categoryId: cat.id,
          categoryName: cat.name,
        ),
      ),
    );
  }

  void _limpiarFiltros() {
    ref.read(productFilterProvider.notifier).reset();
    setState(() {
      _cache.clear();
      _expandidas.clear();
      _ultimaMarca = null;
    });
    _cargarSubcategorias(widget.parentCategoryId);
  }

  void _aplicarYCerrar() => Navigator.pop(context);
  void _cerrarDrawer() => Navigator.pop(context);

  void _seleccionarMarca(String marca) {
    final currentBrand = ref.read(productFilterProvider).brand;
    final nuevaMarca = currentBrand == marca ? '' : marca;
    ref.read(productFilterProvider.notifier).update(brand: nuevaMarca);

    setState(() {
      _cache.clear();
      _expandidas.clear();
      _ultimaMarca = nuevaMarca.isNotEmpty ? nuevaMarca : null;
    });

    _cargarSubcategorias(widget.parentCategoryId);
  }

  @override
  Widget build(BuildContext context) {
    final filtroState = ref.watch(productFilterProvider);

    final marcas = widget.productosEnPantalla
        .expand((p) => p.attributes)
        .where((a) => a.name.toLowerCase().contains('marca'))
        .expand((a) => a.options)
        .toSet()
        .toList();
    marcas.sort();

    final raiz = _cache[widget.parentCategoryId] ?? [];

    final productosFiltrados = filtroState.brand.isNotEmpty
        ? widget.productosEnPantalla.where((p) {
      for (final attr in p.attributes) {
        if (attr.name.toLowerCase().contains('marca') &&
            attr.options.any(
                  (o) => o.toLowerCase() == filtroState.brand.toLowerCase(),
            )) {
          return true;
        }
      }
      return false;
    }).toList()
        : widget.productosEnPantalla;

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.88,
      backgroundColor: const Color(0xFFF5F6F8),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _header(filtroState, productosFiltrados.length),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                children: [
                  _sectionCard(
                    title: 'ORDENAR POR',
                    icon: Icons.swap_vert_rounded,
                    child: Column(
                      children: [
                        _buildSortTile('Más recientes', 'date', Icons.access_time_rounded),
                        _buildDivider(),
                        _buildSortTile('Precio: más barato primero', 'price_asc', Icons.trending_up_rounded),
                        _buildDivider(),
                        _buildSortTile('Precio: más caro primero', 'price_desc', Icons.trending_down_rounded),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _sectionCard(
                    title: 'FILTRAR POR MARCA',
                    icon: Icons.sell_outlined,
                    child: marcas.isEmpty
                        ? _emptyInfo('No hay marcas disponibles', Icons.info_outline)
                        : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: marcas.map((m) => _buildMarcaChip(m)).toList(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _sectionCard(
                    title: 'CATEGORÍAS',
                    icon: Icons.category_rounded,
                    subtitle: filtroState.brand.isNotEmpty
                        ? '${productosFiltrados.length} productos de ${filtroState.brand}'
                        : null,
                    child: _cargando.contains(widget.parentCategoryId)
                        ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                        : raiz.isEmpty
                        ? _emptyInfo(
                      filtroState.brand.isNotEmpty
                          ? 'No hay categorías con productos de ${filtroState.brand}'
                          : 'No hay más categorías',
                      Icons.folder_off_outlined,
                    )
                        : Column(children: raiz.map((cat) => _buildNodo(cat, 0)).toList()),
                  ),
                ],
              ),
            ),
            _bottomButtons(productosFiltrados.length),
          ],
        ),
      ),
    );
  }

  Widget _header(dynamic filtroState, int totalFiltrado) {
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
            child: const Icon(Icons.tune_rounded, color: Colors.white, size: 23),
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
                  filtroState.brand.isNotEmpty
                      ? '${widget.categoryName} · ${filtroState.brand}'
                      : widget.categoryName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          if (filtroState.brand.isNotEmpty || filtroState.orderBy != 'date')
            Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$totalFiltrado',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 23),
            onPressed: _cerrarDrawer,
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
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
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
            child: Text(text, style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
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
      onTap: () => ref.read(productFilterProvider.notifier).update(orderBy: value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.07) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: isSelected ? AppColors.primary : const Color(0xFF6B7280)),
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
              const Icon(Icons.check_circle_rounded, size: 21, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(height: 1, thickness: 1, indent: 44, color: Colors.grey.shade200);
  }

  Widget _buildMarcaChip(String marcaNombre) {
    final selectedBrand = ref.watch(productFilterProvider).brand;
    final isSelected = selectedBrand == marcaNombre;

    return GestureDetector(
      onTap: () => _seleccionarMarca(marcaNombre),
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
          ],
        ),
      ),
    );
  }

  Widget _buildNodo(CategoryModel cat, int nivel) {
    final expandida = _expandidas.contains(cat.id);
    final estaCargando = _cargando.contains(cat.id);
    final hijos = _cache[cat.id] ?? [];
    final tieneHijos = hijos.isNotEmpty;
    final puedeTenerHijos = !_cache.containsKey(cat.id) || tieneHijos;

    return Column(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            if (!_cache.containsKey(cat.id)) {
              _toggleCategoria(cat.id);
            } else if (tieneHijos) {
              _toggleCategoria(cat.id);
            } else {
              _irAProductos(cat);
            }
          },
          child: Container(
            margin: EdgeInsets.only(left: nivel == 0 ? 0 : 12.0 * nivel),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: expandida ? AppColors.primary.withValues(alpha: 0.06) : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  expandida
                      ? Icons.folder_open_rounded
                      : (puedeTenerHijos ? Icons.folder_rounded : Icons.inventory_2_outlined),
                  size: 20,
                  color: expandida
                      ? AppColors.primary
                      : (puedeTenerHijos ? AppColors.primary : Colors.grey.shade500),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    cat.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: expandida ? FontWeight.w800 : FontWeight.w600,
                      color: expandida ? AppColors.primary : AppColors.textPrimary,
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
                if (estaCargando)
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                else if (puedeTenerHijos)
                  AnimatedRotation(
                    turns: expandida ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.chevron_right_rounded, size: 21, color: Color(0xFF6B7280)),
                  ),
              ],
            ),
          ),
        ),
        if (expandida && tieneHijos) ...hijos.map((h) => _buildNodo(h, nivel + 1)),
      ],
    );
  }

  Widget _bottomButtons(int totalFiltrado) {
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
                onPressed: _limpiarFiltros,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: Color(0xFFD9DEE7)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: const Text('Restablecer', style: TextStyle(fontWeight: FontWeight.w800)),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Ver productos', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                    const SizedBox(width: 8),
                    Text('($totalFiltrado)', style: const TextStyle(fontSize: 13, color: Colors.white70)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

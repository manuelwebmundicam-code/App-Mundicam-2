import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/filter_provider.dart';
import '../services/api_service.dart';
import '../models/category_model.dart';
import '../models/producto.dart';
import '../pages/productos_por_categoria.dart';
import '../theme.dart';

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

  void _aplicarYCerrar() {
    Navigator.pop(context);
  }

  void _cerrarDrawer() {
    Navigator.pop(context);
  }

  void _seleccionarMarca(String marca) {
    final currentBrand = ref.read(productFilterProvider).brand;
    final nuevaMarca = currentBrand == marca ? "" : marca;
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

    // Marcas disponibles en los productos actuales
    final marcas = widget.productosEnPantalla
        .expand((p) => p.attributes)
        .where((a) => a.name.toLowerCase().contains('marca'))
        .expand((a) => a.options)
        .toSet()
        .toList();
    marcas.sort();

    final raiz = _cache[widget.parentCategoryId] ?? [];

    // Contar productos que coinciden con la marca seleccionada
    final productosFiltrados = filtroState.brand != null && filtroState.brand!.isNotEmpty
        ? widget.productosEnPantalla.where((p) {
      for (final attr in p.attributes) {
        if (attr.name.toLowerCase().contains('marca') &&
            attr.options.any((o) => o.toLowerCase() == filtroState.brand!.toLowerCase())) {
          return true;
        }
      }
      return false;
    }).toList()
        : widget.productosEnPantalla;

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.85,
      child: SafeArea(
        child: Column(children: [
          // ============================================================
          // HEADER PROFESIONAL
          // ============================================================
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
            decoration: BoxDecoration(
              color: AppColors.primary,
              boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.tune_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text("Filtros y ordenación", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17, fontFamily: 'Oswald')),
                  Text(
                    filtroState.brand != null && filtroState.brand!.isNotEmpty
                        ? "${widget.categoryName} · ${filtroState.brand}"
                        : widget.categoryName,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ]),
              ),
              if (filtroState.brand != null && filtroState.brand!.isNotEmpty || filtroState.orderBy != 'date')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    "${productosFiltrados.length}",
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ),
              IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 22), onPressed: _cerrarDrawer),
            ]),
          ),

          // ============================================================
          // CONTENIDO PRINCIPAL
          // ============================================================
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              children: [
                // ----------------------------------------------------------
                // SECCIÓN: ORDENAR POR
                // ----------------------------------------------------------
                _buildSectionHeader(Icons.swap_vert_rounded, "ORDENAR POR"),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(children: [
                    _buildSortTile("Más recientes", "date", Icons.access_time_rounded),
                    _buildDivider(),
                    _buildSortTile("Precio: más barato primero", "price_asc", Icons.trending_up_rounded),
                    _buildDivider(),
                    _buildSortTile("Precio: más caro primero", "price_desc", Icons.trending_down_rounded),
                  ]),
                ),

                const SizedBox(height: 24),

                // ----------------------------------------------------------
                // SECCIÓN: FILTRAR POR MARCA
                // ----------------------------------------------------------
                _buildSectionHeader(Icons.branding_watermark_rounded, "FILTRAR POR MARCA"),
                const SizedBox(height: 8),
                if (marcas.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      Icon(Icons.info_outline, size: 18, color: Colors.grey[400]),
                      const SizedBox(width: 10),
                      const Text("No hay marcas disponibles", style: TextStyle(fontSize: 13, color: Colors.grey)),
                    ]),
                  )
                else
                  Wrap(spacing: 10, runSpacing: 8, children: marcas.map((m) => _buildMarcaChip(m)).toList()),

                const SizedBox(height: 24),

                // ----------------------------------------------------------
                // SECCIÓN: CATEGORÍAS (ÁRBOL EXPANDIBLE)
                // ----------------------------------------------------------
                _buildSectionHeader(Icons.category_rounded, "CATEGORÍAS"),
                const SizedBox(height: 4),
                if (filtroState.brand != null && filtroState.brand!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      "${productosFiltrados.length} productos de ${filtroState.brand}",
                      style: TextStyle(fontSize: 11, color: Colors.grey[500], fontWeight: FontWeight.w500),
                    ),
                  ),
                const SizedBox(height: 4),
                if (_cargando.contains(widget.parentCategoryId))
                  const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(strokeWidth: 2)))
                else if (raiz.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      Icon(Icons.folder_off_outlined, size: 18, color: Colors.grey[400]),
                      const SizedBox(width: 10),
                      Text(
                        filtroState.brand != null && filtroState.brand!.isNotEmpty
                            ? "No hay categorías con productos de ${filtroState.brand}"
                            : "No hay más categorías",
                        style: const TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ]),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(children: raiz.map((cat) => _buildNodo(cat, 0)).toList()),
                  ),
              ],
            ),
          ),

          // ============================================================
          // BOTONES INFERIORES
          // ============================================================
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -2))],
            ),
            child: Row(children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: _limpiarFiltros,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text("Limpiar filtros", style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Text("Aplicar filtros", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(width: 8),
                      Text("(${productosFiltrados.length})", style: const TextStyle(fontSize: 13, color: Colors.white70)),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  // ================================================================
  // WIDGETS
  // ================================================================
  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(children: [
      Icon(icon, size: 16, color: AppColors.primary),
      const SizedBox(width: 8),
      Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.grey[700], letterSpacing: 0.8)),
    ]);
  }

  Widget _buildSortTile(String label, String value, IconData icon) {
    final currentSort = ref.watch(productFilterProvider).orderBy;
    final isSelected = currentSort == value;
    return InkWell(
      onTap: () => ref.read(productFilterProvider.notifier).update(orderBy: value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.05) : Colors.transparent,
          borderRadius: value == "price_desc" ? const BorderRadius.only(bottomLeft: Radius.circular(14), bottomRight: Radius.circular(14)) : null,
        ),
        child: Row(children: [
          Icon(icon, size: 20, color: isSelected ? AppColors.primary : Colors.grey),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(fontSize: 14, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: isSelected ? AppColors.primary : Colors.black87))),
          if (isSelected) const Icon(Icons.check_circle_rounded, size: 22, color: AppColors.primary),
        ]),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(height: 1, thickness: 1, indent: 48, color: Colors.grey.shade200);
  }

  Widget _buildMarcaChip(String marcaNombre) {
    final selectedBrand = ref.watch(productFilterProvider).brand;
    final isSelected = selectedBrand == marcaNombre;
    return GestureDetector(
      onTap: () => _seleccionarMarca(marcaNombre),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? AppColors.primary : Colors.grey.shade300, width: isSelected ? 2 : 1),
          boxShadow: isSelected ? [BoxShadow(color: AppColors.primary.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 2))] : null,
        ),
        child: Text(marcaNombre, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: isSelected ? Colors.white : Colors.black87)),
      ),
    );
  }

  Widget _buildNodo(CategoryModel cat, int nivel) {
    final expandida = _expandidas.contains(cat.id);
    final estaCargando = _cargando.contains(cat.id);
    final hijos = _cache[cat.id] ?? [];
    final tieneHijos = hijos.isNotEmpty;
    final puedeTenerHijos = !_cache.containsKey(cat.id) || tieneHijos;

    return Column(children: [
      InkWell(
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
          padding: EdgeInsets.only(left: 16.0 + (20.0 * nivel), right: 12, top: 12, bottom: 12),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
          child: Row(children: [
            Icon(
              expandida ? Icons.folder_open_rounded : (puedeTenerHijos ? Icons.folder_rounded : Icons.inventory_2_outlined),
              size: 20,
              color: expandida ? AppColors.primary : (puedeTenerHijos ? AppColors.primary : Colors.grey.shade500),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(cat.name, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: expandida ? AppColors.primary : Colors.black87))),
            if (cat.count > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
                child: Text("${cat.count}", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.primary)),
              ),
            if (estaCargando)
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            else if (puedeTenerHijos)
              AnimatedRotation(turns: expandida ? 0.25 : 0, duration: const Duration(milliseconds: 200), child: const Icon(Icons.chevron_right, size: 20, color: Colors.grey)),
          ]),
        ),
      ),
      if (expandida && tieneHijos) ...hijos.map((h) => _buildNodo(h, nivel + 1)),
    ]);
  }
}
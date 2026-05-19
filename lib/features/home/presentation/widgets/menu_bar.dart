import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mundicam/features/company/presentation/pages/empresa_page.dart';
import 'package:mundicam/features/training/presentation/pages/formacion_page.dart';
import 'package:mundicam/features/catalog/presentation/pages/productos_page.dart';
import 'package:mundicam/features/catalog/presentation/pages/productos_por_categoria.dart';
import 'package:mundicam/features/catalog/presentation/providers/category_provider.dart';
import 'package:mundicam/shared/theme/app_theme.dart';

class MenuBarWidget extends ConsumerWidget {
  const MenuBarWidget({super.key});

  void _navigateTo(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => page));
  }

  /// Busca el ID de la categoría Outlet desde las categorías cargadas
  int? _findOutletId(WidgetRef ref) {
    final categoriasAsync = ref.read(categoriesProvider);
    return categoriasAsync.when(
      data: (categorias) {
        final outlet = categorias.where(
          (c) => c.name.toLowerCase().contains('outlet'),
        );
        return outlet.isNotEmpty ? outlet.first.id : null;
      },
      loading: () => null,
      error: (_, __) => null,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 50,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          MenuItem(
            title: "Productos",
            onTap: () => _navigateTo(context, const ProductosPage()),
          ),
          MenuItem(
            title: "Formación",
            onTap: () => _navigateTo(context, FormacionPage()),
          ),
          MenuItem(
            title: "Empresa",
            onTap: () => _navigateTo(context, const EmpresaPage()),
          ),

          // Botón Ofertas → Outlet
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              onPressed: () {
                final outletId = _findOutletId(ref);
                if (outletId != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProductosPorCategoriaScreen(
                        categoryId: outletId,
                        categoryName: "OUTLET",
                      ),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("No se encontró la categoría Outlet"),
                    ),
                  );
                }
              },
              child: const Text(
                "Ofertas",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MenuItem extends StatelessWidget {
  final String title;
  final VoidCallback onTap;

  const MenuItem({super.key, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Center(
          child: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

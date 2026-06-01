import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mundicam/features/company/presentation/pages/empresa_page.dart';
import 'package:mundicam/features/training/presentation/pages/formacion_page.dart';
import 'package:mundicam/features/catalog/presentation/pages/productos_por_categoria.dart';
import 'package:mundicam/features/catalog/presentation/providers/category_provider.dart';
import 'package:mundicam/shared/theme/app_theme.dart';

class MenuBarWidget extends ConsumerWidget {
  const MenuBarWidget({super.key});

  void _navigateTo(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => page));
  }

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
      error: (error, stackTrace) => null,
    );
  }

  void _openOutlet(BuildContext context, WidgetRef ref) {
    final outletId = _findOutletId(ref);

    if (outletId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProductosPorCategoriaScreen(
            categoryId: outletId,
            categoryName: "OFERTAS",
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
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: _MenuPillButton(
              title: 'Formación',
              icon: Icons.school_outlined,
              backgroundColor: Colors.white,
              foregroundColor: AppColors.textPrimary,
              borderColor: const Color(0xFFE1E7EF),
              onTap: () => _navigateTo(context, const FormacionPage()),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MenuPillButton(
              title: 'Empresa',
              icon: Icons.business_outlined,
              backgroundColor: Colors.white,
              foregroundColor: AppColors.textPrimary,
              borderColor: const Color(0xFFE1E7EF),
              onTap: () => _navigateTo(context, const EmpresaPage()),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MenuPillButton(
              title: 'Ofertas',
              icon: Icons.local_offer_outlined,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              borderColor: AppColors.primary,
              onTap: () => _openOutlet(context, ref),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuPillButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color borderColor;
  final VoidCallback onTap;

  const _MenuPillButton({
    required this.title,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.035),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: foregroundColor),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Oswald',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: foregroundColor,
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
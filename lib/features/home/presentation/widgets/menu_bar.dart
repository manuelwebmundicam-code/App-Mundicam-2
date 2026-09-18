import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mundicam/features/catalog/presentation/pages/productos_por_categoria.dart';
import 'package:mundicam/features/catalog/presentation/providers/category_provider.dart';
import 'package:mundicam/features/home/presentation/pages/noticias_page.dart';
import 'package:mundicam/features/training/presentation/pages/academy_page.dart';
import 'package:mundicam/shared/theme/app_theme.dart';

class MenuBarWidget extends ConsumerWidget {
  const MenuBarWidget({super.key});

  void _navigateTo(BuildContext context, Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  Future<int?> _findOutletId(WidgetRef ref) async {
    try {
      final categorias = await ref.read(apiServiceProvider).getCategorias(
        hideEmpty: false,
        parentOnly: false,
      );

      for (final category in categorias) {
        if (category.slug.trim().toLowerCase() == 'zona-outlet') {
          return category.id;
        }
      }
      for (final category in categorias) {
        if (category.name.trim().toLowerCase() == 'outlet') {
          return category.id;
        }
      }
      for (final category in categorias) {
        if (category.name.toLowerCase().contains('outlet')) {
          return category.id;
        }
      }
    } catch (_) {
      final categoriasAsync = ref.read(categoriesProvider);
      return categoriasAsync.when(
        data: (categorias) {
          final outlet =
              categorias.where((c) => c.name.toLowerCase().contains('outlet'));
          return outlet.isNotEmpty ? outlet.first.id : null;
        },
        loading: () => null,
        error: (error, stackTrace) => null,
      );
    }
    return null;
  }

  Future<void> _openOutlet(BuildContext context, WidgetRef ref) async {
    final outletId = await _findOutletId(ref);
    if (!context.mounted) return;

    if (outletId != null) {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ProductosPorCategoriaScreen(
            categoryId: outletId,
            categoryName: 'OUTLET',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se encontró la categoría Outlet'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const buttonBg = Colors.white;
    const buttonFg = AppColors.textPrimary;
    const buttonBorder = Color(0xFFDCE3EA);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: _MenuPillButton(
              title: 'MundiCam Academy',
              icon: Icons.school_outlined,
              backgroundColor: buttonBg,
              foregroundColor: buttonFg,
              borderColor: buttonBorder,
              onTap: () => _navigateTo(
                context,
                const AcademyPage(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: _MenuPillButton(
              title: 'Noticias',
              icon: Icons.article_outlined,
              backgroundColor: buttonBg,
              foregroundColor: buttonFg,
              borderColor: buttonBorder,
              onTap: () => _navigateTo(
                context,
                const NoticiasPage(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: _MenuPillButton(
              title: 'Outlet',
              icon: Icons.local_offer_outlined,
              backgroundColor: buttonBg,
              foregroundColor: buttonFg,
              borderColor: buttonBorder,
              onTap: () => _openOutlet(context, ref),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuPillButton extends StatelessWidget {
  const _MenuPillButton({
    required this.title,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderColor,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color borderColor;
  final VoidCallback onTap;

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
            padding: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.035),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: foregroundColor,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Oswald',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mundicam/features/catalog/presentation/pages/productos_por_categoria.dart';
import 'package:mundicam/features/catalog/presentation/providers/category_provider.dart';
import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/shared/widgets/professional_page_app_bar.dart';

class ProductosPage extends ConsumerStatefulWidget {
  final VoidCallback? onGoHome;
  final VoidCallback? onGoCart;
  final VoidCallback? onGoQuotes;

  const ProductosPage({
    super.key,
    this.onGoHome,
    this.onGoCart,
    this.onGoQuotes,
  });

  @override
  ConsumerState<ProductosPage> createState() => _ProductosPageState();
}

class _ProductosPageState extends ConsumerState<ProductosPage> {
  void _handleBack() {
    if (widget.onGoHome != null) {
      widget.onGoHome!();
      return;
    }

    final navigator = Navigator.of(context);

    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriasAsync = ref.watch(categoriesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: ProfessionalPageAppBar(
        title: 'CATÁLOGO MUNDICAM',
        subtitle: 'Sistemas de Seguridad Electrónica a Profesionales',
        icon: Icons.security_rounded,
        onBack: _handleBack,
      ),
      body: categoriasAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (err, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Error al cargar categorías: $err',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        data: (categorias) {
          if (categorias.isEmpty) {
            return const Center(
              child: Text(
                'No hay categorías disponibles',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(20),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              childAspectRatio: 1.25,
            ),
            itemCount: categorias.length,
            itemBuilder: (context, index) {
              final cat = categorias[index];

              return _CategoryCard(
                cat: cat,
                icon: _getIconForCategory(cat.name),
                onGoCart: widget.onGoCart,
                onGoQuotes: widget.onGoQuotes,
              );
            },
          );
        },
      ),
    );
  }

  IconData _getIconForCategory(String name) {
    final n = name.toLowerCase();

    if (n.contains('video') || n.contains('cctv')) {
      return Icons.videocam_rounded;
    }

    if (n.contains('ip')) {
      return Icons.settings_remote_rounded;
    }

    if (n.contains('antihurto')) {
      return Icons.lock_outline_rounded;
    }

    if (n.contains('complementos')) {
      return Icons.extension_rounded;
    }

    if (n.contains('intrusión') ||
        n.contains('intrusion') ||
        n.contains('alarma')) {
      return Icons.notifications_active_rounded;
    }

    if (n.contains('acceso')) {
      return Icons.badge_rounded;
    }

    if (n.contains('incendio')) {
      return Icons.local_fire_department_rounded;
    }

    if (n.contains('net')) {
      return Icons.hub_outlined;
    }

    if (n.contains('drone')) {
      return Icons.flight_takeoff_rounded;
    }

    if (n.contains('energía') ||
        n.contains('energia') ||
        n.contains('solar')) {
      return Icons.wb_sunny_rounded;
    }

    if (n.contains('outlet')) {
      return Icons.loyalty_rounded;
    }

    return Icons.health_and_safety_rounded;
  }
}

class _CategoryCard extends StatelessWidget {
  final dynamic cat;
  final IconData icon;
  final VoidCallback? onGoCart;
  final VoidCallback? onGoQuotes;

  const _CategoryCard({
    required this.cat,
    required this.icon,
    this.onGoCart,
    this.onGoQuotes,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => ProductosPorCategoriaScreen(
                  categoryId: cat.id,
                  categoryName: cat.name,
                  onGoCart: onGoCart,
                  onGoQuotes: onGoQuotes,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 28,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  cat.name.toString().toUpperCase(),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    letterSpacing: 0.5,
                    color: Color(0xFF2D3142),
                  ),
                ),
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F2F5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${cat.count} Refs',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
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
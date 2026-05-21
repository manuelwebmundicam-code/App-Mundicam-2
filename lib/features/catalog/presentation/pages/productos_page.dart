import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mundicam/features/catalog/presentation/pages/productos_por_categoria.dart';
import 'package:mundicam/features/catalog/presentation/providers/category_provider.dart';
import 'package:mundicam/shared/theme/app_theme.dart';

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
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 64,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: _handleBack,
        ),
        title: const Text(
          'CATÁLOGO MUNDICAM',
          style: TextStyle(
            color: Colors.white,
            fontFamily: 'Oswald',
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        ),
      ),
      body: categoriasAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (err, stack) => _buildErrorState(err),
        data: (categorias) {
          if (categorias.isEmpty) {
            return _buildEmptyState();
          }

          final categoriasOrdenadas = [...categorias]
            ..sort((a, b) {
              final pa = _categoryPriority(a.name.toString());
              final pb = _categoryPriority(b.name.toString());

              if (pa != pb) return pa.compareTo(pb);

              return a.name
                  .toString()
                  .toLowerCase()
                  .compareTo(b.name.toString().toLowerCase());
            });

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async {
              ref.invalidate(categoriesProvider);
            },
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 22),
              itemCount: categoriasOrdenadas.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final cat = categoriasOrdenadas[index];

                return _CategoryRow(
                  cat: cat,
                  icon: _getIconForCategory(cat.name),
                  subtitle: _getSubtitleForCategory(cat.name),
                  onGoCart: widget.onGoCart,
                  onGoQuotes: widget.onGoQuotes,
                );
              },
            ),
          );
        },
      ),
    );
  }

  int _categoryPriority(String name) {
    final n = name.toLowerCase();

    if (n.contains('video ip') || n.contains('ip hd')) return 0;
    if (n.contains('video') || n.contains('cctv')) return 1;
    if (n.contains('intrusión') || n.contains('intrusion') || n.contains('alarma')) {
      return 2;
    }
    if (n.contains('incendio')) return 3;
    if (n.contains('acceso')) return 4;
    if (n.contains('net')) return 5;
    if (n.contains('antihurto')) return 6;
    if (n.contains('complementos')) return 7;
    if (n.contains('energía') || n.contains('energia') || n.contains('solar')) {
      return 8;
    }
    if (n.contains('drone')) return 9;
    if (n.contains('outlet')) return 10;

    return 99;
  }

  String _getSubtitleForCategory(String name) {
    final n = name.toLowerCase();

    if (n.contains('video ip') || n.contains('ip hd')) {
      return 'Cámaras IP, grabadores, analítica y soluciones de vídeo';
    }

    if (n.contains('video') || n.contains('cctv')) {
      return 'Videovigilancia profesional para instalaciones de seguridad';
    }

    if (n.contains('intrusión') || n.contains('intrusion') || n.contains('alarma')) {
      return 'Sistemas de alarma, sensores, centrales y periféricos';
    }

    if (n.contains('incendio')) {
      return 'Detección y prevención de incendios para proyectos técnicos';
    }

    if (n.contains('acceso')) {
      return 'Control de accesos, identificación y gestión de entradas';
    }

    if (n.contains('net')) {
      return 'Networking, conectividad y comunicaciones profesionales';
    }

    if (n.contains('antihurto')) {
      return 'Soluciones EAS y protección antihurto para comercio';
    }

    if (n.contains('complementos')) {
      return 'Accesorios, soportes, alimentación y material auxiliar';
    }

    if (n.contains('energía') || n.contains('energia') || n.contains('solar')) {
      return 'Alimentación, energía solar y soluciones autónomas';
    }

    if (n.contains('drone')) {
      return 'Equipos y soluciones profesionales para escenarios avanzados';
    }

    if (n.contains('outlet')) {
      return 'Referencias disponibles en condiciones especiales';
    }

    return 'Familia de producto profesional MundiCam';
  }

  Widget _buildErrorState(Object err) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                size: 52,
                color: Colors.redAccent,
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Error al cargar el catálogo',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                fontFamily: 'Oswald',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$err',
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF8A8A8A),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            ElevatedButton.icon(
              onPressed: () => ref.invalidate(categoriesProvider),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('REINTENTAR'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.grid_view_rounded,
                size: 62,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 26),
            const Text(
              'No hay categorías disponibles',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                fontFamily: 'Oswald',
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Actualiza el catálogo o revisa la conexión con la web.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF8A8A8A),
                height: 1.4,
              ),
            ),
          ],
        ),
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

class _CategoryRow extends StatelessWidget {
  final dynamic cat;
  final IconData icon;
  final String subtitle;
  final VoidCallback? onGoCart;
  final VoidCallback? onGoQuotes;

  const _CategoryRow({
    required this.cat,
    required this.icon,
    required this.subtitle,
    this.onGoCart,
    this.onGoQuotes,
  });

  @override
  Widget build(BuildContext context) {
    final String name = cat.name.toString().toUpperCase();
    final int count = cat.count is int
        ? cat.count as int
        : int.tryParse(cat.count.toString()) ?? 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
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
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE7E7E7)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: Color(0xFFF8EAEA),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 26,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        letterSpacing: 0.4,
                        color: AppColors.textPrimary,
                        fontFamily: 'Oswald',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF7A7A7A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F2F5),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$count referencias',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF697386),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.grey.shade400,
                size: 26,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
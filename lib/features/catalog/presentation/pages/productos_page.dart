import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
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
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: ProfessionalPageAppBar(
        title: 'CATÁLOGO MUNDICAM',
        subtitle: '',
        icon: Icons.grid_view_rounded,
        onBack: _handleBack,
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

          // v1.9.65: la API ya devuelve las categorías en el orden real de
          // WooCommerce. No imponemos un fallback local que pueda cambiar la web.
          final categoriasOrdenadas = [...categorias];

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async {
              ref.invalidate(categoriesProvider);
            },
            child: GridView.builder(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 22),
              itemCount: categoriasOrdenadas.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.03,
              ),
              itemBuilder: (context, index) {
                final cat = categoriasOrdenadas[index];
                return _CategoryTile(
                  cat: cat,
                  icon: _getIconForCategory(cat.name),
                  iconAssetPath: _getIconAssetForCategory(cat.name),
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
    final n = name
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

    // Fallback de orden principal igual al menú web MundiCam.

    if (n.contains('video cctv') ||
        n.contains('cctv hd') ||
        n.contains('cctv')) {
      return 0;
    }

    if (n.contains('video ip') ||
        n.contains('ip hd') ||
        n.contains('cctv ip')) {
      return 1;
    }

    // Orden exacto del menú web MundiCam:
    // Video CCTV, Video IP, Complementos, Intrusión, Accesos, Incendio,
    // Networking, Drones, Energía, Antihurto, Outlet.
    if (n.contains('complementos') ||
        n.contains('complemento')) {
      return 2;
    }

    if (n.contains('intrusion') ||
        n.contains('alarma') ||
        n.contains('alarmas')) {
      return 3;
    }

    if (n.contains('acceso') ||
        n.contains('accesos') ||
        n.contains('control acceso')) {
      return 4;
    }

    if (n.contains('incendio') ||
        n.contains('fuego') ||
        n.contains('deteccion')) {
      return 5;
    }

    if (n.contains('networking') ||
        n.contains('net') ||
        n.contains('red') ||
        n.contains('wifi') ||
        n.contains('switch') ||
        n.contains('router')) {
      return 6;
    }

    if (n.contains('drone') ||
        n.contains('drones') ||
        n.contains('dron')) {
      return 7;
    }

    if (n.contains('energia') ||
        n.contains('solar') ||
        n.contains('alimentacion') ||
        n.contains('bateria') ||
        n.contains('fuente')) {
      return 8;
    }

    if (n.contains('antihurto') ||
        n.contains('anti hurto') ||
        n.contains('hurto')) {
      return 9;
    }

    if (n.contains('outlet')) {
      return 10;
    }

    return 99;
  }

  String _getSubtitleForCategory(String name) {
    final n = name.toLowerCase();
    if (n.contains('video ip') || n.contains('ip hd')) {
      return 'Cámaras IP y grabadores';
    }
    if (n.contains('video') || n.contains('cctv')) {
      return 'Videovigilancia profesional';
    }
    if (n.contains('intrusión') || n.contains('intrusion') || n.contains('alarma')) {
      return 'Alarmas y sensores';
    }
    if (n.contains('incendio')) {
      return 'Detección y prevención';
    }
    if (n.contains('acceso')) {
      return 'Control de accesos';
    }
    if (n.contains('net')) {
      return 'Redes y conectividad';
    }
    if (n.contains('antihurto')) {
      return 'Protección EAS retail';
    }
    if (n.contains('complementos')) {
      return 'Material auxiliar';
    }
    if (n.contains('energía') || n.contains('energia') || n.contains('solar')) {
      return 'Alimentación y autonomía';
    }
    if (n.contains('drone')) {
      return 'Soluciones profesionales';
    }
    if (n.contains('outlet')) {
      return 'Condiciones especiales';
    }
    return 'Familia profesional';
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

  String? _getIconAssetForCategory(String name) {
    final n = name
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

    if (n.contains('complementos') ||
        n.contains('complemento')) {
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

    if (n.contains('incendio') ||
        n.contains('fuego')) {
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

    if (n.contains('energia') ||
        n.contains('solar')) {
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

  IconData _getIconForCategory(String name) {
    final n = name
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

    if (n.contains('video ip') ||
        n.contains('ip hd') ||
        n.contains('cctv ip')) {
      return Icons.videocam_rounded;
    }

    if (n.contains('video cctv') ||
        n.contains('cctv hd') ||
        n.contains('cctv')) {
      return Symbols.speed_camera_rounded;
    }

    if (n.contains('intrusion') ||
        n.contains('alarma') ||
        n.contains('alarmas')) {
      return Icons.sensor_occupied_rounded;
    }

    if (n.contains('incendio') ||
        n.contains('fuego') ||
        n.contains('deteccion')) {
      return Icons.local_fire_department_rounded;
    }

    if (n.contains('acceso') ||
        n.contains('accesos') ||
        n.contains('control acceso')) {
      return Icons.key_rounded;
    }

    if (n.contains('networking') ||
        n.contains('net') ||
        n.contains('red') ||
        n.contains('wifi') ||
        n.contains('switch') ||
        n.contains('router')) {
      return Icons.router_rounded;
    }

    if (n.contains('antihurto') ||
        n.contains('anti hurto') ||
        n.contains('hurto')) {
      return Icons.security_rounded;
    }

    if (n.contains('complementos') ||
        n.contains('complemento') ||
        n.contains('accesorio') ||
        n.contains('accesorios')) {
      return Icons.handyman_rounded;
    }

    if (n.contains('energia') ||
        n.contains('solar') ||
        n.contains('alimentacion') ||
        n.contains('bateria') ||
        n.contains('fuente')) {
      return Icons.battery_charging_full_rounded;
    }

    if (n.contains('drone') ||
        n.contains('drones') ||
        n.contains('dron')) {
      return Symbols.drone_2_rounded;
    }

    if (n.contains('outlet')) {
      return Icons.sell_rounded;
    }

    return Icons.category_rounded;
  }
}

class _CategoryTile extends StatelessWidget {
  final dynamic cat;
  final IconData icon;
  final String? iconAssetPath;
  final String subtitle;
  final VoidCallback? onGoCart;
  final VoidCallback? onGoQuotes;

  const _CategoryTile({
    required this.cat,
    required this.icon,
    this.iconAssetPath,
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
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE7E7E7)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.032),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 13, 12, 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
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
                            iconAssetPath!,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                          ),
                        )
                      : Icon(
                          icon,
                          size: 30,
                          color: AppColors.primary,
                        ),
                ),
                const SizedBox(height: 10),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 0.45,
                    color: AppColors.textPrimary,
                    fontFamily: 'Oswald',
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.8,
                    height: 1.15,
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
                    '$count refs.',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF697386),
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

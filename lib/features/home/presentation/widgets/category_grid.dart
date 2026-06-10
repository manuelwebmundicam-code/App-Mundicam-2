import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mundicam/features/catalog/data/models/category_model.dart';
import 'package:mundicam/features/catalog/presentation/pages/productos_por_categoria.dart';
import 'package:mundicam/features/catalog/presentation/providers/category_provider.dart';
import 'package:mundicam/shared/theme/app_theme.dart';

class CategoryGrid extends ConsumerWidget {
  final VoidCallback? onGoCart;
  final VoidCallback? onGoQuotes;

  const CategoryGrid({
    super.key,
    this.onGoCart,
    this.onGoQuotes,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return categoriesAsync.when(
      loading: () => const SizedBox(
        height: 200,
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      ),
      error: (error, stack) => const SizedBox(
        height: 100,
        child: Center(
          child: Text('Error al cargar categorías'),
        ),
      ),
      data: (categories) {
        final visibleCategories = categories.take(8).toList();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: visibleCategories.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.6,
            ),
            itemBuilder: (context, index) {
              final category = visibleCategories[index];

              return CategoryCard(
                category: category,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => ProductosPorCategoriaScreen(
                        categoryId: category.id,
                        categoryName: category.name,
                        onGoCart: onGoCart,
                        onGoQuotes: onGoQuotes,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

class CategoryCard extends StatelessWidget {
  final CategoryModel category;
  final VoidCallback onTap;

  const CategoryCard({
    super.key,
    required this.category,
    required this.onTap,
  });

  String _mapNameToAsset(String name) {
    final String n = name.toUpperCase();

    if (n.contains('TARJETA') || n.contains('M2M') || n.contains('WISM')) {
      return 'TARJETAS';
    }

    if (n.contains('CCTV')) return 'CCTV';
    if (n.contains('IP HD')) return 'IP HD';
    if (n.contains('INTRUSION')) return 'INTRUSION';
    if (n.contains('INTRUSIÓN')) return 'INTRUSION';
    if (n.contains('ACCESOS')) return 'ACCESOS';
    if (n.contains('NETWORKING')) return 'NETWORKING';
    if (n.contains('NIEBLA')) return 'NIEBLA DE SEGURIDAD';
    if (n.contains('INCENDIO')) return 'CONTRA INCENDIOS';
    if (n.contains('HURTO')) return 'ANTI HURTO';
    if (n.contains('COMPLEMENTOS')) return 'COMPLEMENTOS';

    return n
        .replaceAll('Ó', 'O')
        .replaceAll('Á', 'A')
        .replaceAll('É', 'E')
        .replaceAll('Í', 'I')
        .replaceAll('Ú', 'U')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final String fileName = _mapNameToAsset(category.name);
    final String assetPath = 'assets/categorias/$fileName.png';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  assetPath,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: Colors.grey[200],
                    child: const Icon(
                      Icons.image_not_supported,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.5, 1.0],
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.85),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 10,
                left: 8,
                right: 8,
                child: Text(
                  category.name.toUpperCase(),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    fontFamily: 'Oswald',
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
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
        final indexedCategories = List.generate(
          categories.length,
              (index) => MapEntry(index, categories[index]),
        ).where((entry) {
          final name = entry.value.name.trim();

          if (name.isEmpty) return false;

          final normalized = _normalizeCategoryName(name);

          if (normalized.contains('outlet')) return false;

          return true;
        }).toList();

        indexedCategories.sort((a, b) {
          final priorityA = _categoryPriority(a.value.name);
          final priorityB = _categoryPriority(b.value.name);

          if (priorityA != priorityB) {
            return priorityA.compareTo(priorityB);
          }

          return a.key.compareTo(b.key);
        });

        final visibleCategories =
        indexedCategories.map((entry) => entry.value).toList();

        if (visibleCategories.isEmpty) {
          return const SizedBox(
            height: 120,
            child: Center(
              child: Text('No hay categorías disponibles'),
            ),
          );
        }

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

  static String _normalizeCategoryName(String value) {
    return value
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
        .replaceAll('ñ', 'n')
        .replaceAll('&amp;', 'y')
        .replaceAll('&', 'y')
        .replaceAll('/', ' ')
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .replaceAll('.', ' ')
        .replaceAll(',', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static int _categoryPriority(String name) {
    final n = _normalizeCategoryName(name);

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

    if (n.contains('intrusion') ||
        n.contains('alarma') ||
        n.contains('alarmas')) {
      return 2;
    }

    if (n.contains('acceso') ||
        n.contains('accesos') ||
        n.contains('control acceso')) {
      return 3;
    }

    return 99;
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

  String _normalize(String value) {
    return value
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
        .replaceAll('ñ', 'n')
        .replaceAll('&amp;', 'y')
        .replaceAll('&', 'y')
        .replaceAll('/', ' ')
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .replaceAll('.', ' ')
        .replaceAll(',', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  String _slugUpper(String value) {
    return _normalize(value)
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<String> _assetCandidates(String categoryName) {
    final n = _normalize(categoryName);
    final slugUpper = _slugUpper(categoryName);

    final candidates = <String>[];

    void addExact(String path) {
      candidates.add(path);
    }

    void addFile(String fileName) {
      final names = <String>{
        fileName,
        fileName.toUpperCase(),
        fileName.toLowerCase(),
      };

      for (final name in names) {
        candidates.add('assets/categorias/$name.png');
        candidates.add('assets/categorias/$name.jpg');
        candidates.add('assets/categorias/$name.jpeg');
      }
    }

    if (n.contains('video ip') ||
        n.contains('ip hd') ||
        n.contains('cctv ip')) {
      addFile('IP HD');
      addFile('CCTV');
    }

    if (n.contains('video cctv') ||
        n.contains('cctv hd') ||
        n.contains('cctv') ||
        n.contains('camara') ||
        n.contains('camaras') ||
        n.contains('video') ||
        n.contains('hd') ||
        n.contains('ip')) {
      addFile('CCTV');
    }

    if (n.contains('intrusion') ||
        n.contains('alarma') ||
        n.contains('alarmas')) {
      addFile('INTRUSION');
    }

    if (n.contains('acceso') ||
        n.contains('accesos') ||
        n.contains('control acceso')) {
      addFile('ACCESOS');
    }

    if (n.contains('networking') ||
        n.contains('red') ||
        n.contains('wifi') ||
        n.contains('switch') ||
        n.contains('router')) {
      addFile('NETWORKING');
    }

    if (n.contains('incendio') ||
        n.contains('fuego') ||
        n.contains('deteccion')) {
      addFile('CONTRA INCENDIOS');
    }

    if (n.contains('hurto') ||
        n.contains('antihurto') ||
        n.contains('anti hurto')) {
      addFile('ANTI HURTO');
    }

    if (n.contains('niebla')) {
      addFile('NIEBLA DE SEGURIDAD');
    }

    if (n.contains('m2m') ||
        n.contains('iot') ||
        n.contains('sim') ||
        n.contains('tarjeta') ||
        n.contains('tarjetas') ||
        n.contains('wisim')) {
      addFile('TARJETAS');
    }

    if (n.contains('drone') ||
        n.contains('drones') ||
        n.contains('dron')) {
      addExact('assets/categorias/drones.png');
      addFile('DRONES');
    }

    if (n.contains('energia') ||
        n.contains('alimentacion') ||
        n.contains('solar') ||
        n.contains('bateria') ||
        n.contains('baterias') ||
        n.contains('fuente') ||
        n.contains('fuentes')) {
      addExact('assets/categorias/energia.png');
      addFile('ENERGÍA');
      addFile('ENERGIA');
    }

    if (n.contains('complemento') ||
        n.contains('complementos') ||
        n.contains('accesorio') ||
        n.contains('accesorios') ||
        n.contains('soporte') ||
        n.contains('caja')) {
      addFile('COMPLEMENTOS');
    }

    addFile(slugUpper);

    return candidates.toSet().toList();
  }

  @override
  Widget build(BuildContext context) {
    final assetCandidates = _assetCandidates(category.name);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
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
                child: _CategoryAssetImage(
                  candidates: assetCandidates,
                ),
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.45, 1.0],
                      colors: [
                        Colors.black.withOpacity(0.04),
                        Colors.black.withOpacity(0.85),
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
                    height: 1.1,
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

class _CategoryAssetImage extends StatefulWidget {
  final List<String> candidates;

  const _CategoryAssetImage({
    required this.candidates,
  });

  @override
  State<_CategoryAssetImage> createState() => _CategoryAssetImageState();
}

class _CategoryAssetImageState extends State<_CategoryAssetImage> {
  int _index = 0;

  @override
  void didUpdateWidget(covariant _CategoryAssetImage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.candidates.join('|') != widget.candidates.join('|')) {
      _index = 0;
    }
  }

  void _tryNextImage() {
    if (!mounted) return;

    if (_index < widget.candidates.length - 1) {
      setState(() {
        _index++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.candidates.isEmpty) {
      return _fallback();
    }

    final path = widget.candidates[_index];

    return Image.asset(
      path,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        if (_index < widget.candidates.length - 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _tryNextImage();
          });

          return _loadingFallback();
        }

        return _fallback();
      },
    );
  }

  Widget _loadingFallback() {
    return Container(
      color: const Color(0xFFE5E7EB),
    );
  }

  Widget _fallback() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1F2937),
            Color(0xFF111827),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.category_outlined,
          size: 42,
          color: Colors.white.withOpacity(0.65),
        ),
      ),
    );
  }
}
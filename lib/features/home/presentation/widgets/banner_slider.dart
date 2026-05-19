import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mundicam/features/home/data/models/banner_mix.dart';
import 'package:mundicam/features/home/presentation/providers/banner_mix_provider.dart';

class BannerMix extends ConsumerStatefulWidget {
  const BannerMix({super.key});

  @override
  ConsumerState<BannerMix> createState() => _BannerMixState();
}

class _BannerMixState extends ConsumerState<BannerMix> {
  PageController? _controller;
  Timer? _timer;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // Inicializamos el controller con un número alto para permitir scroll infinito hacia ambos lados
    _controller = PageController(initialPage: 1000, viewportFraction: 0.92);
    _startAutoScroll();
  }

  void _startAutoScroll() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_controller != null && _controller!.hasClients) {
        _controller!.nextPage(
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final mixAsync = ref.watch(bannerMixProvider);
    final theme = Theme.of(context);

    return mixAsync.when(
      loading: () => _buildLoadingShimmer(theme),
      error: (err, _) => const SizedBox.shrink(),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();

        // IMPORTANTE: Eliminamos la lógica de _items locales para que el
        // PageView siempre use lo último que devuelva el provider.
        return Column(
          children: [
            SizedBox(
              height: 200,
              child: PageView.builder(
                // La Key asegura que el widget se reconstruya si la lista cambia de tamaño
                key: ValueKey('banner_pv_${items.length}'),
                controller: _controller,
                onPageChanged: (index) => setState(() => _currentIndex = index),
                itemBuilder: (context, index) {
                  final item = items[index % items.length];
                  return _buildBannerCard(item, theme);
                },
              ),
            ),
            const SizedBox(height: 12),
            _buildPageIndicator(items.length, theme),
          ],
        );
      },
    );
  }

  /// Gestiona la carga de imagen desde Asset o desde URL
  Widget _buildImageHandler(String path, Color tagColor, ThemeData theme) {
    if (path.startsWith('assets/')) {
      return Image.asset(
        path,
        fit: BoxFit.cover,
        errorBuilder: (c, e, s) => _buildInternalDesign(tagColor),
      );
    } else if (path.startsWith('http')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        // Shimmer o placeholder mientras carga la imagen de red
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: Colors.grey.shade200,
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
        errorBuilder: (c, e, s) => _buildInternalDesign(tagColor),
      );
    } else {
      return _buildInternalDesign(tagColor);
    }
  }

  Widget _buildBannerCard(BannerMixModel item, ThemeData theme) {
    final String titleUpper = item.title?.toUpperCase() ?? "";

    Color tagColor = theme.primaryColor;
    String tagText = "NOVEDAD";

    // Lógica de etiquetas dinámica
    if (titleUpper.contains("OFERTA")) {
      tagColor = const Color(0xFFE65100);
      tagText = "OFERTA";
    } else if (titleUpper.contains("UNIDADES") ||
        titleUpper.contains("OUTLET")) {
      tagColor = theme.hintColor;
      tagText = "OUTLET";
    } else if (titleUpper.contains("VENDIDOS")) {
      tagColor = const Color(0xFF1B5E20);
      tagText = "TOP VENTAS";
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: _buildImageHandler(item.image, tagColor, theme),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.85),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: tagColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                tagText,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 15,
            left: 15,
            right: 15,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title ?? '',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontSize: 22,
                    fontFamily: 'Oswald',
                    height: 1.1,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.subtitle != null && item.subtitle!.isNotEmpty)
                  Padding(
                    // CAMBIO: .top(4.0) -> .only(top: 4.0)
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      item.subtitle!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                        fontFamily: 'Oswald',
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageIndicator(int count, ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final bool isSelected = (_currentIndex % count) == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          height: 5,
          width: isSelected ? 20 : 5,
          decoration: BoxDecoration(
            color: isSelected ? theme.primaryColor : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(5),
          ),
        );
      }),
    );
  }

  Widget _buildInternalDesign(Color accentColor) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accentColor.withValues(alpha: 0.7), accentColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.security, size: 80, color: Colors.white12),
      ),
    );
  }

  Widget _buildLoadingShimmer(ThemeData theme) {
    return Container(
      height: 200,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: CircularProgressIndicator(
          color: theme.primaryColor,
          strokeWidth: 2,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:mundicam/features/home/presentation/providers/noticias_provider.dart';
import 'package:mundicam/shared/theme/app_theme.dart';

class NewsBanner extends ConsumerStatefulWidget {
  const NewsBanner({super.key});

  @override
  ConsumerState<NewsBanner> createState() => _NewsBannerState();
}

class _NewsBannerState extends ConsumerState<NewsBanner> {
  final PageController _pageController = PageController(viewportFraction: 0.92);

  Timer? _autoTimer;
  int _currentIndex = 0;
  int _newsCount = 0;
  bool _isUserDragging = false;

  static const Duration _autoSlideDuration = Duration(seconds: 7);

  @override
  void initState() {
    super.initState();
    _startAutoSlide();
  }

  void _startAutoSlide() {
    _autoTimer?.cancel();

    _autoTimer = Timer.periodic(_autoSlideDuration, (_) {
      if (!mounted) return;
      if (!_pageController.hasClients) return;
      if (_isUserDragging) return;
      if (_newsCount <= 1) return;

      final nextIndex = _currentIndex >= _newsCount - 1 ? 0 : _currentIndex + 1;

      _pageController.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _openUrl(String url) async {
    if (url.trim().isEmpty) return;

    final uri = Uri.parse(url);

    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      debugPrint('No se pudo abrir la noticia: $url');
    }
  }

  String _formatDate(String rawDate) {
    if (rawDate.isEmpty) return '';

    try {
      final date = DateTime.parse(rawDate);

      return '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.year}';
    } catch (_) {
      return rawDate;
    }
  }

  String _cleanTitle(String text) {
    return text
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#8211;', '–')
        .replaceAll('&#8217;', '’')
        .replaceAll('&nbsp;', ' ')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final noticiasAsync = ref.watch(noticiasProvider);

    return SizedBox(
      height: 228,
      child: noticiasAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (error, stack) => _buildEmptyState(
          'No se pudieron cargar las noticias',
        ),
        data: (noticias) {
          final visibleNoticias = noticias.take(7).toList();
          _newsCount = visibleNoticias.length;

          if (_currentIndex >= _newsCount && _newsCount > 0) {
            _currentIndex = 0;
          }

          if (visibleNoticias.isEmpty) {
            return _buildEmptyState('No hay noticias disponibles');
          }

          return Column(
            children: [
              SizedBox(
                height: 190,
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollStartNotification) {
                      _isUserDragging = true;
                    }

                    if (notification is ScrollEndNotification) {
                      _isUserDragging = false;
                    }

                    return false;
                  },
                  child: PageView.builder(
                    controller: _pageController,
                    physics: const BouncingScrollPhysics(),
                    itemCount: visibleNoticias.length,
                    onPageChanged: (index) {
                      setState(() {
                        _currentIndex = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      final item = visibleNoticias[index];

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => _openUrl(item.link),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: item.imagenUrl.isNotEmpty
                                      ? CachedNetworkImage(
                                    imageUrl: item.imagenUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) =>
                                        Container(
                                          color: Colors.grey.shade200,
                                          child: const Center(
                                            child: CircularProgressIndicator(
                                              color: AppColors.primary,
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        ),
                                    errorWidget: (context, url, error) =>
                                        _buildImageFallback(),
                                  )
                                      : _buildImageFallback(),
                                ),
                                Positioned.fill(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.black.withOpacity(0.03),
                                          Colors.black.withOpacity(0.84),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: 16,
                                  right: 16,
                                  bottom: 18,
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _formatDate(item.fecha),
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _cleanTitle(item.titulo),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontFamily: 'Oswald',
                                          fontSize: 16,
                                          height: 1.16,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 13),
              _buildDots(visibleNoticias.length),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDots(int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final selected = _currentIndex == index;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: selected ? 18 : 7,
          height: 7,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : const Color(0xFFD1D5DB),
            borderRadius: BorderRadius.circular(20),
          ),
        );
      }),
    );
  }

  Widget _buildImageFallback() {
    return Container(
      color: Colors.grey.shade200,
      child: const Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          color: Colors.grey,
          size: 34,
        ),
      ),
    );
  }

  Widget _buildEmptyState(String text) {
    return Container(
      height: 180,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE1E7EF)),
      ),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }
}
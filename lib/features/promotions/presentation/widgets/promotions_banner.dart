import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mundicam/features/promotions/presentation/pages/promotions_page.dart';
import 'package:mundicam/features/promotions/presentation/providers/promotions_provider.dart';
import 'package:mundicam/shared/theme/app_theme.dart';

class PromotionsBanner extends ConsumerStatefulWidget {
  const PromotionsBanner({super.key});

  @override
  ConsumerState<PromotionsBanner> createState() => _PromotionsBannerState();
}

class _PromotionsBannerState extends ConsumerState<PromotionsBanner> {
  final PageController _controller = PageController(viewportFraction: 0.96);
  Timer? _timer;
  int _index = 0;
  int _count = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!mounted || !_controller.hasClients || _dragging || _count <= 1) {
        return;
      }
      final next = _index >= _count - 1 ? 0 : _index + 1;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncPromotions = ref.watch(promotionsProvider);

    return SizedBox(
      height: 326,
      child: asyncPromotions.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (_, __) => _empty('No se pudieron cargar las promociones'),
        data: (promotions) {
          final visible = promotions.take(7).toList();
          _count = visible.length;
          if (_count == 0) return _empty('No hay promociones activas');
          if (_index >= _count) _index = 0;

          return Column(
            children: [
              SizedBox(
                height: 288,
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollStartNotification) {
                      _dragging = true;
                    } else if (notification is ScrollEndNotification) {
                      _dragging = false;
                    }
                    return false;
                  },
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: visible.length,
                    onPageChanged: (value) => setState(() => _index = value),
                    itemBuilder: (context, index) {
                      final item = visible[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const PromotionsPage(),
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: ColoredBox(
                              color: Colors.white,
                              child: Column(
                                children: [
                                  Expanded(
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: item.imageUrl.isNotEmpty
                                          ? CachedNetworkImage(
                                              imageUrl: item.imageUrl,
                                              fit: BoxFit.contain,
                                              alignment: Alignment.center,
                                              filterQuality: FilterQuality.high,
                                              placeholder: (_, __) => _imageFallback(),
                                              errorWidget: (_, __, ___) => _imageFallback(),
                                            )
                                          : _imageFallback(),
                                    ),
                                  ),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                                    color: Colors.white,
                                    child: Text(
                                      item.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFF111827),
                                        fontFamily: 'Oswald',
                                        fontSize: 15.5,
                                        height: 1.14,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 13),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_count, (dotIndex) {
                  final active = dotIndex == _index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: active ? 18 : 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.primary
                          : const Color(0xFFD1D5DB),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  );
                }),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _empty(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _imageFallback() {
    return Container(
      color: const Color(0xFFE9EDF2),
      alignment: Alignment.center,
      child: const Icon(
        Icons.local_offer_outlined,
        size: 42,
        color: Color(0xFF9CA3AF),
      ),
    );
  }
}

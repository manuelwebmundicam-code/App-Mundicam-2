import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/features/promotions/data/models/promotion_model.dart';
import 'package:mundicam/features/promotions/presentation/providers/promotions_provider.dart';
import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/shared/widgets/mundicam_webview_page.dart';
import 'package:mundicam/shared/widgets/professional_page_app_bar.dart';

class PromotionsPage extends ConsumerWidget {
  const PromotionsPage({super.key});

  Future<void> _openPromotion(
    BuildContext context,
    PromotionModel promotion,
  ) async {
    final messenger = ScaffoldMessenger.of(context);

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 12),
        content: Text('Abriendo promoción en MundiCam…'),
      ),
    );

    final uri = await ApiService().resolvePromotionWebUri(promotion);

    if (!context.mounted) return;

    messenger.hideCurrentSnackBar();

    if (uri == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'No se ha encontrado la página web de esta promoción.',
          ),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MundiCamWebViewPage(
          title: 'PROMOCIÓN',
          initialUri: uri,
          closeOnBack: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promotionsAsync = ref.watch(promotionsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: ProfessionalPageAppBar(
        title: 'PROMOCIONES',
        onBack: () => Navigator.of(context).maybePop(),
        onRefresh: () => ref.invalidate(promotionsProvider),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          ref.invalidate(promotionsProvider);
          await ref.read(promotionsProvider.future);
        },
        child: promotionsAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
          error: (_, __) => _messageList(
            icon: Icons.cloud_off_rounded,
            message: 'No se pudieron cargar las promociones.',
          ),
          data: (promotions) {
            if (promotions.isEmpty) {
              return _messageList(
                icon: Icons.local_offer_outlined,
                message: 'No hay promociones activas ahora mismo.',
              );
            }

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
              itemCount: promotions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                final promotion = promotions[index];

                return _PromotionCard(
                  promotion: promotion,
                  onTap: () => _openPromotion(context, promotion),
                );
              },
            );
          },
        ),
      ),
    );
  }

  static Widget _messageList({
    required IconData icon,
    required String message,
  }) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 80),
      children: [
        Icon(icon, size: 42, color: const Color(0xFF9CA3AF)),
        const SizedBox(height: 14),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _PromotionCard extends StatelessWidget {
  const _PromotionCard({
    required this.promotion,
    required this.onTap,
  });

  final PromotionModel promotion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Abrir promoción ${promotion.title}',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE4E7EC)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: 150,
              maxHeight: 520,
            ),
            child: SizedBox(
              width: double.infinity,
              child: promotion.imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: promotion.imageUrl,
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                      filterQuality: FilterQuality.high,
                      placeholder: (_, __) => const SizedBox(
                        height: 190,
                        child: _ImagePlaceholder(),
                      ),
                      errorWidget: (_, __, ___) => const SizedBox(
                        height: 190,
                        child: _ImagePlaceholder(),
                      ),
                    )
                  : const SizedBox(
                      height: 190,
                      child: _ImagePlaceholder(),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 15),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.local_offer_outlined,
                  color: AppColors.primary,
                  size: 18,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    promotion.title,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontFamily: 'Oswald',
                      fontSize: 17,
                      height: 1.18,
                      fontWeight: FontWeight.w800,
                    ),
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
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF0F2F5),
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_outlined,
        color: Color(0xFF9CA3AF),
        size: 38,
      ),
    );
  }
}

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mundicam/features/mundicam_content/domain/models/mundicam_news_item.dart';
import 'package:mundicam/features/mundicam_content/presentation/providers/mundicam_content_provider.dart';
import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/shared/widgets/professional_page_app_bar.dart';

const Color _pageBg = Color(0xFFF4F7FB);
const Color _dark = Color(0xFF111827);
const Color _muted = Color(0xFF667085);
const Color _border = Color(0xFFE3E8EF);

class MundicamNewsPage extends ConsumerWidget {
  const MundicamNewsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncNews = ref.watch(mundicamNewsProvider);

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: ProfessionalPageAppBar(
        title: 'NOTICIAS',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: asyncNews.when(
        loading: () => const Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
          ),
        ),
        error: (_, __) => _ErrorState(
          onRetry: () => ref.invalidate(mundicamNewsProvider),
        ),
        data: (news) {
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async {
              ref.invalidate(mundicamNewsProvider);
              await ref.read(mundicamNewsProvider.future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                if (news.isEmpty)
                  const _EmptyState()
                else
                  ...news.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _NewsCard(
                        item: item,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => MundicamNewsDetailPage(
                              item: item,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class MundicamNewsDetailPage extends StatelessWidget {
  const MundicamNewsDetailPage({
    super.key,
    required this.item,
  });

  final MundicamNewsItem item;

  @override
  Widget build(BuildContext context) {
    final body = item.content.isNotEmpty
        ? item.content
        : item.excerpt;

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: ProfessionalPageAppBar(
        title: 'NOTICIA',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
        children: [
          if (item.imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: CachedNetworkImage(
                  imageUrl: item.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => const _ImageFallback(),
                  errorWidget: (_, __, ___) =>
                      const _ImageFallback(),
                ),
              ),
            ),
          if (item.imageUrl.isNotEmpty)
            const SizedBox(height: 18),
          Text(
            item.title,
            style: const TextStyle(
              color: _dark,
              fontFamily: 'Oswald',
              fontSize: 25,
              height: 1.08,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (item.publishedDate.isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(
              _formatDate(item.publishedDate),
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _border),
            ),
            child: Text(
              body.isNotEmpty
                  ? body
                  : 'Esta noticia no contiene texto adicional.',
              style: const TextStyle(
                color: _dark,
                fontSize: 14,
                height: 1.58,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NewsCard extends StatelessWidget {
  const _NewsCard({
    required this.item,
    required this.onTap,
  });

  final MundicamNewsItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 8.5,
                child: item.imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: item.imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            const _ImageFallback(),
                        errorWidget: (_, __, ___) =>
                            const _ImageFallback(),
                      )
                    : const _ImageFallback(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  15,
                  13,
                  15,
                  15,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.publishedDate.isNotEmpty)
                      Text(
                        _formatDate(item.publishedDate),
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (item.publishedDate.isNotEmpty)
                      const SizedBox(height: 7),
                    Text(
                      item.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _dark,
                        fontFamily: 'Oswald',
                        fontSize: 19,
                        height: 1.12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (item.excerpt.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        item.excerpt,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 12.5,
                          height: 1.42,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Row(
                      children: [
                        Text(
                          'LEER NOTICIA',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontFamily: 'Oswald',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(width: 5),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: AppColors.primary,
                          size: 18,
                        ),
                      ],
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

class _ImageFallback extends StatelessWidget {
  const _ImageFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF1F3F5),
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_outlined,
        color: Color(0xFF98A2B3),
        size: 35,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Text(
          'No hay noticias disponibles.',
          style: TextStyle(
            color: _muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('REINTENTAR'),
      ),
    );
  }
}

String _formatDate(String raw) {
  if (raw.isEmpty) return '';

  try {
    final date = DateTime.parse(raw);
    const months = <String>[
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];

    return '${date.day} de ${months[date.month - 1]} de ${date.year}';
  } catch (_) {
    return raw;
  }
}

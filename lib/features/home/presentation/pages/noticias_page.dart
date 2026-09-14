import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mundicam/features/home/data/models/noticia.dart';
import 'package:mundicam/features/home/presentation/providers/noticias_provider.dart';
import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/shared/widgets/professional_page_app_bar.dart';

const Color _pageBg = Color(0xFFF4F7FB);
const Color _dark = Color(0xFF111827);
const Color _muted = Color(0xFF667085);
const Color _border = Color(0xFFE3E8EF);

class NoticiasPage extends ConsumerStatefulWidget {
  const NoticiasPage({super.key});

  @override
  ConsumerState<NoticiasPage> createState() => _NoticiasPageState();
}

class _NoticiasPageState extends ConsumerState<NoticiasPage> {
  @override
  void initState() {
    super.initState();

    Future<void>.microtask(() {
      if (!mounted) return;
      ref.read(noticiasProvider.notifier).refreshSilently();
    });
  }

  @override
  Widget build(BuildContext context) {
    final noticiasAsync = ref.watch(noticiasProvider);

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: ProfessionalPageAppBar(
        title: 'NOTICIAS',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: noticiasAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (error, stack) => _ErrorState(
          onRetry: () => ref.read(noticiasProvider.notifier).retry(),
        ),
        data: (noticias) {
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () =>
                ref.read(noticiasProvider.notifier).refreshFromPull(),
            child: noticias.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: ClampingScrollPhysics(),
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    children: const [
                      _EmptyState(),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: ClampingScrollPhysics(),
                    ),
                    padding: const EdgeInsets.fromLTRB(14, 16, 14, 30),
                    itemCount: noticias.length,
                    itemBuilder: (context, index) {
                      final noticia = noticias[index];

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 22),
                        child: _NewsCard(
                          noticia: noticia,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => NoticiaDetallePage(
                                noticia: noticia,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
}

class NoticiaDetallePage extends StatelessWidget {
  const NoticiaDetallePage({
    super.key,
    required this.noticia,
  });

  final Noticia noticia;

  @override
  Widget build(BuildContext context) {
    final body = noticia.contenido.trim().isNotEmpty
        ? noticia.contenido.trim()
        : noticia.resumen.trim();

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: ProfessionalPageAppBar(
        title: 'NOTICIA',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
        children: [
          if (noticia.imagenUrl.trim().isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: CachedNetworkImage(
                imageUrl: noticia.imagenUrl,
                width: double.infinity,
                fit: BoxFit.fitWidth,
                alignment: Alignment.topCenter,
                placeholder: (_, __) => const AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _ImagePlaceholder(),
                ),
                errorWidget: (_, __, ___) => const AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _ImagePlaceholder(),
                ),
              ),
            ),
          if (noticia.imagenUrl.trim().isNotEmpty)
            const SizedBox(height: 18),
          Text(
            noticia.titulo,
            style: const TextStyle(
              color: _dark,
              fontFamily: 'Oswald',
              fontSize: 25,
              height: 1.08,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                color: AppColors.primary,
                size: 15,
              ),
              const SizedBox(width: 7),
              Text(
                _formatDate(noticia.fecha),
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.fromLTRB(17, 17, 17, 19),
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
    required this.noticia,
    required this.onTap,
  });

  final Noticia noticia;
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
              noticia.imagenUrl.trim().isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: noticia.imagenUrl,
                      width: double.infinity,
                      fit: BoxFit.fitWidth,
                      alignment: Alignment.topCenter,
                      fadeInDuration: const Duration(milliseconds: 120),
                      placeholder: (_, __) => const AspectRatio(
                        aspectRatio: 16 / 9,
                        child: _ImagePlaceholder(),
                      ),
                      errorWidget: (_, __, ___) => const AspectRatio(
                        aspectRatio: 16 / 9,
                        child: _ImagePlaceholder(),
                      ),
                    )
                  : const AspectRatio(
                      aspectRatio: 16 / 9,
                      child: _ImagePlaceholder(),
                    ),
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 13, 15, 15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatDate(noticia.fecha),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      noticia.titulo,
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
                    if (noticia.resumen.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        noticia.resumen,
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

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF1F3F5),
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_outlined,
        size: 35,
        color: Color(0xFF98A2B3),
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
  if (raw.trim().isEmpty) return '';

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

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mundicam/core/network/mundicam_content_service.dart';

import 'package:mundicam/features/training/data/models/cursos_model.dart';
import 'package:mundicam/features/training/presentation/providers/academy_provider.dart';
import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/shared/widgets/mundicam_webview_page.dart';
import 'package:mundicam/shared/widgets/professional_page_app_bar.dart';

const Color _pageBg = Color(0xFFF4F7FB);
const Color _dark = Color(0xFF111827);
const Color _muted = Color(0xFF667085);
const Color _border = Color(0xFFE3E8EF);

const Map<String, String> _academyImageHeaders = <String, String>{
  'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
  'User-Agent': 'MundiCam-App/Public-Content',
  'Referer': 'https://www.mundicam.com/academy/',
};

final MundicamContentService _academyImageService = MundicamContentService();

final _academyPageFallbackImageProvider =
    FutureProvider.autoDispose.family<String, String>((ref, pageUrl) async {
  final cleanUrl = pageUrl.trim();
  if (cleanUrl.isEmpty) return '';
  return _academyImageService.getAcademyPageImage(cleanUrl);
});


class AcademyPage extends ConsumerStatefulWidget {
  const AcademyPage({super.key});

  @override
  ConsumerState<AcademyPage> createState() => _AcademyPageState();
}

class _AcademyPageState extends ConsumerState<AcademyPage> {
  late DateTime _visibleMonth;
  DateTime? _selectedDay;
  final Set<String> _prefetchedAcademyImages = <String>{};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);

    Future<void>.microtask(() {
      if (!mounted) return;
      ref.read(academyProvider.notifier).refreshSilently();
    });
  }

  void _previousMonth() {
    setState(() {
      _visibleMonth = DateTime(
        _visibleMonth.year,
        _visibleMonth.month - 1,
      );
      _selectedDay = null;
    });

    ref.read(academyProvider.notifier).refreshSilently();
  }

  void _nextMonth() {
    setState(() {
      _visibleMonth = DateTime(
        _visibleMonth.year,
        _visibleMonth.month + 1,
      );
      _selectedDay = null;
    });

    ref.read(academyProvider.notifier).refreshSilently();
  }

  void _openRegistration(BuildContext context, CourseModel course) {
    final uri = Uri.tryParse(course.url.trim());

    if (uri == null || !uri.hasScheme) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La inscripción no está disponible para este evento.',
          ),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MundiCamWebViewPage(
          title: 'INSCRIPCIÓN ACADEMY',
          initialUri: uri,
          closeOnBack: true,
        ),
      ),
    );
  }

  void _prefetchFirstAcademyImages(List<CourseModel> courses) {
    final urls = courses
        .map((course) => course.imageUrl.trim())
        .where((url) =>
            url.isNotEmpty &&
            (url.startsWith('https://') || url.startsWith('http://')))
        .where((url) => !_prefetchedAcademyImages.contains(url))
        .take(4)
        .toList(growable: false);

    if (urls.isEmpty) return;

    _prefetchedAcademyImages.addAll(urls);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      for (final imageUrl in urls) {
        precacheImage(
          CachedNetworkImageProvider(
            imageUrl,
            headers: _academyImageHeaders,
          ),
          context,
        ).catchError((_) {
          // Si una imagen directa falla, la tarjeta conserva el fallback
          // a la página pública real del evento.
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final academyAsync = ref.watch(academyProvider);

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: ProfessionalPageAppBar(
        title: 'MUNDICAM ACADEMY',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: academyAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (error, stack) => _AcademyError(
          onRetry: () => ref.read(academyProvider.notifier).retry(),
        ),
        data: (courses) {
          _prefetchFirstAcademyImages(courses);

          final visibleCourses = _selectedDay == null
              ? courses
              : courses.where((course) {
                  final date = course.eventDate;
                  return date != null &&
                      _sameDay(date, _selectedDay!);
                }).toList();

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () =>
                ref.read(academyProvider.notifier).refreshFromPull(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate.fixed([
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text(
                          'PRÓXIMOS EVENTOS IMPORTANTES EN MUNDICAM ACADEMY',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'Oswald',
                            fontSize: 17,
                            height: 1.05,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _AcademyCalendar(
                        visibleMonth: _visibleMonth,
                        courses: courses,
                        selectedDay: _selectedDay,
                        onPrevious: _previousMonth,
                        onNext: _nextMonth,
                        onDaySelected: (date) {
                          final hasEvents = courses.any(
                            (course) =>
                                course.eventDate != null &&
                                _sameDay(course.eventDate!, date),
                          );

                          setState(() {
                            _selectedDay = hasEvents ? date : null;
                          });
                        },
                      ),
                      const SizedBox(height: 28),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Row(
                          children: [
                            const Text(
                              'Eventos',
                              style: TextStyle(
                                color: _dark,
                                fontFamily: 'Oswald',
                                fontSize: 25,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            if (_selectedDay != null)
                              TextButton(
                                onPressed: () {
                                  setState(() => _selectedDay = null);
                                },
                                child: const Text('Ver todos'),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ]),
                  ),
                ),
                if (visibleCourses.isEmpty)
                  const SliverToBoxAdapter(
                    child: _AcademyEmpty(),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final course = visibleCourses[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: _AcademyCard(
                              course: course,
                              onRegister: () =>
                                  _openRegistration(context, course),
                            ),
                          );
                        },
                        childCount: visibleCourses.length,
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

class _AcademyCalendar extends StatelessWidget {
  const _AcademyCalendar({
    required this.visibleMonth,
    required this.courses,
    required this.selectedDay,
    required this.onPrevious,
    required this.onNext,
    required this.onDaySelected,
  });

  final DateTime visibleMonth;
  final List<CourseModel> courses;
  final DateTime? selectedDay;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<DateTime> onDaySelected;

  @override
  Widget build(BuildContext context) {
    const weekdays = <String>[
      'Lunes',
      'Martes',
      'Miércoles',
      'Jueves',
      'Viernes',
      'Sábado',
      'Domingo',
    ];

    final firstDay = DateTime(
      visibleMonth.year,
      visibleMonth.month,
      1,
    );
    final offset = firstDay.weekday - DateTime.monday;
    final gridStart = firstDay.subtract(Duration(days: offset));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 10,
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: onPrevious,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    _monthLabel(visibleMonth),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _dark,
                      fontFamily: 'Oswald',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onNext,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
          Container(
            color: const Color(0xFFB40000),
            child: Row(
              children: weekdays.map((label) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          GridView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 42,
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.2,
            ),
            itemBuilder: (context, index) {
              final day = gridStart.add(Duration(days: index));
              final inMonth = day.month == visibleMonth.month;
              final events = courses.where((course) {
                final eventDate = course.eventDate;
                return eventDate != null && _sameDay(eventDate, day);
              }).toList();
              final hasEvents = events.isNotEmpty;
              final selected =
                  selectedDay != null && _sameDay(selectedDay!, day);

              return InkWell(
                onTap: () => onDaySelected(day),
                child: Container(
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFFFFDADA)
                        : (hasEvents
                            ? const Color(0xFFFFF0F0)
                            : Colors.white),
                    border: Border(
                      right: BorderSide(color: _border, width: 0.7),
                      bottom: BorderSide(color: _border, width: 0.7),
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: hasEvents ? 30 : null,
                        height: hasEvents ? 30 : null,
                        alignment: Alignment.center,
                        decoration: hasEvents
                            ? const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              )
                            : null,
                        child: Text(
                          '${day.day}',
                          style: TextStyle(
                            color: hasEvents
                                ? Colors.white
                                : (inMonth
                                    ? _dark
                                    : const Color(0xFF98A2B3)),
                            fontSize: 12,
                            fontWeight: hasEvents
                                ? FontWeight.w800
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (hasEvents)
                        Positioned(
                          bottom: 3,
                          child: Container(
                            width: 22,
                            height: 3,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                      if (events.length > 1)
                        Positioned(
                          top: 3,
                          right: 4,
                          child: Text(
                            '${events.length}',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _monthLabel(DateTime date) {
    const months = <String>[
      'ENERO',
      'FEBRERO',
      'MARZO',
      'ABRIL',
      'MAYO',
      'JUNIO',
      'JULIO',
      'AGOSTO',
      'SEPTIEMBRE',
      'OCTUBRE',
      'NOVIEMBRE',
      'DICIEMBRE',
    ];

    return '${months[date.month - 1]} ${date.year}';
  }
}

class _AcademyCard extends StatelessWidget {
  const _AcademyCard({
    required this.course,
    required this.onRegister,
  });

  final CourseModel course;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AcademyEventImage(course: course),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  course.title,
                  style: const TextStyle(
                    color: _dark,
                    fontFamily: 'Oswald',
                    fontSize: 18,
                    height: 1.12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (course.presenter.trim().isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    course.presenter.trim(),
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  height: 40,
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onRegister,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF54C96B),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                    child: const Text(
                      'Inscribirme',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
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
}

class _AcademyEventImage extends ConsumerWidget {
  const _AcademyEventImage({required this.course});

  final CourseModel course;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final directImageUrl = course.imageUrl.trim();
    final courseUrl = course.url.trim();

    final fallback = courseUrl.isEmpty
        ? const _ImagePlaceholder()
        : _AcademyPageImageFallback(courseUrl: courseUrl);

    // El endpoint ya entrega la URL real de la imagen publicada en la web.
    // La usamos primero para evitar volver a descargar y analizar la página
    // pública de Academy en cada tarjeta. Si esa URL falla, conservamos el
    // fallback anterior y volvemos a resolver la imagen desde la web real.
    if (directImageUrl.isNotEmpty &&
        (directImageUrl.startsWith('https://') ||
            directImageUrl.startsWith('http://'))) {
      return _AcademyNetworkImage(
        imageUrl: directImageUrl,
        onFailure: fallback,
      );
    }

    return fallback;
  }
}

class _AcademyNetworkImage extends StatelessWidget {
  const _AcademyNetworkImage({
    required this.imageUrl,
    required this.onFailure,
  });

  final String imageUrl;
  final Widget onFailure;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      httpHeaders: _academyImageHeaders,
      width: double.infinity,
      fit: BoxFit.fitWidth,
      alignment: Alignment.topCenter,
      fadeInDuration: const Duration(milliseconds: 120),
      fadeOutDuration: const Duration(milliseconds: 80),
      useOldImageOnUrlChange: true,
      // Mantiene la misma imagen real, pero evita decodificar miles de
      // pixeles innecesarios en moviles antiguos.
      memCacheWidth: 1200,
      maxWidthDiskCache: 1200,
      placeholder: (_, __) => const AspectRatio(
        aspectRatio: 16 / 9,
        child: _ImagePlaceholder(),
      ),
      errorWidget: (_, __, ___) => onFailure,
    );
  }
}

class _AcademyPageImageFallback extends ConsumerWidget {
  const _AcademyPageImageFallback({required this.courseUrl});

  final String courseUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cleanUrl = courseUrl.trim();
    if (cleanUrl.isEmpty) {
      return const _ImagePlaceholder();
    }

    final asyncImage =
        ref.watch(_academyPageFallbackImageProvider(cleanUrl));

    return asyncImage.when(
      loading: () => const _ImagePlaceholder(),
      error: (_, __) => const _ImagePlaceholder(),
      data: (imageUrl) {
        final cleanImage = imageUrl.trim();
        if (cleanImage.isEmpty) {
          return const _ImagePlaceholder();
        }

        return _AcademyNetworkImage(
          imageUrl: cleanImage,
          onFailure: const _ImagePlaceholder(),
        );
      },
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
        Icons.school_outlined,
        color: Color(0xFF98A2B3),
        size: 34,
      ),
    );
  }
}

class _AcademyEmpty extends StatelessWidget {
  const _AcademyEmpty();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 50),
      child: Center(
        child: Text(
          'No hay formaciones disponibles.',
          style: TextStyle(
            color: _muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _AcademyError extends StatelessWidget {
  const _AcademyError({required this.onRetry});

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


bool _sameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

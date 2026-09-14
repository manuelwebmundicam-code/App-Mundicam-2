import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mundicam/features/mundicam_content/domain/models/mundicam_academy_event.dart';
import 'package:mundicam/features/mundicam_content/presentation/pages/content_registration_webview_page.dart';
import 'package:mundicam/features/mundicam_content/presentation/providers/mundicam_content_provider.dart';
import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/shared/widgets/professional_page_app_bar.dart';

const Color _pageBg = Color(0xFFF4F7FB);
const Color _dark = Color(0xFF111827);
const Color _muted = Color(0xFF667085);
const Color _border = Color(0xFFE3E8EF);

class MundicamAcademyPage extends ConsumerStatefulWidget {
  const MundicamAcademyPage({super.key});

  @override
  ConsumerState<MundicamAcademyPage> createState() =>
      _MundicamAcademyPageState();
}

class _MundicamAcademyPageState
    extends ConsumerState<MundicamAcademyPage> {
  late DateTime _visibleMonth;
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
  }

  void _previousMonth() {
    setState(() {
      _visibleMonth = DateTime(
        _visibleMonth.year,
        _visibleMonth.month - 1,
      );
      _selectedDay = null;
    });
  }

  void _nextMonth() {
    setState(() {
      _visibleMonth = DateTime(
        _visibleMonth.year,
        _visibleMonth.month + 1,
      );
      _selectedDay = null;
    });
  }

  void _register(
    BuildContext context,
    MundicamAcademyEvent event,
  ) {
    final uri = Uri.tryParse(event.registrationUrl);

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
        builder: (_) => ContentRegistrationWebViewPage(
          title: 'INSCRIPCIÓN ACADEMY',
          initialUri: uri,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncEvents = ref.watch(mundicamAcademyProvider);

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: ProfessionalPageAppBar(
        title: 'MUNDICAM ACADEMY',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: asyncEvents.when(
        loading: () => const Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
          ),
        ),
        error: (_, __) => _ErrorState(
          onRetry: () =>
              ref.invalidate(mundicamAcademyProvider),
        ),
        data: (events) {
          final visibleEvents = _selectedDay == null
              ? events
              : events.where((event) {
                  final date = event.eventDate;
                  return date != null &&
                      _sameDay(date, _selectedDay!);
                }).toList();

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async {
              ref.invalidate(mundicamAcademyProvider);
              await ref.read(mundicamAcademyProvider.future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(
                10,
                14,
                10,
                28,
              ),
              children: [
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
                _Calendar(
                  visibleMonth: _visibleMonth,
                  events: events,
                  selectedDay: _selectedDay,
                  onPrevious: _previousMonth,
                  onNext: _nextMonth,
                  onDaySelected: (date) {
                    final hasEvents = events.any(
                      (event) =>
                          event.eventDate != null &&
                          _sameDay(event.eventDate!, date),
                    );

                    setState(() {
                      _selectedDay =
                          hasEvents ? date : null;
                    });
                  },
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Text(
                      'Eventos',
                      style: TextStyle(
                        color: _dark,
                        fontFamily: 'Oswald',
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    if (_selectedDay != null)
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedDay = null;
                          });
                        },
                        child: const Text('Ver todos'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (visibleEvents.isEmpty)
                  const _EmptyState()
                else
                  ...visibleEvents.map(
                    (event) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _EventCard(
                        event: event,
                        onRegister: () =>
                            _register(context, event),
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

class _Calendar extends StatelessWidget {
  const _Calendar({
    required this.visibleMonth,
    required this.events,
    required this.selectedDay,
    required this.onPrevious,
    required this.onNext,
    required this.onDaySelected,
  });

  final DateTime visibleMonth;
  final List<MundicamAcademyEvent> events;
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

    final first = DateTime(
      visibleMonth.year,
      visibleMonth.month,
      1,
    );

    final offset = first.weekday - DateTime.monday;
    final start = first.subtract(Duration(days: offset));

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
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
                  icon: const Icon(
                    Icons.chevron_left_rounded,
                  ),
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
                  icon: const Icon(
                    Icons.chevron_right_rounded,
                  ),
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
                    padding: const EdgeInsets.symmetric(
                      vertical: 5,
                    ),
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
              final day = start.add(
                Duration(days: index),
              );

              final inMonth =
                  day.month == visibleMonth.month;

              final hasEvents = events.any(
                (event) =>
                    event.eventDate != null &&
                    _sameDay(event.eventDate!, day),
              );

              final selected =
                  selectedDay != null &&
                  _sameDay(selectedDay!, day);

              return InkWell(
                onTap: () => onDaySelected(day),
                child: Container(
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFFFDECEC)
                        : Colors.white,
                    border: Border(
                      right: BorderSide(
                        color: _border,
                        width: 0.7,
                      ),
                      bottom: BorderSide(
                        color: _border,
                        width: 0.7,
                      ),
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Text(
                        '${day.day}',
                        style: TextStyle(
                          color: inMonth
                              ? _dark
                              : const Color(0xFF98A2B3),
                          fontSize: 12,
                          fontWeight: hasEvents
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                      if (hasEvents)
                        Positioned(
                          bottom: 5,
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration:
                                const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
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
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.onRegister,
  });

  final MundicamAcademyEvent event;
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            height: 150,
            child: event.imageUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: event.imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        const _ImageFallback(),
                    errorWidget: (_, __, ___) =>
                        const _ImageFallback(),
                  )
                : const _ImageFallback(),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                13,
                12,
                13,
                12,
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _dark,
                      fontFamily: 'Oswald',
                      fontSize: 16.5,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (event.presenter.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      event.presenter,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 11.6,
                        height: 1.25,
                      ),
                    ),
                  ],
                  if (event.eventDate != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _dateLabel(event.eventDate!),
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 11.6,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (event.startTime.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Hora de inicio: ${event.startTime}',
                      style: const TextStyle(
                        color: _dark,
                        fontSize: 11.8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 34,
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onRegister,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            const Color(0xFF54C96B),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(7),
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
          ),
        ],
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
        Icons.school_outlined,
        color: Color(0xFF98A2B3),
        size: 34,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

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

bool _sameDay(DateTime a, DateTime b) {
  return a.year == b.year &&
      a.month == b.month &&
      a.day == b.day;
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

String _dateLabel(DateTime date) {
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
}

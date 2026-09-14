import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mundicam/core/network/mundicam_content_service.dart';
import 'package:mundicam/features/training/data/models/cursos_model.dart';

final academyContentServiceProvider = Provider<MundicamContentService>((ref) {
  return MundicamContentService();
});

/// Academy usa como autoridad las fechas del calendario real de la web.
/// - Solo muestra eventos con fecha ESTRICTAMENTE posterior a hoy.
/// - El mismo día del evento ya no se ofrece inscripción en la app.
/// - Excluye fechas pasadas y eventos sin fecha verificable.
/// - Ordena del evento más próximo al más lejano.
List<CourseModel> _futureAcademyCourses(Iterable<CourseModel> courses) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final result = courses.where((course) {
    final eventDate = course.eventDate;
    if (eventDate == null) {
      return false;
    }

    final day = DateTime(
      eventDate.year,
      eventDate.month,
      eventDate.day,
    );

    return day.isAfter(today);
  }).toList();

  result.sort((a, b) {
    final aDate = a.eventDate!;
    final bDate = b.eventDate!;
    final byDate = aDate.compareTo(bDate);

    if (byDate != 0) {
      return byDate;
    }

    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });

  return result;
}

class AcademyNotifier
    extends StateNotifier<AsyncValue<List<CourseModel>>> {
  AcademyNotifier(this._ref) : super(const AsyncValue.loading()) {
    _loadInitial();
  }

  final Ref _ref;
  bool _refreshing = false;

  Future<void> _loadInitial() async {
    final service = _ref.read(academyContentServiceProvider);
    final cached = service.academyCachedCourses;

    if (cached.isNotEmpty) {
      state = AsyncValue.data(_futureAcademyCourses(cached));
      await refreshSilently();
      return;
    }

    try {
      final courses = await service.getAcademyCourses();
      state = AsyncValue.data(_futureAcademyCourses(courses));
    } catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  Future<void> refreshSilently() async {
    if (_refreshing || state.isLoading) return;

    _refreshing = true;
    try {
      final service = _ref.read(academyContentServiceProvider);
      final courses = await service.getAcademyCourses(
        forceRefresh: true,
      );

      // Mantiene la pantalla actual visible mientras consulta la web.
      // Solo sustituye el contenido cuando la respuesta nueva ya ha llegado.
      state = AsyncValue.data(_futureAcademyCourses(courses));
    } catch (_) {
      // Si falla la comprobación de fondo conservamos lo que ya veía el usuario.
    } finally {
      _refreshing = false;
    }
  }

  Future<void> refreshFromPull() async {
    if (_refreshing) return;

    _refreshing = true;
    try {
      final service = _ref.read(academyContentServiceProvider);
      final courses = await service.getAcademyCourses(
        forceRefresh: true,
      );
      state = AsyncValue.data(_futureAcademyCourses(courses));
    } catch (error, stack) {
      // Si ya hay datos, no vaciamos Academy por un fallo temporal de red.
      if (!state.hasValue) {
        state = AsyncValue.error(error, stack);
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> retry() async {
    if (_refreshing) return;

    _refreshing = true;
    state = const AsyncValue.loading();

    try {
      final service = _ref.read(academyContentServiceProvider);
      final courses = await service.getAcademyCourses(
        forceRefresh: true,
      );
      state = AsyncValue.data(_futureAcademyCourses(courses));
    } catch (error, stack) {
      state = AsyncValue.error(error, stack);
    } finally {
      _refreshing = false;
    }
  }
}

final academyProvider = StateNotifierProvider<
    AcademyNotifier,
    AsyncValue<List<CourseModel>>>((ref) {
  return AcademyNotifier(ref);
});

import 'dart:async';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
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
  final Set<String> _academyImageResolveStarted = <String>{};
  final Set<String> _academyImageWarmupStarted = <String>{};
  final Map<String, String> _resolvedAcademyImages = <String, String>{};

  static const Map<String, String> _academyImageHeaders = <String, String>{
    'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
    'User-Agent': 'MundiCam-App/Public-Content',
    'Referer': 'https://www.mundicam.com/academy/',
  };

  bool _isHttpUrl(String value) {
    return value.startsWith('https://') || value.startsWith('http://');
  }

  String _courseKey(CourseModel course) {
    return '${course.id}|${course.url.trim()}';
  }

  CourseModel _courseWithImage(CourseModel course, String imageUrl) {
    return CourseModel(
      id: course.id,
      title: course.title,
      excerpt: course.excerpt,
      url: course.url,
      imageUrl: imageUrl,
      eventDate: course.eventDate,
      publishedAt: course.publishedAt,
      startTime: course.startTime,
      presenter: course.presenter,
      contentText: course.contentText,
      featuredMediaId: course.featuredMediaId,
    );
  }

  List<CourseModel> _applyResolvedImages(Iterable<CourseModel> courses) {
    return courses.map((course) {
      final courseKey = _courseKey(course);
      final directImage = course.imageUrl.trim();

      if (_isHttpUrl(directImage)) {
        // Si el endpoint ya trae una imagen valida, es la fuente preferente y
        // actualizamos la memoria por si antes habiamos resuelto un fallback.
        _resolvedAcademyImages[courseKey] = directImage;
        return course;
      }

      final resolved = _resolvedAcademyImages[courseKey];
      if (resolved == null || !_isHttpUrl(resolved)) {
        return course;
      }

      return _courseWithImage(course, resolved);
    }).toList(growable: false);
  }

  void _resolveAndWarmFirstAcademyImages(Iterable<CourseModel> courses) {
    final firstFutureCourses = courses.take(4).toList(growable: false);
    if (firstFutureCourses.isEmpty) return;

    // Se hace antes de entrar en Academy porque Home instancia este provider.
    // Si el endpoint no trae imageUrl, resolvemos la imagen REAL desde la web
    // publica del propio evento y despues la dejamos en cache.
    unawaited(_resolveAndWarmAcademyImagesSequentially(firstFutureCourses));
  }

  Future<void> _resolveAndWarmAcademyImagesSequentially(
    List<CourseModel> courses,
  ) async {
    final service = _ref.read(academyContentServiceProvider);
    final cacheManager = DefaultCacheManager();
    final resolvedImages = <String, String>{};

    for (final course in courses) {
      final courseKey = _courseKey(course);
      if (!_academyImageResolveStarted.add(courseKey)) {
        continue;
      }

      var imageUrl = course.imageUrl.trim();

      if (!_isHttpUrl(imageUrl)) {
        final pageUrl = course.url.trim();
        if (_isHttpUrl(pageUrl)) {
          try {
            imageUrl = await service
                .getAcademyPageImage(pageUrl)
                .timeout(const Duration(seconds: 8));
          } catch (_) {
            imageUrl = '';
          }
        }
      }

      if (!_isHttpUrl(imageUrl)) {
        // Permitimos reintento posterior si la web fallo temporalmente.
        _academyImageResolveStarted.remove(courseKey);
        continue;
      }

      resolvedImages[courseKey] = imageUrl;
      _resolvedAcademyImages[courseKey] = imageUrl;

      if (!_academyImageWarmupStarted.add(imageUrl)) {
        continue;
      }

      try {
        final cachedFile = await cacheManager.getFileFromCache(imageUrl);
        if (cachedFile != null) continue;

        await cacheManager
            .getSingleFile(
              imageUrl,
              headers: _academyImageHeaders,
            )
            .timeout(const Duration(seconds: 12));
      } catch (_) {
        // La precarga es una optimizacion. Si falla, Academy conserva la
        // carga normal de esa misma imagen real y el fallback web existente.
      }
    }

    if (resolvedImages.isEmpty) return;

    // Si tuvimos que descubrir una URL desde /academy/ o desde la ficha del
    // evento, la incorporamos al estado. Asi Academy no vuelve a resolverla
    // al dibujar la tarjeta por primera vez.
    state.whenData((currentCourses) {
      var changed = false;
      final updated = currentCourses.map((course) {
        final resolved = resolvedImages[_courseKey(course)];
        if (resolved == null ||
            resolved.isEmpty ||
            course.imageUrl.trim() == resolved) {
          return course;
        }

        changed = true;
        return _courseWithImage(course, resolved);
      }).toList(growable: false);

      if (changed) {
        state = AsyncValue.data(updated);
      }
    });
  }

  Future<void> _loadInitial() async {
    final service = _ref.read(academyContentServiceProvider);
    final cached = service.academyCachedCourses;

    if (cached.isNotEmpty) {
      final futureCourses = _applyResolvedImages(
        _futureAcademyCourses(cached),
      );
      state = AsyncValue.data(futureCourses);
      _resolveAndWarmFirstAcademyImages(futureCourses);
      await refreshSilently();
      return;
    }

    try {
      final courses = await service.getAcademyCourses();
      final futureCourses = _applyResolvedImages(
        _futureAcademyCourses(courses),
      );
      state = AsyncValue.data(futureCourses);
      _resolveAndWarmFirstAcademyImages(futureCourses);
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
      final futureCourses = _applyResolvedImages(
        _futureAcademyCourses(courses),
      );
      state = AsyncValue.data(futureCourses);
      _resolveAndWarmFirstAcademyImages(futureCourses);
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
      final futureCourses = _applyResolvedImages(
        _futureAcademyCourses(courses),
      );
      state = AsyncValue.data(futureCourses);
      _resolveAndWarmFirstAcademyImages(futureCourses);
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
      final futureCourses = _applyResolvedImages(
        _futureAcademyCourses(courses),
      );
      state = AsyncValue.data(futureCourses);
      _resolveAndWarmFirstAcademyImages(futureCourses);
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

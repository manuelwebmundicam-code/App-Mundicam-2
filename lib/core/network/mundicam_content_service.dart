import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:mundicam/features/home/data/models/noticia.dart';
import 'package:mundicam/features/training/data/models/cursos_model.dart';

class MundicamContentService {
  MundicamContentService()
      : _dio = Dio(
          BaseOptions(
            baseUrl: 'https://www.mundicam.com',
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 25),
            sendTimeout: const Duration(seconds: 15),
            headers: const <String, dynamic>{
              'Accept': 'application/json',
              'User-Agent': 'MundiCam-App/Public-Content',
            },
          ),
        );

  final Dio _dio;

  final Map<String, String> _academyPageImageCache = <String, String>{};
  String _academyArchiveImageHtmlCache = '';
  DateTime? _academyArchiveImageHtmlFetchedAt;
  final Map<String, DateTime> _academyPageDateCache = <String, DateTime>{};
  List<CourseModel> _academyCoursesCache = <CourseModel>[];
  List<Noticia> _noticiasCache = <Noticia>[];

  List<Noticia> get noticiasCached =>
      List<Noticia>.unmodifiable(_noticiasCache);

  Future<List<Noticia>> getNoticias({
    bool forceRefresh = false,
    bool fast = false,
  }) async {
    if (!forceRefresh && _noticiasCache.isNotEmpty) {
      return List<Noticia>.unmodifiable(_noticiasCache);
    }

    try {
      final response = await _dio.get(
        '/wp-json/wp/v2/posts',
        queryParameters: <String, dynamic>{
          // La primera carga trae solo lo necesario para pintar rápido.
          // Después el provider amplía a 100 noticias en segundo plano.
          'per_page': fast ? 24 : 100,
          '_embed': 'wp:featuredmedia',
          '_fields':
              'id,date,link,title,excerpt,content,_links,_embedded',
          'status': 'publish',
          'orderby': 'date',
          'order': 'desc',
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 12),
          sendTimeout: const Duration(seconds: 8),
        ),
      );

      final raw = response.data is List
          ? List<dynamic>.from(response.data as List)
          : const <dynamic>[];

      final noticias = raw
          .whereType<Map>()
          .map((item) => Noticia.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.id > 0 && item.titulo.trim().isNotEmpty)
          .toList();

      if (noticias.isNotEmpty) {
        _noticiasCache = List<Noticia>.from(noticias);
      }

      return List<Noticia>.unmodifiable(noticias);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('⚠️ No se pudieron cargar noticias WordPress: $error');
      }

      if (_noticiasCache.isNotEmpty) {
        return List<Noticia>.unmodifiable(_noticiasCache);
      }

      return const <Noticia>[];
    }
  }

  List<CourseModel> get academyCachedCourses =>
      List<CourseModel>.unmodifiable(_academyCoursesCache);

  Future<List<CourseModel>> getAcademyCourses({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _academyCoursesCache.isNotEmpty) {
      return List<CourseModel>.unmodifiable(_academyCoursesCache);
    }

    // Fuente única y autoritativa de Academy:
    // el endpoint MundiCam lee el mismo meta `event_date` que usa el
    // JetEngine Listing Calendar de la web.
    final calendarCourses = await _getAcademyCoursesFromCalendarApi();

    if (calendarCourses != null) {
      _academyCoursesCache = List<CourseModel>.from(calendarCourses);
      return List<CourseModel>.unmodifiable(calendarCourses);
    }

    // Si falla temporalmente la API NO usamos el listado histórico de
    // /academy/, porque contiene eventos antiguos que no deben reaparecer.
    if (_academyCoursesCache.isNotEmpty) {
      return List<CourseModel>.unmodifiable(_academyCoursesCache);
    }

    return const <CourseModel>[];
  }

  /// Fecha de una ficha concreta. Se usa de forma LAZY desde la tarjeta:
  /// la pantalla Academy no espera a que se descarguen todas las fichas.
  Future<DateTime?> getAcademyEventDate(String pageUrl) {
    return _getAcademyEventDateFromPage(pageUrl);
  }


  /// Fuente principal de Academy.
  ///
  /// Devuelve una lista si el puente Academy JetEngine respondió correctamente
  /// (también si está vacía) y null solo si el endpoint no está disponible.
  Future<List<CourseModel>?> _getAcademyCoursesFromCalendarApi() async {
    final now = DateTime.now();
    final tomorrowDate = DateTime(now.year, now.month, now.day + 1);
    final tomorrow =
        '${tomorrowDate.year.toString().padLeft(4, '0')}-'
        '${tomorrowDate.month.toString().padLeft(2, '0')}-'
        '${tomorrowDate.day.toString().padLeft(2, '0')}';

    final events = <CourseModel>[];
    final seen = <String>{};

    var page = 1;
    var totalPages = 1;

    try {
      do {
        final response = await _dio.get(
          '/wp-json/mundicam-app/v1/academy/events',
          options: Options(
            responseType: ResponseType.json,
            receiveTimeout: const Duration(seconds: 15),
            sendTimeout: const Duration(seconds: 8),
            headers: const <String, dynamic>{
              'Accept': 'application/json',
              'User-Agent': 'MundiCam-App/Public-Content',
            },
          ),
        );

        final data = response.data;
        List<dynamic> rawEvents;

        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          final raw = map['events'];
          rawEvents = raw is List
              ? List<dynamic>.from(raw)
              : const <dynamic>[];

          totalPages =
              int.tryParse(map['total_pages']?.toString() ?? '') ??
              int.tryParse(map['totalPages']?.toString() ?? '') ??
              1;
        } else if (data is List) {
          // Compatibilidad defensiva con instalaciones que devuelvan una lista.
          rawEvents = List<dynamic>.from(data);
          totalPages = 1;
        } else {
          return null;
        }

        for (final raw in rawEvents) {
          if (raw is! Map) continue;

          final course = _courseFromCalendarApiEvent(
            Map<String, dynamic>.from(raw),
          );
          if (course == null || course.eventDate == null) continue;

          final key = course.id > 0
              ? 'id:${course.id}'
              : '${course.url.trim().toLowerCase()}|'
                  '${course.eventDate!.toIso8601String()}';

          if (!seen.add(key)) continue;
          events.add(course);
        }

        page++;
      } while (page <= totalPages && page <= 20);

      events.sort((a, b) {
        final byDate = a.eventDate!.compareTo(b.eventDate!);
        if (byDate != 0) return byDate;

        final byTime = a.startTime.compareTo(b.startTime);
        if (byTime != 0) return byTime;

        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });

      if (kDebugMode) {
        debugPrint(
          '✅ Academy sincronizado con calendario web: '
          '${events.length} evento(s) futuro(s).',
        );
      }

      return events;
    } on DioException catch (error) {
      if (kDebugMode) {
        final status = error.response?.statusCode;
        debugPrint(
          '⚠️ API MundiCam Academy/JetEngine no disponible'
          '${status == null ? '' : ' HTTP $status'}: $error',
        );
      }
      return null;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('⚠️ No se pudo leer el calendario Academy: $error');
      }
      return null;
    }
  }

  CourseModel? _courseFromCalendarApiEvent(
    Map<String, dynamic> event,
  ) {
    final id = int.tryParse(event['id']?.toString() ?? '') ?? 0;
    final title = _calendarApiText(event['title']);
    if (title.isEmpty) return null;

    // La fecha del registro del calendario web es la autoridad.
    // No usamos como fecha principal textos manuales que puedan quedar antiguos
    // dentro de la página de inscripción.
    final startDate = _calendarApiDate(
      event['start_date'],
      event['start_date_details'],
    );
    if (startDate == null) return null;

    final allDay =
        event['all_day'] == true || event['all_day']?.toString() == '1';

    final eventUrl = _calendarApiUrl(event['url']).isNotEmpty
        ? _calendarApiUrl(event['url'])
        : _calendarApiUrl(event['website']);

    final excerpt = _calendarApiText(event['excerpt']);
    final description = _calendarApiText(event['description']);

    return CourseModel(
      id: id > 0
          ? id
          : _stablePositiveId(
              '$eventUrl|$title|${startDate.toIso8601String()}',
            ),
      title: title,
      excerpt: excerpt.isNotEmpty ? excerpt : description,
      url: eventUrl,
      imageUrl: _calendarApiImageUrl(event['image']),
      eventDate: startDate,
      startTime: allDay
          ? ''
          : _calendarApiTime(
              event['start_date'],
              event['start_date_details'],
            ),
      presenter: _calendarApiPresenter(event['organizer']),
      contentText: description,
    );
  }

  String _calendarApiText(dynamic value) {
    if (value is String) {
      return _plainWebText(value);
    }

    if (value is Map) {
      for (final key in const <String>[
        'rendered',
        'name',
        'title',
        'description',
      ]) {
        final candidate = _calendarApiText(value[key]);
        if (candidate.isNotEmpty) return candidate;
      }
    }

    return '';
  }

  DateTime? _calendarApiDate(
    dynamic rawDate,
    dynamic rawDetails,
  ) {
    final raw = rawDate?.toString().trim() ?? '';
    final direct = RegExp(
      r'^(20\d{2})-([01]?\d)-([0-3]?\d)',
    ).firstMatch(raw);

    if (direct != null) {
      return _safeAcademyDate(
        int.tryParse(direct.group(1) ?? ''),
        int.tryParse(direct.group(2) ?? ''),
        int.tryParse(direct.group(3) ?? ''),
      );
    }

    if (rawDetails is Map) {
      final details = Map<String, dynamic>.from(rawDetails);
      return _safeAcademyDate(
        int.tryParse(details['year']?.toString() ?? ''),
        int.tryParse(details['month']?.toString() ?? ''),
        int.tryParse(details['day']?.toString() ?? ''),
      );
    }

    return null;
  }

  String _calendarApiTime(
    dynamic rawDate,
    dynamic rawDetails,
  ) {
    final raw = rawDate?.toString().trim() ?? '';
    final direct = RegExp(
      r'(?:T|\s)((?:[01]?\d|2[0-3])):([0-5]\d)',
    ).firstMatch(raw);

    if (direct != null) {
      return '${direct.group(1)!.padLeft(2, '0')}:${direct.group(2)}';
    }

    if (rawDetails is Map) {
      final details = Map<String, dynamic>.from(rawDetails);
      final hour = int.tryParse(details['hour']?.toString() ?? '');
      final minute = int.tryParse(
        details['minutes']?.toString() ??
            details['minute']?.toString() ??
            '',
      );

      if (hour != null &&
          minute != null &&
          hour >= 0 &&
          hour <= 23 &&
          minute >= 0 &&
          minute <= 59) {
        return '${hour.toString().padLeft(2, '0')}:'
            '${minute.toString().padLeft(2, '0')}';
      }
    }

    return '';
  }

  String _calendarApiUrl(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return '';

    final uri = Uri.tryParse(raw);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return '';
    }

    return uri.toString();
  }

  String _calendarApiImageUrl(dynamic value) {
    if (value is String) {
      return _calendarApiUrl(value);
    }

    if (value is Map) {
      for (final key in const <String>[
        'url',
        'source_url',
        'src',
        'full',
      ]) {
        final candidate = _calendarApiImageUrl(value[key]);
        if (candidate.isNotEmpty) return candidate;
      }
    }

    if (value is List) {
      for (final item in value) {
        final candidate = _calendarApiImageUrl(item);
        if (candidate.isNotEmpty) return candidate;
      }
    }

    return '';
  }

  String _calendarApiPresenter(dynamic value) {
    final names = <String>[];

    void collect(dynamic item) {
      if (item is String) {
        final name = _plainWebText(item);
        if (name.isNotEmpty && !names.contains(name)) {
          names.add(name);
        }
        return;
      }

      if (item is Map) {
        final organizer = _calendarApiText(item['organizer']);
        final name = organizer.isNotEmpty
            ? organizer
            : _calendarApiText(item['name']);

        if (name.isNotEmpty && !names.contains(name)) {
          names.add(name);
        }
        return;
      }

      if (item is List) {
        for (final nested in item) {
          collect(nested);
        }
      }
    }

    collect(value);
    return names.take(3).join(', ');
  }

  Future<String> _fetchAcademyArchiveHtml() async {
    try {
      final response = await _dio.get<String>(
        '/academy/',
        options: Options(
          responseType: ResponseType.plain,
          headers: const <String, dynamic>{
            'Accept': 'text/html,application/xhtml+xml',
          },
        ),
      );
      return response.data ?? '';
    } catch (error) {
      if (kDebugMode) {
        debugPrint('⚠️ No se pudo precargar /academy/: $error');
      }
      return '';
    }
  }

  Future<List<CourseModel>> _getAcademyCoursesFromWebArchive({
    String? prefetchedHtml,
  }) async {
    try {
      final html = (prefetchedHtml ?? '').trim().isNotEmpty
          ? prefetchedHtml!
          : await _fetchAcademyArchiveHtml();
      if (html.trim().isEmpty) {
        return const <CourseModel>[];
      }

      final events = <CourseModel>[];
      final seen = <String>{};

      final scripts = RegExp(
        r'''<script[^>]+type=["']application/ld\+json["'][^>]*>(.*?)</script>''',
        caseSensitive: false,
        dotAll: true,
      ).allMatches(html);

      for (final match in scripts) {
        final rawJson = (match.group(1) ?? '')
            .replaceAll('&amp;', '&')
            .replaceAll('&#038;', '&')
            .trim();

        if (rawJson.isEmpty) continue;

        dynamic decoded;
        try {
          decoded = jsonDecode(rawJson);
        } catch (_) {
          continue;
        }

        final schemaEvents = <Map<String, dynamic>>[];
        _collectSchemaEvents(decoded, schemaEvents);

        for (final event in schemaEvents) {
          final course = _courseFromSchemaEvent(event);
          if (course == null) continue;

          final key = course.url.trim().isNotEmpty
              ? course.url.trim().toLowerCase()
              : course.title.trim().toLowerCase();

          if (key.isEmpty || !seen.add(key)) continue;
          events.add(course);
        }
      }

      events.sort((a, b) {
        final aDate = a.eventDate;
        final bDate = b.eventDate;

        if (aDate != null && bDate != null) {
          return bDate.compareTo(aDate);
        }
        if (aDate != null) return -1;
        if (bDate != null) return 1;
        return a.title.compareTo(b.title);
      });

      if (kDebugMode && events.isNotEmpty) {
        debugPrint(
          '✅ Academy cargado desde la web pública: ${events.length} evento(s).',
        );
      }

      return events;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('⚠️ No se pudo leer /academy/: $error');
      }
      return const <CourseModel>[];
    }
  }



  List<CourseModel> _mergeAcademyArchiveCards(
    List<CourseModel> courses,
    String html,
  ) {
    if (html.trim().isEmpty) return courses;

    final cards = _extractAcademyArchiveCards(html);
    if (cards.isEmpty) return courses;

    final result = <CourseModel>[];

    // IMPORTANTE:
    // La ficha visible en https://www.mundicam.com/academy/ es la autoridad.
    // No conservamos título/hora/ponente de REST si contradicen la web.
    for (final card in cards) {
      final webTitle = (card['title'] ?? '').trim();
      final webUrl = (card['url'] ?? '').trim();
      final webImage = (card['image'] ?? '').trim();
      final webPresenter = (card['presenter'] ?? '').trim();
      final webTime = _validAcademyWebTime(card['time'] ?? '');
      final webDate = _parseAcademyCardDate(card['date'] ?? '') ??
          _knownLegacyAcademyDate(webTitle);

      if (webTitle.isEmpty || webUrl.isEmpty) {
        continue;
      }

      final normalizedWebTitle = _normalizeAcademyMatchText(webTitle);

      CourseModel? match;
      for (final course in courses) {
        final normalizedCourseTitle =
            _normalizeAcademyMatchText(course.title);

        if (normalizedCourseTitle.isEmpty) continue;

        final sameTitle = normalizedWebTitle == normalizedCourseTitle ||
            normalizedWebTitle.contains(normalizedCourseTitle) ||
            normalizedCourseTitle.contains(normalizedWebTitle);

        if (sameTitle) {
          match = course;
          break;
        }
      }

      result.add(
        CourseModel(
          id: match?.id ??
              _stablePositiveId(
                webUrl.isNotEmpty ? webUrl : webTitle,
              ),
          title: webTitle,
          excerpt: match?.excerpt ?? '',
          url: webUrl,
          imageUrl: webImage.isNotEmpty
              ? webImage
              : (match?.imageUrl ?? ''),
          eventDate: webDate,
          publishedAt: match?.publishedAt,
          startTime: webTime,
          presenter: webPresenter,
          contentText: match?.contentText ?? '',
          featuredMediaId: match?.featuredMediaId ?? 0,
        ),
      );
    }

    return result;
  }

  DateTime? _parseAcademyCardDate(String value) {
    final clean = value.trim();
    final match = RegExp(r'^(20\d{2})-([01]\d)-([0-3]\d)$')
        .firstMatch(clean);
    if (match == null) return null;

    return _safeAcademyDate(
      int.tryParse(match.group(1) ?? ''),
      int.tryParse(match.group(2) ?? ''),
      int.tryParse(match.group(3) ?? ''),
    );
  }

  DateTime? _knownLegacyAcademyDate(String title) {
    // Fallback únicamente para fichas históricas cuya página antigua no
    // expone la fecha como texto/HTML y la creatividad publicada sí la fija.
    // No se usa para eventos nuevos y nunca sustituye una fecha del calendario.
    final key = _normalizeAcademyMatchText(title);

    if (key.contains('webinar yale sobre linus l2 smart lock')) {
      return DateTime(2024, 11, 15);
    }
    if (key.contains('formacion presencial de hikvision en mundicam academy')) {
      return DateTime(2024, 11, 20);
    }
    if (key.contains('webinar hikvision en mundicam academy')) {
      return DateTime(2024, 11, 14);
    }
    if (key.contains('multiverse event de ajax')) {
      return DateTime(2024, 11, 21);
    }
    if (key.contains('seguridad perimetral inteligente con rbtec')) {
      return DateTime(2024, 9, 13);
    }
    if (key.contains('transformamos la seguridad perimetral con secury360')) {
      return DateTime(2024, 9, 11);
    }
    if (key.contains('ajax day ii')) {
      return DateTime(2025, 3, 13);
    }

    return null;
  }

  String _validAcademyWebTime(String value) {
    final clean = value.trim();
    return RegExp(r'^(?:[01]?\d|2[0-3]):[0-5]\d$').hasMatch(clean)
        ? clean
        : '';
  }

  List<Map<String, String>> _extractAcademyArchiveCards(String html) {
    final result = <Map<String, String>>[];
    final seen = <String>{};
    final baseUri = Uri.parse('https://www.mundicam.com/academy/');

    final imageTagPattern = RegExp(
      r'<img\b[^>]*>',
      caseSensitive: false,
      dotAll: true,
    );
    final imageMatches = imageTagPattern.allMatches(html).toList();

    for (var i = 0; i < imageMatches.length; i++) {
      final imageMatch = imageMatches[i];
      final imageTag = imageMatch.group(0) ?? '';
      final imageUrl = _bestImageFromHtmlTag(imageTag, baseUri);

      if (imageUrl.isEmpty) continue;

      final nextImageStart = i + 1 < imageMatches.length
          ? imageMatches[i + 1].start
          : html.length;

      // Cada bloque de Academy en la web sigue el patrón:
      // imagen -> título -> ponente(opcional) -> Hora de inicio -> Inscribirme.
      final hardEnd = imageMatch.end + 8000;
      final segmentEnd =
          nextImageStart < hardEnd ? nextImageStart : hardEnd;

      if (segmentEnd <= imageMatch.end) continue;
      final segment = html.substring(imageMatch.end, segmentEnd);

      final registrationMatch = RegExp(
        r'''<a\b[^>]*href=["']([^"']+)["'][^>]*>[\s\S]*?Inscribirme[\s\S]*?</a>''',
        caseSensitive: false,
      ).firstMatch(segment);

      final registrationUrl =
          _resolveWebUrl(registrationMatch?.group(1), baseUri);

      if (registrationUrl.isEmpty) {
        continue;
      }

      final headings = RegExp(
        r'<h[1-6]\b[^>]*>(.*?)</h[1-6]>',
        caseSensitive: false,
        dotAll: true,
      )
          .allMatches(segment)
          .map((match) => _plainWebText(match.group(1) ?? ''))
          .where((value) => value.isNotEmpty)
          .toList();

      String title = '';
      String presenter = '';

      for (final heading in headings) {
        final lower = heading.toLowerCase();

        if (lower == 'eventos' ||
            lower.contains('inscribirme') ||
            lower.startsWith('hora de inicio')) {
          continue;
        }

        if (title.isEmpty) {
          title = heading;
          continue;
        }

        if (presenter.isEmpty) {
          presenter = heading;
          break;
        }
      }

      if (title.isEmpty) continue;

      final plainSegment = _plainWebText(segment);
      final timeMatch = RegExp(
        r'hora\s+de\s+inicio\s*:?\s*((?:[01]?\d|2[0-3]):[0-5]\d)',
        caseSensitive: false,
      ).firstMatch(plainSegment);

      final time = _validAcademyWebTime(
        timeMatch?.group(1)?.trim() ?? '',
      );

      // Algunas plantillas esconden la fecha en atributos/texto del propio
      // bloque aunque no se vea en la lista. La leemos aquí sin otra petición.
      final cardDate = _extractAcademyEventDate('$imageTag $segment') ??
          _knownLegacyAcademyDate(title);

      final imageLower = imageUrl.toLowerCase();
      if (imageLower.contains('logo') ||
          imageLower.contains('avatar') ||
          imageLower.contains('favicon') ||
          imageLower.contains('placeholder')) {
        continue;
      }

      final key = _normalizeAcademyMatchText(title);
      if (key.isEmpty || !seen.add(key)) continue;

      result.add(<String, String>{
        'title': title,
        'presenter': presenter,
        'image': imageUrl,
        'url': registrationUrl,
        'time': time,
        'date': cardDate == null
            ? ''
            : '${cardDate.year.toString().padLeft(4, '0')}-'
                '${cardDate.month.toString().padLeft(2, '0')}-'
                '${cardDate.day.toString().padLeft(2, '0')}',
      });
    }

    return result;
  }

  String _bestImageFromHtmlTag(String tag, Uri baseUri) {
    final srcsetMatch = RegExp(
      r'''srcset=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(tag);

    if (srcsetMatch != null) {
      String best = '';
      var bestWidth = 0;

      for (final item in (srcsetMatch.group(1) ?? '').split(',')) {
        final parts = item.trim().split(RegExp(r'\s+'));
        if (parts.isEmpty) continue;

        final candidate = _resolveWebUrl(parts.first, baseUri);
        if (candidate.isEmpty || candidate.startsWith('data:')) continue;

        var width = 1;
        if (parts.length > 1) {
          final descriptor = parts.last.toLowerCase();
          if (descriptor.endsWith('w')) {
            width = int.tryParse(
                  descriptor.substring(0, descriptor.length - 1),
                ) ??
                1;
          }
        }

        if (width >= bestWidth) {
          bestWidth = width;
          best = candidate;
        }
      }

      if (best.isNotEmpty) return best;
    }

    for (final attribute in const <String>[
      'data-lazy-src',
      'data-src',
      'data-original',
      'src',
    ]) {
      final pattern = RegExp(
        '$attribute=["\\\']([^"\\\']+)["\\\']',
        caseSensitive: false,
      );
      final match = pattern.firstMatch(tag);
      final resolved = _resolveWebUrl(match?.group(1), baseUri);
      if (resolved.isNotEmpty && !resolved.startsWith('data:')) {
        return resolved;
      }
    }

    return '';
  }


  Future<DateTime?> _getAcademyEventDateFromPage(String pageUrl) async {
    final cleanUrl = pageUrl.trim();
    if (cleanUrl.isEmpty) return null;

    final cached = _academyPageDateCache[cleanUrl];
    if (cached != null) return cached;

    final uri = Uri.tryParse(cleanUrl);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return null;
    }

    try {
      final response = await _dio.get<String>(
        cleanUrl,
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 6),
          sendTimeout: const Duration(seconds: 6),
          headers: const <String, dynamic>{
            'Accept': 'text/html,application/xhtml+xml',
            'User-Agent': 'MundiCam-App/Public-Content',
          },
        ),
      );

      final html = response.data ?? '';
      final date = _extractAcademyEventDate(html);

      if (date != null) {
        _academyPageDateCache[cleanUrl] = date;
      }

      return date;
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '⚠️ Academy: no se pudo recuperar fecha desde $cleanUrl: $error',
        );
      }
      return null;
    }
  }

  DateTime? _extractAcademyEventDate(String html) {
    if (html.trim().isEmpty) return null;

    // 1) Datos estructurados / atributos HTML.
    // Son la fuente más fiable cuando Elementor o un plugin de eventos
    // publica la fecha de forma legible por máquina.
    for (final pattern in <RegExp>[
      RegExp(
        r'''["']startDate["']\s*:\s*["'](20\d{2})-([01]\d)-([0-3]\d)(?:[T\s][^"']*)?["']''',
        caseSensitive: false,
      ),
      RegExp(
        r'''datetime\s*=\s*["'](20\d{2})-([01]\d)-([0-3]\d)(?:[T\s][^"']*)?["']''',
        caseSensitive: false,
      ),
      RegExp(
        r'''data-(?:event-)?date\s*=\s*["'](20\d{2})-([01]\d)-([0-3]\d)(?:[T\s][^"']*)?["']''',
        caseSensitive: false,
      ),
    ]) {
      final match = pattern.firstMatch(html);
      if (match != null) {
        final date = _safeAcademyDate(
          int.tryParse(match.group(1) ?? ''),
          int.tryParse(match.group(2) ?? ''),
          int.tryParse(match.group(3) ?? ''),
        );
        if (date != null) return date;
      }
    }

    final plain = _plainWebText(html);
    if (plain.isEmpty) return null;

    final lower = plain.toLowerCase();

    // Trabajamos primero sobre la zona del contenido donde normalmente
    // MundiCam publica los datos del evento, evitando cabecera/footer.
    var start = -1;
    for (final marker in const <String>[
      'cuándo y dónde',
      'cuando y donde',
      'dónde, cuándo',
      'donde, cuando',
      'dónde, cuándo y quién',
      'donde, cuando y quien',
      'fecha del evento',
      'fecha:',
      'hora de inicio',
    ]) {
      final found = lower.indexOf(marker);
      if (found >= 0 && (start < 0 || found < start)) {
        start = found;
      }
    }

    final relevant = start >= 0
        ? plain.substring(
            (start - 700).clamp(0, plain.length),
            (start + 4000).clamp(0, plain.length),
          )
        : plain;

    // 2) dd/mm/yyyy o dd-mm-yyyy.
    final numeric = RegExp(
      r'\b([0-3]?\d)[/-]([01]?\d)[/-](20\d{2})\b',
      caseSensitive: false,
    ).firstMatch(relevant);

    if (numeric != null) {
      final date = _safeAcademyDate(
        int.tryParse(numeric.group(3) ?? ''),
        int.tryParse(numeric.group(2) ?? ''),
        int.tryParse(numeric.group(1) ?? ''),
      );
      if (date != null) return date;
    }

    // 3) ISO yyyy-mm-dd que pueda estar visible en texto.
    final iso = RegExp(
      r'\b(20\d{2})-([01]?\d)-([0-3]?\d)\b',
      caseSensitive: false,
    ).firstMatch(relevant);

    if (iso != null) {
      final date = _safeAcademyDate(
        int.tryParse(iso.group(1) ?? ''),
        int.tryParse(iso.group(2) ?? ''),
        int.tryParse(iso.group(3) ?? ''),
      );
      if (date != null) return date;
    }

    // 4) Español flexible:
    // 20 de noviembre de 2024
    // 20 de noviembre 2024
    // 20 noviembre de 2024
    // 20 noviembre 2024
    final spanish = RegExp(
      r'\b([0-3]?\d)\s+(?:de\s+)?'
      r'(enero|febrero|marzo|abril|mayo|junio|julio|agosto|'
      r'septiembre|setiembre|octubre|noviembre|diciembre)'
      r'(?:\s+de)?\s+(20\d{2})\b',
      caseSensitive: false,
    ).firstMatch(relevant);

    if (spanish != null) {
      final month = _academyMonthNumber(
        spanish.group(2)?.toLowerCase() ?? '',
      );
      final date = _safeAcademyDate(
        int.tryParse(spanish.group(3) ?? ''),
        month,
        int.tryParse(spanish.group(1) ?? ''),
      );
      if (date != null) return date;
    }

    // 5) Algunas creatividades muestran solo 14/11 o "20 de noviembre",
    // mientras el año figura muy cerca en el mismo bloque de la ficha.
    // Solo aceptamos este caso si encontramos UN único año 20xx cercano;
    // no usamos fecha de publicación ni inventamos el año.
    final shortNumeric = RegExp(
      r'\b([0-3]?\d)[/-]([01]?\d)\b',
      caseSensitive: false,
    ).firstMatch(relevant);

    if (shortNumeric != null) {
      final year = _uniqueNearbyAcademyYear(
        relevant,
        shortNumeric.start,
        shortNumeric.end,
      );
      if (year != null) {
        final date = _safeAcademyDate(
          year,
          int.tryParse(shortNumeric.group(2) ?? ''),
          int.tryParse(shortNumeric.group(1) ?? ''),
        );
        if (date != null) return date;
      }
    }

    final shortSpanish = RegExp(
      r'\b([0-3]?\d)\s+(?:de\s+)?'
      r'(enero|febrero|marzo|abril|mayo|junio|julio|agosto|'
      r'septiembre|setiembre|octubre|noviembre|diciembre)\b',
      caseSensitive: false,
    ).firstMatch(relevant);

    if (shortSpanish != null) {
      final year = _uniqueNearbyAcademyYear(
        relevant,
        shortSpanish.start,
        shortSpanish.end,
      );
      if (year != null) {
        final date = _safeAcademyDate(
          year,
          _academyMonthNumber(
            shortSpanish.group(2)?.toLowerCase() ?? '',
          ),
          int.tryParse(shortSpanish.group(1) ?? ''),
        );
        if (date != null) return date;
      }
    }

    // 6) Formatos frecuentes en fichas MundiCam sin el literal "Fecha:":
    // "El próximo viernes 13 de septiembre de 2024"
    // "Jueves, 13 de marzo de 2025"
    // "Cuándo: Jueves 10 de julio" + año explícito en la propia ficha.
    final looseSpanish = RegExp(
      r'\b(?:lunes|martes|miércoles|miercoles|jueves|viernes|sábado|sabado|domingo)?'
      r'\s*,?\s*([0-3]?\d)\s+(?:de\s+)?'
      r'(enero|febrero|marzo|abril|mayo|junio|julio|agosto|'
      r'septiembre|setiembre|octubre|noviembre|diciembre)'
      r'(?:\s+de)?\s+(20\d{2})\b',
      caseSensitive: false,
    ).firstMatch(plain);

    if (looseSpanish != null) {
      final date = _safeAcademyDate(
        int.tryParse(looseSpanish.group(3) ?? ''),
        _academyMonthNumber(
          looseSpanish.group(2)?.toLowerCase() ?? '',
        ),
        int.tryParse(looseSpanish.group(1) ?? ''),
      );
      if (date != null) return date;
    }

    // Si la ficha realmente no publica una fecha comprobable, NO usamos
    // datePublished/publishedAt como fecha del evento.
    return null;
  }

  int? _uniqueNearbyAcademyYear(
    String text,
    int matchStart,
    int matchEnd,
  ) {
    final from = (matchStart - 500).clamp(0, text.length);
    final to = (matchEnd + 500).clamp(0, text.length);
    final nearby = text.substring(from, to);

    final years = RegExp(r'\b20\d{2}\b')
        .allMatches(nearby)
        .map((match) => int.tryParse(match.group(0) ?? ''))
        .whereType<int>()
        .toSet();

    return years.length == 1 ? years.first : null;
  }

  DateTime? _safeAcademyDate(int? year, int? month, int? day) {
    if (year == null || month == null || day == null) return null;
    if (year < 2000 || year > 2100) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;

    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  int? _academyMonthNumber(String month) {
    const values = <String, int>{
      'enero': 1,
      'febrero': 2,
      'marzo': 3,
      'abril': 4,
      'mayo': 5,
      'junio': 6,
      'julio': 7,
      'agosto': 8,
      'septiembre': 9,
      'setiembre': 9,
      'octubre': 10,
      'noviembre': 11,
      'diciembre': 12,
    };
    return values[month];
  }

  List<CourseModel> _mergeAcademyCalendarHints(
    List<CourseModel> courses,
    String html,
  ) {
    if (html.trim().isEmpty || courses.isEmpty) return courses;

    // Usamos el texto visible de la MISMA /academy/. En el calendario el
    // patrón real es: título del evento -> dd/mm/yyyy -> Hora. Cada título
    // también aparece después en la lista "Eventos", pero esa segunda
    // aparición no lleva fecha. Por eso recorremos TODAS las apariciones y
    // elegimos únicamente una que tenga una fecha dd/mm/yyyy inmediatamente
    // asociada. Así no mezclamos meses ni fechas de otros bloques.
    final visibleText = _plainWebText(html);
    if (visibleText.isEmpty) return courses;

    final lowerText = visibleText.toLowerCase();
    final result = <CourseModel>[];

    for (final course in courses) {
      final title = course.title.trim();
      if (title.isEmpty) {
        result.add(course);
        continue;
      }

      DateTime? calendarDate;
      String calendarTime = '';

      final exactNeedle = title.toLowerCase();
      var searchFrom = 0;

      while (searchFrom < lowerText.length) {
        final index = lowerText.indexOf(exactNeedle, searchFrom);
        if (index < 0) break;

        final afterStart = index + exactNeedle.length;
        final afterEnd = (afterStart + 520).clamp(0, visibleText.length);
        if (afterStart < afterEnd) {
          final afterTitle = visibleText.substring(afterStart, afterEnd);
          final dateMatch = RegExp(
            r'\b([0-3]?\d)/([01]?\d)/(20\d{2})\b',
            caseSensitive: false,
          ).firstMatch(afterTitle);

          if (dateMatch != null) {
            final candidate = _safeAcademyDate(
              int.tryParse(dateMatch.group(3) ?? ''),
              int.tryParse(dateMatch.group(2) ?? ''),
              int.tryParse(dateMatch.group(1) ?? ''),
            );

            if (candidate != null) {
              calendarDate = candidate;
              final timeMatch = RegExp(
                r'\b(?:hora(?:\s+de\s+inicio)?)\s*:?\s*'
                r'((?:[01]?\d|2[0-3]):[0-5]\d)',
                caseSensitive: false,
              ).firstMatch(afterTitle);
              calendarTime = _validAcademyWebTime(
                timeMatch?.group(1)?.trim() ?? '',
              );
              break;
            }
          }
        }

        searchFrom = index + exactNeedle.length;
      }

      // Fallback normalizado para pequeños cambios de espacios, símbolos o
      // mayúsculas entre el título del calendario y la lista de eventos.
      if (calendarDate == null) {
        final normalizedTitle = _normalizeAcademyMatchText(title);
        if (normalizedTitle.isNotEmpty) {
          final words = normalizedTitle
              .split(' ')
              .where((word) => word.length > 2)
              .take(8)
              .toList();

          if (words.length >= 2) {
            final firstWord = words.first;
            var fuzzyFrom = 0;

            while (fuzzyFrom < lowerText.length) {
              final index = lowerText.indexOf(firstWord, fuzzyFrom);
              if (index < 0) break;

              final windowEnd = (index + 700).clamp(0, visibleText.length);
              final window = visibleText.substring(index, windowEnd);
              final normalizedWindow = _normalizeAcademyMatchText(window);

              var matchedWords = 0;
              for (final word in words) {
                if (normalizedWindow.contains(word)) matchedWords++;
              }

              if (matchedWords >= (words.length >= 5 ? 4 : 2)) {
                final dateMatch = RegExp(
                  r'\b([0-3]?\d)/([01]?\d)/(20\d{2})\b',
                  caseSensitive: false,
                ).firstMatch(window);

                if (dateMatch != null) {
                  final candidate = _safeAcademyDate(
                    int.tryParse(dateMatch.group(3) ?? ''),
                    int.tryParse(dateMatch.group(2) ?? ''),
                    int.tryParse(dateMatch.group(1) ?? ''),
                  );

                  if (candidate != null) {
                    calendarDate = candidate;
                    final timeMatch = RegExp(
                      r'\b(?:hora(?:\s+de\s+inicio)?)\s*:?\s*'
                      r'((?:[01]?\d|2[0-3]):[0-5]\d)',
                      caseSensitive: false,
                    ).firstMatch(window);
                    calendarTime = _validAcademyWebTime(
                      timeMatch?.group(1)?.trim() ?? '',
                    );
                    break;
                  }
                }
              }

              fuzzyFrom = index + firstWord.length;
            }
          }
        }
      }

      result.add(
        CourseModel(
          id: course.id,
          title: course.title,
          excerpt: course.excerpt,
          url: course.url,
          imageUrl: course.imageUrl,
          // La fecha del calendario actual tiene prioridad. Si este curso es
          // histórico, conservamos la fecha legacy verificada de la tarjeta y,
          // si tampoco existe, la ficha se consulta lazy al hacerse visible.
          eventDate: calendarDate ?? course.eventDate,
          publishedAt: course.publishedAt,
          startTime: calendarTime.isNotEmpty
              ? calendarTime
              : course.startTime,
          presenter: course.presenter,
          contentText: course.contentText,
          featuredMediaId: course.featuredMediaId,
        ),
      );
    }

    return result;
  }

  String _normalizeAcademyMatchText(String value) {
    return _plainWebText(value)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9áéíóúüñ]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void _collectSchemaEvents(
    dynamic value,
    List<Map<String, dynamic>> output,
  ) {
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      final rawType = map['@type'];

      final types = rawType is List
          ? rawType.map((item) => item.toString().toLowerCase()).toList()
          : <String>[rawType?.toString().toLowerCase() ?? ''];

      if (types.contains('event')) {
        output.add(map);
      }

      for (final nested in map.values) {
        _collectSchemaEvents(nested, output);
      }
      return;
    }

    if (value is List) {
      for (final nested in value) {
        _collectSchemaEvents(nested, output);
      }
    }
  }

  CourseModel? _courseFromSchemaEvent(Map<String, dynamic> event) {
    final title = _plainWebText(event['name']?.toString() ?? '');
    if (title.isEmpty) return null;

    final primaryUrl = _schemaUrl(event['url']);
    final url = primaryUrl.isNotEmpty
        ? primaryUrl
        : _schemaUrl(event['mainEntityOfPage']);
    final startRaw = event['startDate']?.toString().trim() ?? '';
    final start = DateTime.tryParse(startRaw);
    final description =
        _plainWebText(event['description']?.toString() ?? '');

    final imageUrl = _schemaImageUrl(event['image']);
    final presenter = _schemaPersonName(event['performer']).isNotEmpty
        ? _schemaPersonName(event['performer'])
        : _schemaPersonName(event['organizer']);

    final keySource = url.isNotEmpty ? url : '$title|$startRaw';

    return CourseModel(
      id: _stablePositiveId(keySource),
      title: title,
      excerpt: description,
      url: url,
      imageUrl: imageUrl,
      eventDate: start == null
          ? null
          : DateTime(start.year, start.month, start.day),
      startTime: start == null
          ? ''
          : '${start.hour.toString().padLeft(2, '0')}:'
              '${start.minute.toString().padLeft(2, '0')}',
      presenter: presenter,
      contentText: description,
    );
  }

  String _schemaUrl(dynamic value) {
    if (value is String) {
      final uri = Uri.tryParse(value.trim());
      if (uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https')) {
        return uri.toString();
      }
    }

    if (value is Map) {
      for (final key in const <String>['url', '@id']) {
        final found = _schemaUrl(value[key]);
        if (found.isNotEmpty) return found;
      }
    }

    return '';
  }

  String _schemaImageUrl(dynamic value) {
    if (value is String) {
      return _schemaUrl(value);
    }

    if (value is List) {
      for (final item in value) {
        final found = _schemaImageUrl(item);
        if (found.isNotEmpty) return found;
      }
    }

    if (value is Map) {
      for (final key in const <String>['url', 'contentUrl', '@id']) {
        final found = _schemaUrl(value[key]);
        if (found.isNotEmpty) return found;
      }
    }

    return '';
  }

  String _schemaPersonName(dynamic value) {
    if (value is String) {
      return _plainWebText(value);
    }

    if (value is List) {
      for (final item in value) {
        final found = _schemaPersonName(item);
        if (found.isNotEmpty) return found;
      }
    }

    if (value is Map) {
      final name = _plainWebText(value['name']?.toString() ?? '');
      if (name.isNotEmpty) return name;
    }

    return '';
  }

  String _plainWebText(String value) {
    return value
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), ' ')
        .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  int _stablePositiveId(String value) {
    var hash = 5381;
    for (final codeUnit in value.codeUnits) {
      hash = ((hash << 5) + hash) ^ codeUnit;
      hash &= 0x7FFFFFFF;
    }
    return hash == 0 ? 1 : hash;
  }

  Future<String> getAcademyPageImage(String pageUrl) async {
    final cleanUrl = pageUrl.trim();
    if (cleanUrl.isEmpty) return '';

    if (_academyPageImageCache.containsKey(cleanUrl)) {
      return _academyPageImageCache[cleanUrl] ?? '';
    }

    final uri = Uri.tryParse(cleanUrl);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return '';
    }

    // 1) Fuente principal: el propio archivo público /academy/.
    // Es la misma web donde JetEngine pinta cada evento con su imagen real.
    //
    // La asociación se hace por la URL exacta del evento, no por posición
    // ni por título, para evitar coger banners globales o la imagen de otro.
    try {
      final archiveHtml = await _getAcademyArchiveHtmlForImages();
      if (archiveHtml.isNotEmpty) {
        final archiveImage = _extractAcademyArchiveImageForEvent(
          archiveHtml,
          cleanUrl,
        );

        if (archiveImage.isNotEmpty) {
          _academyPageImageCache[cleanUrl] = archiveImage;

          if (kDebugMode) {
            debugPrint(
              '✅ Imagen Academy desde calendario/listado web: '
              '$cleanUrl -> $archiveImage',
            );
          }

          return archiveImage;
        }
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '⚠️ No se pudo resolver imagen Academy desde /academy/: $error',
        );
      }
    }

    // 2) Fallback: ficha pública individual del evento.
    // Sigue siendo web directa, sin depender de ninguna imagen del PHP.
    try {
      final response = await _dio.get<String>(
        cleanUrl,
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
          headers: const <String, dynamic>{
            'Accept': 'text/html,application/xhtml+xml',
            'User-Agent': 'MundiCam-App/Public-Content',
          },
        ),
      );

      final html = response.data ?? '';
      final imageUrl = _extractPageImage(html, uri);

      if (imageUrl.isNotEmpty) {
        _academyPageImageCache[cleanUrl] = imageUrl;

        if (kDebugMode) {
          debugPrint(
            '✅ Imagen Academy desde ficha web: '
            '$cleanUrl -> $imageUrl',
          );
        }
      }

      return imageUrl;
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '⚠️ No se pudo recuperar imagen Academy desde $cleanUrl: $error',
        );
      }
      return '';
    }
  }

  Future<String> _getAcademyArchiveHtmlForImages() async {
    final now = DateTime.now();
    final fetchedAt = _academyArchiveImageHtmlFetchedAt;

    // Caché corta para no descargar /academy/ una vez por cada tarjeta.
    if (_academyArchiveImageHtmlCache.isNotEmpty &&
        fetchedAt != null &&
        now.difference(fetchedAt) < const Duration(minutes: 5)) {
      return _academyArchiveImageHtmlCache;
    }

    final response = await _dio.get<String>(
      '/academy/?nocache=1',
      options: Options(
        responseType: ResponseType.plain,
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 8),
        headers: const <String, dynamic>{
          'Accept': 'text/html,application/xhtml+xml',
          'User-Agent': 'MundiCam-App/Public-Content',
        },
      ),
    );

    final html = response.data ?? '';
    if (html.isNotEmpty) {
      _academyArchiveImageHtmlCache = html;
      _academyArchiveImageHtmlFetchedAt = now;
    }

    return html;
  }

  String _extractAcademyArchiveImageForEvent(
    String html,
    String eventUrl,
  ) {
    if (html.isEmpty || eventUrl.trim().isEmpty) return '';

    final baseUri = Uri.parse('https://www.mundicam.com/academy/');

    String normalizeUrl(String value) {
      final uri = Uri.tryParse(value.trim());
      if (uri == null) return value.trim().toLowerCase();

      var path = uri.path;
      while (path.length > 1 && path.endsWith('/')) {
        path = path.substring(0, path.length - 1);
      }

      return '${uri.scheme.toLowerCase()}://'
          '${uri.host.toLowerCase()}$path';
    }

    final target = normalizeUrl(eventUrl);
    if (target.isEmpty) return '';

    // Buscamos links <a> de Academy y comparamos la URL normalizada.
    final linkPattern = RegExp(
      r'''<a\b[^>]*href=["']([^"']+)["'][^>]*>''',
      caseSensitive: false,
    );

    for (final link in linkPattern.allMatches(html)) {
      final href = _resolveWebUrl(link.group(1), baseUri);
      if (href.isEmpty || normalizeUrl(href) != target) {
        continue;
      }

      // La imagen de cada listing JetEngine aparece antes del enlace/título
      // del propio evento. Limitamos mucho la ventana para no alcanzar
      // cabeceras, WhatsApp, soporte ni tarjetas anteriores lejanas.
      final windowStart =
          link.start > 7000 ? link.start - 7000 : 0;
      final beforeLink = html.substring(windowStart, link.start);

      final images = RegExp(
        r'''<img\b[^>]*>''',
        caseSensitive: false,
        dotAll: true,
      ).allMatches(beforeLink).toList();

      for (var i = images.length - 1; i >= 0; i--) {
        final tag = images[i].group(0) ?? '';
        final imageUrl = _bestImageFromHtmlTag(tag, baseUri);

        if (imageUrl.isEmpty || _isRejectedAcademyImage(imageUrl)) {
          continue;
        }

        // Evita saltar hacia la imagen de una tarjeta anterior:
        // entre esta imagen y el enlace objetivo no debe haber otro enlace
        // distinto a un evento Academy.
        final absoluteImageEnd = windowStart + images[i].end;
        final between = html.substring(absoluteImageEnd, link.start);

        final otherAcademyLinks = RegExp(
          r'''href=["'][^"']*/academy/[^"']+["']''',
          caseSensitive: false,
        ).allMatches(between);

        var hasDifferentEventLink = false;
        for (final other in otherAcademyLinks) {
          final raw = other.group(0) ?? '';
          final hrefMatch = RegExp(
            r'''href=["']([^"']+)["']''',
            caseSensitive: false,
          ).firstMatch(raw);

          final otherUrl = _resolveWebUrl(hrefMatch?.group(1), baseUri);
          if (otherUrl.isNotEmpty && normalizeUrl(otherUrl) != target) {
            hasDifferentEventLink = true;
            break;
          }
        }

        if (hasDifferentEventLink) {
          continue;
        }

        return imageUrl;
      }
    }

    return '';
  }


  String _extractPageImage(String html, Uri pageUri) {
    if (html.trim().isEmpty) return '';

    String accept(String? raw) {
      final resolved = _resolveWebUrl(raw, pageUri);
      if (resolved.isEmpty || _isRejectedAcademyImage(resolved)) {
        return '';
      }
      return resolved;
    }

    // 1) Imagen social/SEO propia de la ficha del evento.
    final metaPatterns = <RegExp>[
      RegExp(
        r'''<meta[^>]+property=["']og:image(?::url)?["'][^>]+content=["']([^"']+)["']''',
        caseSensitive: false,
      ),
      RegExp(
        r'''<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image(?::url)?["']''',
        caseSensitive: false,
      ),
      RegExp(
        r'''<meta[^>]+name=["']twitter:image(?::src)?["'][^>]+content=["']([^"']+)["']''',
        caseSensitive: false,
      ),
      RegExp(
        r'''<meta[^>]+content=["']([^"']+)["'][^>]+name=["']twitter:image(?::src)?["']''',
        caseSensitive: false,
      ),
    ];

    for (final pattern in metaPatterns) {
      final match = pattern.firstMatch(html);
      final candidate = accept(match?.group(1));
      if (candidate.isNotEmpty) return candidate;
    }

    // 2) Imagen declarada en JSON-LD/schema de la página.
    final jsonLdPatterns = <RegExp>[
      RegExp(
        r'''"image"\s*:\s*"([^"]+)"''',
        caseSensitive: false,
      ),
      RegExp(
        r'''"image"\s*:\s*\[\s*"([^"]+)"''',
        caseSensitive: false,
      ),
      RegExp(
        r'''"image"\s*:\s*\{[^{}]{0,1200}?"url"\s*:\s*"([^"]+)"''',
        caseSensitive: false,
        dotAll: true,
      ),
      RegExp(
        r'''"image"\s*:\s*\{[^{}]{0,1200}?"contentUrl"\s*:\s*"([^"]+)"''',
        caseSensitive: false,
        dotAll: true,
      ),
    ];

    for (final pattern in jsonLdPatterns) {
      for (final match in pattern.allMatches(html)) {
        final raw = (match.group(1) ?? '')
            .replaceAll(r'\/', '/')
            .replaceAll(r'\u0026', '&');
        final candidate = accept(raw);
        if (candidate.isNotEmpty) return candidate;
      }
    }

    // 3) Último respaldo: buscar solo dentro del contenido principal.
    // Nunca se recorre el HTML completo para evitar cabeceras, WhatsApp,
    // soporte, footer y otros elementos globales.
    String mainHtml = '';

    for (final pattern in <RegExp>[
      RegExp(
        r'''<main\b[^>]*>(.*?)</main>''',
        caseSensitive: false,
        dotAll: true,
      ),
      RegExp(
        r'''<article\b[^>]*>(.*?)</article>''',
        caseSensitive: false,
        dotAll: true,
      ),
      RegExp(
        r'''<div[^>]+(?:id|class)=["'][^"']*(?:entry-content|page-content|site-content)[^"']*["'][^>]*>(.*?)</div>''',
        caseSensitive: false,
        dotAll: true,
      ),
    ]) {
      final match = pattern.firstMatch(html);
      if (match != null && (match.group(1) ?? '').trim().isNotEmpty) {
        mainHtml = match.group(1) ?? '';
        break;
      }
    }

    if (mainHtml.isEmpty) return '';

    String best = '';
    var bestScore = -1;

    final imageTagPattern = RegExp(
      r'''<img\b[^>]*>''',
      caseSensitive: false,
    );

    for (final match in imageTagPattern.allMatches(mainHtml)) {
      final tag = match.group(0) ?? '';
      final candidate = accept(_bestImageFromHtmlTag(tag, pageUri));
      if (candidate.isEmpty) continue;

      var score = 0;

      final widthMatch = RegExp(
        r'''\bwidth=["']?(\d{2,5})''',
        caseSensitive: false,
      ).firstMatch(tag);
      final heightMatch = RegExp(
        r'''\bheight=["']?(\d{2,5})''',
        caseSensitive: false,
      ).firstMatch(tag);

      final width = int.tryParse(widthMatch?.group(1) ?? '') ?? 0;
      final height = int.tryParse(heightMatch?.group(1) ?? '') ?? 0;

      if (width >= 600) score += 4;
      if (height >= 400) score += 3;
      if (width >= 300 && height >= 200) score += 2;

      final lowerTag = tag.toLowerCase();
      if (lowerTag.contains('wp-image-')) score += 2;
      if (lowerTag.contains('attachment-large') ||
          lowerTag.contains('size-large')) {
        score += 2;
      }

      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }

    return best;
  }

  bool _isRejectedAcademyImage(String imageUrl) {
    final lower = imageUrl.toLowerCase();

    const rejected = <String>[
      'logo',
      'favicon',
      'avatar',
      'placeholder',
      'whatsapp',
      'wa.me',
      'pedido',
      'pedidos',
      'soporte',
      'support',
      'header',
      'cabecera',
      'footer',
      'mundicamlogo',
      'logo-pdf',
      'payment',
      'pago-seguro',
      'icon-',
      '/icons/',
      'elementor-placeholder',
    ];

    for (final token in rejected) {
      if (lower.contains(token)) return true;
    }

    if (lower.contains('1x1') ||
        lower.contains('pixel') ||
        lower.contains('tracking')) {
      return true;
    }

    return false;
  }


  String _resolveWebUrl(String? value, Uri baseUri) {
    var raw = value?.trim() ?? '';
    if (raw.isEmpty) return '';

    raw = raw
        .replaceAll('&amp;', '&')
        .replaceAll('&#038;', '&');

    if (raw.startsWith('//')) {
      raw = '${baseUri.scheme}:$raw';
    }

    final parsed = Uri.tryParse(raw);
    if (parsed == null) return '';

    final resolved = parsed.hasScheme ? parsed : baseUri.resolveUri(parsed);
    if (resolved.scheme != 'http' && resolved.scheme != 'https') {
      return '';
    }

    return resolved.toString();
  }

}

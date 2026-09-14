import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:mundicam/features/mundicam_content/domain/models/mundicam_academy_event.dart';
import 'package:mundicam/features/mundicam_content/domain/models/mundicam_news_item.dart';
import 'package:mundicam/features/mundicam_content/domain/repositories/mundicam_content_repository.dart';

class WordPressRestContentRepository implements MundicamContentRepository {
  WordPressRestContentRepository()
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
  String? _academyCollectionPath;

  @override
  Future<List<MundicamNewsItem>> getNews() async {
    try {
      final response = await _dio.get(
        '/wp-json/wp/v2/posts',
        queryParameters: const <String, dynamic>{
          'per_page': 100,
          '_embed': 'true',
          'status': 'publish',
          'orderby': 'date',
          'order': 'desc',
        },
      );

      final raw = response.data is List
          ? List<dynamic>.from(response.data as List)
          : const <dynamic>[];

      return raw
          .whereType<Map>()
          .map(
            (post) => _newsFromWordPress(
              Map<String, dynamic>.from(post),
            ),
          )
          .where((item) => item.id > 0 && item.title.isNotEmpty)
          .toList();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('⚠️ Noticias WordPress no disponibles: $error');
      }
      return const <MundicamNewsItem>[];
    }
  }

  @override
  Future<List<MundicamAcademyEvent>> getAcademyEvents() async {
    try {
      final path = await _discoverAcademyCollectionPath();

      if (path == null || path.isEmpty) {
        if (kDebugMode) {
          debugPrint(
            '⚠️ Academy no expone un tipo REST detectable actualmente.',
          );
        }
        return const <MundicamAcademyEvent>[];
      }

      Response<dynamic> response;

      try {
        response = await _dio.get(
          path,
          queryParameters: const <String, dynamic>{
            'per_page': 100,
            '_embed': 'true',
            'status': 'publish',
          },
        );
      } on DioException {
        response = await _dio.get(
          path,
          queryParameters: const <String, dynamic>{
            'per_page': 100,
            '_embed': 'true',
          },
        );
      }

      final raw = response.data is List
          ? List<dynamic>.from(response.data as List)
          : const <dynamic>[];

      final events = raw
          .whereType<Map>()
          .map(
            (post) => _academyFromWordPress(
              Map<String, dynamic>.from(post),
            ),
          )
          .where((event) => event.id > 0 && event.title.isNotEmpty)
          .toList();

      events.sort((a, b) {
        final aDate = a.eventDate;
        final bDate = b.eventDate;

        if (aDate != null && bDate != null) {
          return aDate.compareTo(bDate);
        }
        if (aDate != null) return -1;
        if (bDate != null) return 1;
        return a.title.compareTo(b.title);
      });

      return events;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('⚠️ MundiCam Academy no disponible: $error');
      }
      return const <MundicamAcademyEvent>[];
    }
  }

  Future<String?> _discoverAcademyCollectionPath() async {
    if ((_academyCollectionPath ?? '').isNotEmpty) {
      return _academyCollectionPath;
    }

    final response = await _dio.get('/wp-json/wp/v2/types');
    final rawTypes = response.data;

    if (rawTypes is! Map) return null;

    String? routeForType(
      String typeKey,
      Map<String, dynamic> type,
    ) {
      final namespace =
          type['rest_namespace']?.toString().trim() ?? 'wp/v2';
      final restBase =
          type['rest_base']?.toString().trim() ?? typeKey.trim();

      if (restBase.isEmpty) return null;

      final cleanNamespace = namespace.isEmpty
          ? 'wp/v2'
          : namespace.replaceAll(RegExp(r'^/+|/+$'), '');

      return '/wp-json/$cleanNamespace/$restBase';
    }

    for (final entry in rawTypes.entries) {
      final value = entry.value;
      if (value is! Map) continue;

      final type = Map<String, dynamic>.from(value);
      final slug =
          type['slug']?.toString().trim().toLowerCase() ?? '';
      final restBase =
          type['rest_base']?.toString().trim().toLowerCase() ?? '';
      final archive =
          type['has_archive']?.toString().trim().toLowerCase() ?? '';
      final name =
          type['name']?.toString().trim().toLowerCase() ?? '';

      final isAcademy = slug == 'academy' ||
          restBase == 'academy' ||
          archive == 'academy' ||
          archive.endsWith('/academy') ||
          name.contains('academy');

      if (!isAcademy) continue;

      final route = routeForType(
        entry.key.toString(),
        type,
      );

      if (route == null) continue;

      _academyCollectionPath = route;
      return route;
    }

    // Segundo intento: búsqueda REST estándar. Solo descubre el subtype real;
    // no inventa el nombre del tipo de contenido ni una ruta propia.
    try {
      final searchResponse = await _dio.get(
        '/wp-json/wp/v2/search',
        queryParameters: const <String, dynamic>{
          'search': 'academy',
          'per_page': 100,
          'subtype': 'any',
        },
      );

      final items = searchResponse.data is List
          ? List<dynamic>.from(searchResponse.data as List)
          : const <dynamic>[];

      for (final item in items.whereType<Map>()) {
        final url =
            item['url']?.toString().trim().toLowerCase() ?? '';

        if (!url.contains('/academy/')) continue;

        final subtype = item['subtype']?.toString().trim() ?? '';
        if (subtype.isEmpty) continue;

        final rawType = rawTypes[subtype];
        if (rawType is! Map) continue;

        final route = routeForType(
          subtype,
          Map<String, dynamic>.from(rawType),
        );

        if (route == null) continue;

        _academyCollectionPath = route;
        return route;
      }
    } catch (_) {}

    return null;
  }

  MundicamNewsItem _newsFromWordPress(
    Map<String, dynamic> json,
  ) {
    final embedded = json['_embedded'];

    String imageUrl = '';
    if (embedded is Map &&
        embedded['wp:featuredmedia'] is List &&
        (embedded['wp:featuredmedia'] as List).isNotEmpty) {
      final media = (embedded['wp:featuredmedia'] as List).first;
      if (media is Map) {
        imageUrl = media['source_url']?.toString().trim() ?? '';
      }
    }

    return MundicamNewsItem(
      id: _asInt(json['id']),
      title: _htmlToText(_rendered(json['title'])),
      publishedDate: json['date']?.toString().trim() ?? '',
      imageUrl: imageUrl,
      excerpt: _htmlToText(_rendered(json['excerpt'])),
      content: _htmlToReadableText(_rendered(json['content'])),
      sourceUrl: json['link']?.toString().trim() ?? '',
    );
  }

  MundicamAcademyEvent _academyFromWordPress(
    Map<String, dynamic> json,
  ) {
    final contentHtml = _rendered(json['content']);
    final contentText = _htmlToReadableText(contentHtml);

    return MundicamAcademyEvent(
      id: _asInt(json['id']),
      title: _htmlToText(_rendered(json['title'])),
      eventDate: _extractEventDate(json, contentText),
      startTime: _extractTime(json, contentText),
      presenter: _extractPresenter(json, contentText),
      description: _htmlToText(_rendered(json['excerpt'])),
      imageUrl: _extractFeaturedImage(json).isNotEmpty
          ? _extractFeaturedImage(json)
          : _extractFirstImage(contentHtml),
      registrationUrl: json['link']?.toString().trim() ?? '',
    );
  }

  String _extractFeaturedImage(Map<String, dynamic> json) {
    final embedded = json['_embedded'];

    if (embedded is Map &&
        embedded['wp:featuredmedia'] is List &&
        (embedded['wp:featuredmedia'] as List).isNotEmpty) {
      final media = (embedded['wp:featuredmedia'] as List).first;
      if (media is Map) {
        return media['source_url']?.toString().trim() ?? '';
      }
    }

    return '';
  }

  String _extractFirstImage(String html) {
    final match = RegExp(
      r'''<img[^>]+src=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html);

    return match?.group(1)?.trim() ?? '';
  }

  DateTime? _extractEventDate(
    Map<String, dynamic> json,
    String text,
  ) {
    final structured = _findDateValue(json);
    if (structured != null) return structured;

    final numeric = RegExp(
      r'\b(\d{1,2})[/-](\d{1,2})[/-](\d{4})\b',
    ).firstMatch(text);

    if (numeric != null) {
      return DateTime(
        int.parse(numeric.group(3)!),
        int.parse(numeric.group(2)!),
        int.parse(numeric.group(1)!),
      );
    }

    const months = <String, int>{
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

    final spanish = RegExp(
      r'\b(\d{1,2})\s+de\s+'
      r'(enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|setiembre|octubre|noviembre|diciembre)'
      r'\s+de\s+(\d{4})\b',
      caseSensitive: false,
    ).firstMatch(text.toLowerCase());

    if (spanish == null) return null;

    return DateTime(
      int.parse(spanish.group(3)!),
      months[spanish.group(2)!.toLowerCase()]!,
      int.parse(spanish.group(1)!),
    );
  }

  DateTime? _findDateValue(dynamic value) {
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString().toLowerCase();
        final isCandidate =
            key.contains('event') && key.contains('date') ||
            key.contains('start') && key.contains('date') ||
            key.contains('fecha');

        if (isCandidate) {
          final parsed = _parseDate(entry.value);
          if (parsed != null) return parsed;
        }
      }

      for (final nested in value.values) {
        final parsed = _findDateValue(nested);
        if (parsed != null) return parsed;
      }
    }

    if (value is List) {
      for (final nested in value) {
        final parsed = _findDateValue(nested);
        if (parsed != null) return parsed;
      }
    }

    return null;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;

    final raw = value.toString().trim();
    if (raw.isEmpty) return null;

    final iso = DateTime.tryParse(raw);
    if (iso != null) {
      return DateTime(iso.year, iso.month, iso.day);
    }

    final slash = RegExp(
      r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$',
    ).firstMatch(raw);

    if (slash == null) return null;

    return DateTime(
      int.parse(slash.group(3)!),
      int.parse(slash.group(2)!),
      int.parse(slash.group(1)!),
    );
  }

  String _extractTime(
    Map<String, dynamic> json,
    String text,
  ) {
    final structured = _findTextValue(
      json,
      const <String>[
        'start_time',
        'event_time',
        'hora',
        'time',
      ],
    );

    if (structured != null && structured.isNotEmpty) {
      final match = RegExp(r'\b(\d{1,2}:\d{2})\b')
          .firstMatch(structured);
      if (match != null) return match.group(1) ?? '';
    }

    final match = RegExp(
      r'(?:hora(?:\s+de\s+inicio)?\s*:?\s*)'
      r'(\d{1,2}:\d{2})',
      caseSensitive: false,
    ).firstMatch(text);

    return match?.group(1)?.trim() ?? '';
  }

  String _extractPresenter(
    Map<String, dynamic> json,
    String text,
  ) {
    final structured = _findTextValue(
      json,
      const <String>[
        'presenter',
        'speaker',
        'ponente',
        'formador',
      ],
    );

    if (structured != null && structured.isNotEmpty) {
      return structured;
    }

    for (final pattern in <RegExp>[
      RegExp(
        r'ponente\s*:\s*(.+?)(?:\n|\.|$)',
        caseSensitive: false,
      ),
      RegExp(
        r'formador\s*:\s*(.+?)(?:\n|\.|$)',
        caseSensitive: false,
      ),
      RegExp(
        r'la formación estará impartida por\s+(.+?)(?:\n|\.|$)',
        caseSensitive: false,
      ),
    ]) {
      final match = pattern.firstMatch(text);
      final value = match?.group(1)?.trim() ?? '';
      if (value.isNotEmpty) return value;
    }

    return '';
  }

  String? _findTextValue(
    dynamic value,
    List<String> keyFragments,
  ) {
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString().toLowerCase();
        if (!keyFragments.any(key.contains)) continue;

        final raw = entry.value;
        if (raw is String && raw.trim().isNotEmpty) {
          return _htmlToText(raw);
        }
      }

      for (final nested in value.values) {
        final found = _findTextValue(
          nested,
          keyFragments,
        );
        if (found != null && found.isNotEmpty) return found;
      }
    }

    if (value is List) {
      for (final nested in value) {
        final found = _findTextValue(
          nested,
          keyFragments,
        );
        if (found != null && found.isNotEmpty) return found;
      }
    }

    return null;
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _rendered(dynamic value) {
    if (value is Map) {
      return value['rendered']?.toString() ?? '';
    }
    return '';
  }

  String _decodeEntities(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&#8211;', '–')
        .replaceAll('&#8212;', '—')
        .replaceAll('&#8216;', '‘')
        .replaceAll('&#8217;', '’')
        .replaceAll('&#8220;', '“')
        .replaceAll('&#8221;', '”')
        .replaceAll('&nbsp;', ' ');
  }

  String _htmlToText(String value) {
    return _decodeEntities(
      value
          .replaceAll(
            RegExp(
              r'<script[^>]*>.*?</script>',
              dotAll: true,
            ),
            ' ',
          )
          .replaceAll(
            RegExp(
              r'<style[^>]*>.*?</style>',
              dotAll: true,
            ),
            ' ',
          )
          .replaceAll(RegExp(r'<[^>]*>'), ' '),
    ).replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _htmlToReadableText(String value) {
    var text = value
        .replaceAll(
          RegExp(
            r'<script[^>]*>.*?</script>',
            dotAll: true,
          ),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'<style[^>]*>.*?</style>',
            dotAll: true,
          ),
          ' ',
        )
        .replaceAll(
          RegExp(r'<br\s*/?>', caseSensitive: false),
          '\n',
        )
        .replaceAll(
          RegExp(r'</p\s*>', caseSensitive: false),
          '\n\n',
        )
        .replaceAll(
          RegExp(r'</li\s*>', caseSensitive: false),
          '\n',
        )
        .replaceAll(RegExp(r'<[^>]*>'), ' ');

    return _decodeEntities(text)
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r' *\n *'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}

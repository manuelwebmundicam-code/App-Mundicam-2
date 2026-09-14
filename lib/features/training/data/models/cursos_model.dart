class CourseModel {
  final int id;
  final String title;
  final String excerpt;
  final String url;
  final String imageUrl;
  final DateTime? eventDate;
  final DateTime? publishedAt;
  final String startTime;
  final String presenter;
  final String contentText;
  final int featuredMediaId;

  const CourseModel({
    required this.id,
    required this.title,
    required this.excerpt,
    required this.url,
    required this.imageUrl,
    this.eventDate,
    this.publishedAt,
    this.startTime = '',
    this.presenter = '',
    this.contentText = '',
    this.featuredMediaId = 0,
  });

  factory CourseModel.fromWordPress(Map<String, dynamic> json) {
    final titleRaw = _rendered(json['title']);
    final excerptRaw = _rendered(json['excerpt']);
    final contentRaw = _rendered(json['content']);

    final title = _htmlToText(titleRaw);
    final excerpt = _htmlToText(excerptRaw);
    final contentText = _htmlToReadableText(contentRaw);
    final publishedAt = DateTime.tryParse(json['date']?.toString() ?? '');

    final embeddedImage = _featuredImage(json);
    final structuredImage = _findStructuredImageUrl(json);
    final contentImage = _firstImageFromHtml(contentRaw);

    final imageUrl = embeddedImage.isNotEmpty
        ? embeddedImage
        : (structuredImage.isNotEmpty ? structuredImage : contentImage);

    final eventDate =
        _findStructuredEventDate(json) ??
        _parseSpanishEventDate(
          contentText,
          fallbackYear: publishedAt?.year,
        );

    final startTime =
        _findTextValue(
          json,
          const <String>[
            'start_time',
            'event_time',
            'hora',
            'time',
          ],
        ) ??
        _parseTime(contentText);

    final presenter =
        _findTextValue(
          json,
          const <String>[
            'presenter',
            'speaker',
            'ponente',
            'formador',
          ],
        ) ??
        _parsePresenter(contentText);

    return CourseModel(
      id: _parseInt(json['id']),
      title: title.isNotEmpty ? title : 'Sin título',
      excerpt: excerpt,
      url: json['link']?.toString() ?? '',
      imageUrl: imageUrl,
      eventDate: eventDate,
      publishedAt: publishedAt,
      startTime: startTime,
      presenter: presenter,
      contentText: contentText,
      featuredMediaId: _parseInt(json['featured_media']),
    );
  }

  static String _rendered(dynamic value) {
    if (value is Map) {
      return value['rendered']?.toString() ?? '';
    }
    return '';
  }

  static int _parseInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _featuredImage(Map<String, dynamic> json) {
    final embedded = json['_embedded'];
    if (embedded is Map &&
        embedded['wp:featuredmedia'] is List &&
        (embedded['wp:featuredmedia'] as List).isNotEmpty) {
      final media = (embedded['wp:featuredmedia'] as List).first;
      if (media is Map) {
        final source = _cleanImageUrl(media['source_url']);
        if (source.isNotEmpty) return source;

        final details = media['media_details'];
        if (details is Map && details['sizes'] is Map) {
          final sizes = details['sizes'] as Map;
          for (final sizeName in const <String>[
            'full',
            'large',
            'medium_large',
            'medium',
            'thumbnail',
          ]) {
            final size = sizes[sizeName];
            if (size is Map) {
              final candidate = _cleanImageUrl(size['source_url']);
              if (candidate.isNotEmpty) return candidate;
            }
          }
        }
      }
    }
    return '';
  }

  static String _findStructuredImageUrl(dynamic value, [int depth = 0]) {
    if (depth > 6) return '';

    if (value is Map) {
      const directKeys = <String>{
        'image',
        'image_url',
        'imageurl',
        'featured_image',
        'featured_image_url',
        'featuredimage',
        'featuredimageurl',
        'thumbnail',
        'thumbnail_url',
        'banner',
        'banner_url',
        'event_image',
        'event_image_url',
        'mec_featured_image',
      };

      for (final entry in value.entries) {
        final key = entry.key.toString().toLowerCase().replaceAll('-', '_');
        if (!directKeys.contains(key) &&
            !key.endsWith('_image') &&
            !key.endsWith('_image_url')) {
          continue;
        }

        final candidate = _imageUrlFromDynamic(entry.value, depth + 1);
        if (candidate.isNotEmpty) return candidate;
      }

      for (final nested in value.values) {
        final candidate = _findStructuredImageUrl(nested, depth + 1);
        if (candidate.isNotEmpty) return candidate;
      }
    }

    if (value is List) {
      for (final nested in value) {
        final candidate = _findStructuredImageUrl(nested, depth + 1);
        if (candidate.isNotEmpty) return candidate;
      }
    }

    return '';
  }

  static String _imageUrlFromDynamic(dynamic value, [int depth = 0]) {
    if (depth > 6) return '';

    if (value is String) {
      return _cleanImageUrl(value);
    }

    if (value is Map) {
      for (final key in const <String>[
        'source_url',
        'url',
        'src',
        'full',
        'large',
      ]) {
        final candidate = _cleanImageUrl(value[key]);
        if (candidate.isNotEmpty) return candidate;
      }

      for (final nested in value.values) {
        final candidate = _imageUrlFromDynamic(nested, depth + 1);
        if (candidate.isNotEmpty) return candidate;
      }
    }

    if (value is List) {
      for (final nested in value) {
        final candidate = _imageUrlFromDynamic(nested, depth + 1);
        if (candidate.isNotEmpty) return candidate;
      }
    }

    return '';
  }

  static String _firstImageFromHtml(String html) {
    if (html.trim().isEmpty) return '';

    final patterns = <RegExp>[
      RegExp(
        r'''<img[^>]+(?:data-lazy-src|data-src|data-original|src)=["']([^"']+)["']''',
        caseSensitive: false,
      ),
      RegExp(
        r'''<source[^>]+srcset=["']([^"' ,]+)''',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      final candidate = _cleanImageUrl(match?.group(1));
      if (candidate.isNotEmpty) return candidate;
    }

    return '';
  }

  static String _cleanImageUrl(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return '';

    final decoded = raw
        .replaceAll('&amp;', '&')
        .replaceAll('&#038;', '&');

    final uri = Uri.tryParse(decoded);
    if (uri == null) return '';

    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return decoded;
    }

    if (decoded.startsWith('//')) {
      return 'https:$decoded';
    }

    return '';
  }

  static String _decodeEntities(String value) {
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

  static String _htmlToText(String value) {
    return _decodeEntities(
      value
          .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), ' ')
          .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), ' ')
          .replaceAll(RegExp(r'<[^>]*>'), ' '),
    ).replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _htmlToReadableText(String value) {
    var text = value
        .replaceAll(
          RegExp(r'<script[^>]*>.*?</script>', dotAll: true),
          ' ',
        )
        .replaceAll(
          RegExp(r'<style[^>]*>.*?</style>', dotAll: true),
          ' ',
        )
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</h[1-6]\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</li\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), ' ');

    return _decodeEntities(text)
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r' *\n *'), '\n')
        .replaceAll(RegExp(r'\n{2,}'), '\n')
        .trim();
  }

  static DateTime? _findStructuredEventDate(dynamic value) {
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString().toLowerCase();
        final candidate = entry.value;

        final looksLikeEventDate =
            key.contains('event') && key.contains('date') ||
            key.contains('start') && key.contains('date') ||
            key.contains('fecha');

        if (looksLikeEventDate) {
          final parsed = _parseDateValue(candidate);
          if (parsed != null) return parsed;
        }
      }

      for (final nested in value.values) {
        final parsed = _findStructuredEventDate(nested);
        if (parsed != null) return parsed;
      }
    }

    if (value is List) {
      for (final nested in value) {
        final parsed = _findStructuredEventDate(nested);
        if (parsed != null) return parsed;
      }
    }

    return null;
  }

  static DateTime? _parseDateValue(dynamic value) {
    if (value == null) return null;

    if (value is num) {
      final raw = value.toInt();
      if (raw > 1000000000) {
        return DateTime.fromMillisecondsSinceEpoch(
          raw > 1000000000000 ? raw : raw * 1000,
        );
      }
    }

    final text = value.toString().trim();
    if (text.isEmpty) return null;

    final iso = DateTime.tryParse(text);
    if (iso != null) return iso;

    final slash = RegExp(r'\b(\d{1,2})[/-](\d{1,2})[/-](\d{4})\b')
        .firstMatch(text);
    if (slash != null) {
      return DateTime(
        int.parse(slash.group(3)!),
        int.parse(slash.group(2)!),
        int.parse(slash.group(1)!),
      );
    }

    return null;
  }

  static DateTime? _parseSpanishEventDate(
    String text, {
    int? fallbackYear,
  }) {
    final lower = text.toLowerCase();

    final numeric = RegExp(
      r'\b(\d{1,2})[/-](\d{1,2})[/-](\d{4})\b',
    ).firstMatch(lower);

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

    final withYear = RegExp(
      r'\b(\d{1,2})\s+de\s+'
      r'(enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|setiembre|octubre|noviembre|diciembre)'
      r'\s+de\s+(\d{4})\b',
      caseSensitive: false,
    ).firstMatch(lower);

    if (withYear != null) {
      return DateTime(
        int.parse(withYear.group(3)!),
        months[withYear.group(2)!.toLowerCase()]!,
        int.parse(withYear.group(1)!),
      );
    }

    final withoutYear = RegExp(
      r'\b(\d{1,2})\s+de\s+'
      r'(enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|setiembre|octubre|noviembre|diciembre)\b',
      caseSensitive: false,
    ).firstMatch(lower);

    if (withoutYear != null && fallbackYear != null) {
      return DateTime(
        fallbackYear,
        months[withoutYear.group(2)!.toLowerCase()]!,
        int.parse(withoutYear.group(1)!),
      );
    }

    return null;
  }

  static String _parseTime(String text) {
    final match = RegExp(
      r'(?:hora(?:\s+de\s+inicio)?|hora)\s*:?\s*(\d{1,2}:\d{2})',
      caseSensitive: false,
    ).firstMatch(text);

    if (match != null) {
      return match.group(1)?.trim() ?? '';
    }

    final loose = RegExp(r'\b(\d{1,2}:\d{2})\s*h?\b').firstMatch(text);
    return loose?.group(1)?.trim() ?? '';
  }

  static String _parsePresenter(String text) {
    final patterns = <RegExp>[
      RegExp(
        r'la formación estará impartida por\s+(.+?)(?:\n|\.|$)',
        caseSensitive: false,
      ),
      RegExp(
        r'formador\s*:\s*(.+?)(?:\n|\.|$)',
        caseSensitive: false,
      ),
      RegExp(
        r'ponente\s*:\s*(.+?)(?:\n|\.|$)',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      final value = match?.group(1)?.trim() ?? '';
      if (value.isNotEmpty) return value;
    }

    return '';
  }

  static String? _findTextValue(
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
        final result = _findTextValue(nested, keyFragments);
        if (result != null && result.isNotEmpty) return result;
      }
    }

    if (value is List) {
      for (final nested in value) {
        final result = _findTextValue(nested, keyFragments);
        if (result != null && result.isNotEmpty) return result;
      }
    }

    return null;
  }
}

class Noticia {
  final int id;
  final String titulo;
  final String fecha;
  final String imagenUrl;
  final String link;
  final String resumen;
  final String contenido;

  const Noticia({
    required this.id,
    required this.titulo,
    required this.fecha,
    required this.imagenUrl,
    required this.link,
    this.resumen = '',
    this.contenido = '',
  });

  factory Noticia.fromJson(Map<String, dynamic> json) {
    String imageUrl = '';

    final embedded = json['_embedded'];
    if (embedded is Map &&
        embedded['wp:featuredmedia'] is List &&
        (embedded['wp:featuredmedia'] as List).isNotEmpty) {
      final media = (embedded['wp:featuredmedia'] as List).first;
      if (media is Map) {
        imageUrl = media['source_url']?.toString() ?? '';
      }
    }

    final titleRaw = _rendered(json['title']);
    final excerptRaw = _rendered(json['excerpt']);
    final contentRaw = _rendered(json['content']);

    return Noticia(
      id: _parseInt(json['id']),
      titulo: _htmlToText(titleRaw).isNotEmpty
          ? _htmlToText(titleRaw)
          : 'Sin título',
      fecha: json['date']?.toString() ?? '',
      imagenUrl: imageUrl,
      link: json['link']?.toString() ?? '',
      resumen: _htmlToText(excerptRaw),
      contenido: _htmlToReadableText(contentRaw),
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
        .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'</h[1-6]\s*>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'</li\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '• ')
        .replaceAll(RegExp(r'<[^>]*>'), ' ');

    text = _decodeEntities(text)
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r' *\n *'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    return text;
  }
}

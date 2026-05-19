class CourseModel {
  final int id;
  final String title;
  final String excerpt;
  final String url;
  final String imageUrl;

  CourseModel({
    required this.id,
    required this.title,
    required this.excerpt,
    required this.url,
    required this.imageUrl,
  });

  factory CourseModel.fromWordPress(Map<String, dynamic> json) {
    // Función interna para limpiar HTML y espacios del JSON
    String cleanHtml(String html) {
      return html.replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), '').trim();
    }

    // Buscamos la imagen en el contenido si no hay destacada
    String content = json['content']?['rendered'] ?? '';
    RegExp imgRegExp = RegExp(r'src="([^"]+)"');
    Iterable<RegExpMatch> matches = imgRegExp.allMatches(content);

    String img = 'https://via.placeholder.com/400x200'; // Fallback
    if (matches.isNotEmpty) {
      img = matches.first.group(1) ?? img;
    }

    return CourseModel(
      id: json['id'] ?? 0,
      title: cleanHtml(json['title']?['rendered'] ?? 'Sin título'),
      excerpt: cleanHtml(json['title']?['rendered']),
      url: json['link'] ?? '',
      imageUrl: img,
    );
  }
}

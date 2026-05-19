class Noticia {
  final int id;
  final String titulo;
  final String fecha;
  final String imagenUrl;
  final String link;

  const Noticia({
    required this.id,
    required this.titulo,
    required this.fecha,
    required this.imagenUrl,
    required this.link,
  });

  factory Noticia.fromJson(Map<String, dynamic> json) {
    String imageUrl = '';

    final embedded = json['_embedded'];
    if (embedded != null &&
        embedded['wp:featuredmedia'] != null &&
        embedded['wp:featuredmedia'] is List &&
        (embedded['wp:featuredmedia'] as List).isNotEmpty) {
      imageUrl =
          embedded['wp:featuredmedia'][0]['source_url']?.toString() ?? '';
    }

    return Noticia(
      id: json['id'] ?? 0,
      titulo: json['title']?['rendered']?.toString() ?? 'Sin título',
      fecha: json['date']?.toString() ?? '',
      imagenUrl: imageUrl,
      link: json['link']?.toString() ?? '',
    );
  }
}

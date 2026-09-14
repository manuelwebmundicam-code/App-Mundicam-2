class PromotionModel {
  final int id;
  final String title;
  final String imageUrl;
  final String webUrl;
  final DateTime? publishedAt;

  const PromotionModel({
    required this.id,
    required this.title,
    required this.imageUrl,
    this.webUrl = '',
    this.publishedAt,
  });

  factory PromotionModel.fromJson(Map<String, dynamic> json) {
    final rawDate = json['fecha_publicacion']?.toString().trim() ?? '';

    return PromotionModel(
      id: _parseInt(json['id']),
      title: json['titulo']?.toString().trim() ?? '',
      imageUrl: json['imagen_url']?.toString().trim() ?? '',
      webUrl: _firstWebUrl(json),
      publishedAt: rawDate.isEmpty ? null : DateTime.tryParse(rawDate),
    );
  }

  bool get hasImage => imageUrl.trim().isNotEmpty;

  static String _firstWebUrl(Map<String, dynamic> json) {
    for (final key in const <String>[
      'web_url',
      'url',
      'link',
      'enlace',
      'permalink',
    ]) {
      final value = json[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString().trim() ?? '') ?? 0;
  }
}

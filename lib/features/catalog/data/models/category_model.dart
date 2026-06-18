// lib/features/catalog/data/models/category_model.dart

class CategoryModel {
  final int id;
  final String name;
  final String slug;
  final int parent;
  final int count;

  /// Campo compatible con pantallas antiguas.
  /// En la app MundiCam las imágenes de categoría se pintan desde assets locales
  /// o iconos, no desde WordPress/API. Se conserva para no romper código existente.
  final String image;

  /// Alias compatible para código que use imageUrl.
  String get imageUrl => image;

  /// Alias compatible para código que use imageSrc.
  String get imageSrc => image;

  /// Campos opcionales por compatibilidad con respuestas WooCommerce/Store API.
  final String description;
  final int menuOrder;
  final String display;

  const CategoryModel({
    required this.id,
    required this.name,
    this.slug = '',
    this.parent = 0,
    this.count = 0,
    String? image,
    String? imageUrl,
    String? imageSrc,
    this.description = '',
    this.menuOrder = 0,
    this.display = '',
  }) : image = image ?? imageUrl ?? imageSrc ?? '';

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: _parseInt(json['id'] ?? json['term_id'] ?? json['category_id']),
      name: _decodeHtml(json['name']?.toString() ?? ''),
      slug: json['slug']?.toString() ?? '',
      parent: _parseInt(json['parent'] ?? json['parent_id']),
      count: _parseInt(json['count'] ?? json['product_count'] ?? json['total']),
      image: _extractImageUrl(
        json['image'] ??
            json['image_url'] ??
            json['imageUrl'] ??
            json['thumbnail'] ??
            json['thumbnail_url'],
      ),
      description: _decodeHtml(json['description']?.toString() ?? ''),
      menuOrder: _parseInt(json['menu_order'] ?? json['menuOrder']),
      display: json['display']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'slug': slug,
      'parent': parent,
      'count': count,
      'image': {
        'id': 0,
        'src': image,
        'url': image,
      },
      'image_url': image,
      'description': description,
      'menu_order': menuOrder,
      'display': display,
    };
  }

  CategoryModel copyWith({
    int? id,
    String? name,
    String? slug,
    int? parent,
    int? count,
    String? image,
    String? imageUrl,
    String? description,
    int? menuOrder,
    String? display,
  }) {
    return CategoryModel(
      id: id ?? this.id,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      parent: parent ?? this.parent,
      count: count ?? this.count,
      image: image ?? imageUrl ?? this.image,
      description: description ?? this.description,
      menuOrder: menuOrder ?? this.menuOrder,
      display: display ?? this.display,
    );
  }

  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();

    final raw = value.toString().trim();
    if (raw.isEmpty || raw.toLowerCase() == 'null') return 0;

    return int.tryParse(raw) ?? double.tryParse(raw)?.toInt() ?? 0;
  }

  static String _decodeHtml(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
  }

  static String _extractImageUrl(dynamic value) {
    if (value == null) return '';

    if (value is String) {
      final clean = value.trim();
      if (clean.isEmpty ||
          clean.toLowerCase() == 'null' ||
          clean.toLowerCase() == 'false') {
        return '';
      }
      return clean;
    }

    if (value is Map) {
      final map = Map<dynamic, dynamic>.from(value);
      for (final key in const [
        'src',
        'url',
        'source_url',
        'image',
        'image_url',
        'thumbnail',
        'thumbnail_url',
        'medium',
        'full',
      ]) {
        final extracted = _extractImageUrl(map[key]);
        if (extracted.isNotEmpty) return extracted;
      }
      return '';
    }

    if (value is List) {
      for (final item in value) {
        final extracted = _extractImageUrl(item);
        if (extracted.isNotEmpty) return extracted;
      }
      return '';
    }

    return '';
  }
}

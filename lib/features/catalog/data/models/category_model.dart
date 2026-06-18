class CategoryModel {
  final int id;
  final String name;
  final String slug;
  final String imageUrl;
  final int parent;
  final int count;
  final int menuOrder;

  const CategoryModel({
    required this.id,
    required this.name,
    required this.slug,
    required this.imageUrl,
    required this.parent,
    required this.count,
    required this.menuOrder,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: _parseInt(json['id']),
      name: _parseString(json['name'], fallback: 'Sin nombre'),
      slug: _parseString(json['slug']),
      // No dependemos de la imagen de WordPress/API.
      // La pantalla de categorías puede usar iconos o assets locales.
      imageUrl: _parseImageUrl(json['image']),
      parent: _parseInt(json['parent']),
      count: _parseInt(json['count']),
      menuOrder: _parseInt(json['menu_order']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'slug': slug,
      'image': imageUrl.isEmpty
          ? null
          : {
        'src': imageUrl,
      },
      'parent': parent,
      'count': count,
      'menu_order': menuOrder,
    };
  }

  CategoryModel copyWith({
    int? id,
    String? name,
    String? slug,
    String? imageUrl,
    int? parent,
    int? count,
    int? menuOrder,
  }) {
    return CategoryModel(
      id: id ?? this.id,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      imageUrl: imageUrl ?? this.imageUrl,
      parent: parent ?? this.parent,
      count: count ?? this.count,
      menuOrder: menuOrder ?? this.menuOrder,
    );
  }

  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();

    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return 0;

    return int.tryParse(text) ?? double.tryParse(text)?.toInt() ?? 0;
  }

  static String _parseString(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;

    final text = value.toString().trim();

    if (text.isEmpty || text.toLowerCase() == 'null') {
      return fallback;
    }

    return text;
  }

  static String _parseImageUrl(dynamic image) {
    // Para tu caso actual podemos devolver siempre vacío y usar iconos/assets.
    // Pero lo dejamos blindado por si en el futuro vuelve una URL válida.
    if (image == null) return '';

    if (image is String) {
      final text = image.trim();
      if (text.isEmpty || text.toLowerCase() == 'null') return '';
      return text.startsWith('http') ? text : '';
    }

    if (image is Map) {
      final map = Map<dynamic, dynamic>.from(image);

      final candidates = [
        map['src'],
        map['url'],
        map['source_url'],
        map['image_url'],
      ];

      for (final candidate in candidates) {
        final text = candidate?.toString().trim() ?? '';
        if (text.isNotEmpty &&
            text.toLowerCase() != 'null' &&
            text.startsWith('http')) {
          return text;
        }
      }

      return '';
    }

    if (image is List && image.isNotEmpty) {
      for (final item in image) {
        final parsed = _parseImageUrl(item);
        if (parsed.isNotEmpty) return parsed;
      }
    }

    return '';
  }
}
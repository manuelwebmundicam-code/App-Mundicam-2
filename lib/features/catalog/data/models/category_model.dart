// ARCHIVO: lib/features/catalog/data/models/category_model.dart
// Sustituye el archivo completo por este contenido.

// lib/features/catalog/data/models/category_model.dart

class CategoryModel {
  final int id;
  final String name;
  final String slug;

  /// URL de imagen remota si WordPress/PHP la devuelve.
  /// En MundiCam muchas categorías pueden seguir usando assets locales o iconos,
  /// por eso este campo puede venir vacío sin romper la app.
  final String imageUrl;

  /// Alias compatible con pantallas antiguas que usan `image`.
  String get image => imageUrl;

  /// Alias compatible con pantallas antiguas que usan `imageSrc`.
  String get imageSrc => imageUrl;

  final int parent;
  final int count;

  /// null = backend antiguo/no informa; true/false = dato explícito del PHP.
  /// Permite abrir una hoja directamente sin hacer una petición extra, pero
  /// conserva compatibilidad con servidores anteriores.
  final bool? hasChildren;
  final int childrenCount;

  final int menuOrder;

  /// Compatibilidad con respuestas WooCommerce / Store API / plugin propio.
  final String description;
  final String display;

  const CategoryModel({
    required this.id,
    required this.name,
    this.slug = '',
    this.imageUrl = '',
    this.parent = 0,
    this.count = 0,
    this.hasChildren,
    this.childrenCount = 0,
    this.menuOrder = 0,
    this.description = '',
    this.display = '',
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: _parseInt(json['id'] ?? json['term_id'] ?? json['category_id']),
      name: _decodeHtml(
        _firstNonEmptyString([
          json['name'],
          json['title'],
          json['label'],
        ], fallback: 'Sin nombre'),
      ),
      slug: _firstNonEmptyString([
        json['slug'],
      ]),
      imageUrl: _extractImageUrl(
        json['image'] ??
            json['image_url'] ??
            json['imageUrl'] ??
            json['image_src'] ??
            json['imageSrc'] ??
            json['thumbnail'] ??
            json['thumbnail_url'] ??
            json['thumbnailUrl'],
      ),
      parent: _parseInt(json['parent'] ?? json['parent_id']),
      count: _parseInt(json['count'] ?? json['product_count'] ?? json['total']),
      hasChildren: _parseNullableBool(
        json.containsKey('has_children')
            ? json['has_children']
            : json.containsKey('hasChildren')
                ? json['hasChildren']
                : null,
      ),
      childrenCount: _parseInt(json['children_count'] ?? json['childrenCount']),
      menuOrder: _parseInt(json['menu_order'] ?? json['menuOrder'] ?? json['order']),
      description: _decodeHtml(json['description']?.toString() ?? ''),
      display: json['display']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'slug': slug,
      'image': {
        'id': 0,
        'src': imageUrl,
        'url': imageUrl,
      },
      'image_url': imageUrl,
      'parent': parent,
      'count': count,
      if (hasChildren != null) 'has_children': hasChildren,
      'children_count': childrenCount,
      'menu_order': menuOrder,
      'description': description,
      'display': display,
    };
  }

  CategoryModel copyWith({
    int? id,
    String? name,
    String? slug,
    String? imageUrl,
    String? image,
    String? imageSrc,
    int? parent,
    int? count,
    bool? hasChildren,
    bool clearHasChildren = false,
    int? childrenCount,
    int? menuOrder,
    String? description,
    String? display,
  }) {
    return CategoryModel(
      id: id ?? this.id,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      imageUrl: imageUrl ?? image ?? imageSrc ?? this.imageUrl,
      parent: parent ?? this.parent,
      count: count ?? this.count,
      hasChildren: clearHasChildren ? null : (hasChildren ?? this.hasChildren),
      childrenCount: childrenCount ?? this.childrenCount,
      menuOrder: menuOrder ?? this.menuOrder,
      description: description ?? this.description,
      display: display ?? this.display,
    );
  }

  static bool? _parseNullableBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;

    final normalized = value.toString().trim().toLowerCase();
    if (normalized.isEmpty || normalized == 'null') return null;
    if (['1', 'true', 'yes', 'si', 'sí'].contains(normalized)) return true;
    if (['0', 'false', 'no'].contains(normalized)) return false;
    return null;
  }

  static int _parseInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();

    final raw = value.toString().trim();
    if (raw.isEmpty || raw.toLowerCase() == 'null') return fallback;

    return int.tryParse(raw) ?? double.tryParse(raw.replaceAll(',', '.'))?.toInt() ?? fallback;
  }

  static String _firstNonEmptyString(
      List<dynamic> values, {
        String fallback = '',
      }) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }
    return fallback;
  }

  static String _decodeHtml(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#034;', '"')
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
        'imageUrl',
        'thumbnail',
        'thumbnail_url',
        'thumbnailUrl',
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


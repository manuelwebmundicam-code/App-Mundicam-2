class Product {
  final int id;
  final String name;
  final String price;
  final String regularPrice;
  final String imageUrl;
  final String sku;
  final int stockQuantity;
  final bool onSale;
  final bool isInstock;
  final String shortDescription;
  final String description;
  final List<ProductAttribute> attributes;

  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.regularPrice,
    required this.imageUrl,
    required this.stockQuantity,
    required this.sku,
    required this.onSale,
    required this.isInstock,
    required this.shortDescription,
    required this.description,
    required this.attributes,
  });

  // =========================
  // CONTROL REAL DE STOCK
  // =========================

  bool get hasStock {
    if (stockQuantity > 0) {
      return true;
    }

    if (isInstock) {
      return true;
    }

    return false;
  }

  // =========================
  // MÁXIMO COMPRABLE
  // =========================

  int get maxPurchaseQty {
    if (stockQuantity > 0) {
      return stockQuantity;
    }

    if (isInstock) {
      return 999;
    }

    return 0;
  }

  // =========================
  // MARCA
  // =========================

  String? get brandName {
    for (final attr in attributes) {
      final attrName = attr.name.toLowerCase().trim();

      if ((attrName.contains('marca') ||
          attrName.contains('brand') ||
          attrName == 'pa_marca') &&
          attr.options.isNotEmpty) {
        final value = attr.options.first.trim();
        if (value.isNotEmpty) return value;
      }
    }

    return null;
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    // =========================
    // IMAGEN
    // =========================

    String firstImage = 'https://via.placeholder.com/150';

    if (json['images'] != null && (json['images'] as List).isNotEmpty) {
      firstImage = json['images'][0]['src'] ?? firstImage;
    }

    // =========================
    // DESCRIPCIÓN CORTA
    // =========================

    final String rawShort = json['short_description']?.toString() ?? '';

    final String cleanShort = rawShort.replaceAll(
      RegExp(r'<[^>]*>|&[^;]+;'),
      '',
    );

    // =========================
    // DESCRIPCIÓN LARGA
    // =========================

    final String rawLong = json['description']?.toString() ?? '';

    final String cleanLong = rawLong.replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), '');

    // =========================
    // ATRIBUTOS + MARCA
    // =========================

    final parsedAttributes =
        (json['attributes'] as List?)
            ?.map((attr) => ProductAttribute.fromJson(attr))
            .toList() ??
            <ProductAttribute>[];

    final extractedBrand = _extractBrandFromJson(json);

    final hasMarcaAttribute = parsedAttributes.any((attr) {
      final name = attr.name.toLowerCase().trim();
      return name.contains('marca') || name.contains('brand') || name == 'pa_marca';
    });

    if (extractedBrand != null &&
        extractedBrand.trim().isNotEmpty &&
        !hasMarcaAttribute) {
      parsedAttributes.add(
        ProductAttribute(
          name: 'Marca',
          options: [extractedBrand.trim()],
        ),
      );
    }

    return Product(
      id: _parseInt(json['id']),

      name: json['name'] ?? 'Sin nombre',

      price: (json['price'] ?? '0.00').toString(),

      regularPrice: (json['regular_price'] ?? '').toString(),

      imageUrl: firstImage,

      sku: (json['sku'] ?? '').toString(),

      stockQuantity: _parseInt(json['stock_quantity']),

      onSale: json['on_sale'] ?? false,

      isInstock: json['stock_status']?.toString() == 'instock',

      shortDescription: cleanShort.trim().isEmpty
          ? 'Sin descripción'
          : cleanShort.trim(),

      description: cleanLong.trim().isEmpty
          ? 'Sin descripción detallada'
          : cleanLong.trim(),

      attributes: parsedAttributes,
    );
  }

  static String? _extractBrandFromJson(Map<String, dynamic> json) {
    final directBrand = json['brand'];
    if (directBrand != null) {
      if (directBrand is String && directBrand.trim().isNotEmpty) {
        return directBrand.trim();
      }

      if (directBrand is Map) {
        final name = directBrand['name']?.toString().trim();
        if (name != null && name.isNotEmpty) return name;
      }
    }

    final brands = json['brands'];
    if (brands is List && brands.isNotEmpty) {
      final firstBrand = brands.first;

      if (firstBrand is String && firstBrand.trim().isNotEmpty) {
        return firstBrand.trim();
      }

      if (firstBrand is Map) {
        final name = firstBrand['name']?.toString().trim();
        if (name != null && name.isNotEmpty) return name;

        final slug = firstBrand['slug']?.toString().trim();
        if (slug != null && slug.isNotEmpty) return slug;
      }
    }

    final categories = json['categories'];
    if (categories is List && categories.isNotEmpty) {
      for (final category in categories) {
        if (category is! Map) continue;

        final name = category['name']?.toString().trim();
        final slug = category['slug']?.toString().trim();

        final candidate = name ?? slug;
        if (candidate == null || candidate.isEmpty) continue;

        final lower = candidate.toLowerCase();

        const knownBrands = [
          'dahua',
          'hikvision',
          'ajax',
          'ksenia',
          'tplink',
          'tp-link',
          'mobotix',
          'teletek',
          'wisat',
          'wisim',
          'evolve',
          'secury360',
        ];

        for (final brand in knownBrands) {
          if (lower == brand || lower.contains(brand)) {
            return candidate;
          }
        }
      }
    }

    return null;
  }

  static int _parseInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'price': price,
    'regular_price': regularPrice,
    'images': [
      {'src': imageUrl},
    ],
    'sku': sku,
    'on_sale': onSale,
    'stock_status': isInstock ? 'instock' : 'outofstock',
    'short_description': shortDescription,
    'description': description,
    'attributes': attributes.map((a) => a.toJson()).toList(),
  };
}

class ProductAttribute {
  final String name;
  final List<String> options;

  ProductAttribute({required this.name, required this.options});

  factory ProductAttribute.fromJson(Map<String, dynamic> json) {
    return ProductAttribute(
      name: json['name'] ?? '',
      options: List<String>.from(json['options'] ?? []),
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'options': options};
}
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
  final List<StockLocation>? stockLocations;

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
    this.stockLocations,
  });

  // =========================
  // STOCK DETALLADO
  // =========================

  int get totalStockLocations {
    final locations = stockLocations;
    if (locations == null || locations.isEmpty) return 0;

    return locations.fold<int>(
      0,
          (total, location) => total + (location.quantity > 0 ? location.quantity : 0),
    );
  }

  bool get hasStockLocations {
    final locations = stockLocations;
    return locations != null && locations.isNotEmpty;
  }

  // =========================
  // CONTROL REAL DE STOCK
  // =========================

  bool get hasStock {
    // Si WooCommerce devuelve stock por almacén, usamos ese dato como prioridad.
    // Así evitamos mostrar compra si stock_status dice instock pero General/Murcia están a 0.
    if (hasStockLocations) {
      return totalStockLocations > 0;
    }

    if (stockQuantity > 0) {
      return true;
    }

    return isInstock;
  }

  // =========================
  // MÁXIMO COMPRABLE
  // =========================

  int get maxPurchaseQty {
    if (hasStockLocations) {
      return totalStockLocations;
    }

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
      final attrName = _normalizeText(attr.name);

      if ((attrName.contains('marca') ||
          attrName.contains('brand') ||
          attrName == 'pamarca') &&
          attr.options.isNotEmpty) {
        final value = attr.options.first.trim();
        if (value.isNotEmpty) return value;
      }
    }

    return null;
  }

  // =========================
  // STOCK DETALLADO PARA ADMIN/COMERCIAL
  // =========================

  String? get stockDetailsText {
    final locations = stockLocations;
    if (locations == null || locations.isEmpty) return null;

    final buffer = StringBuffer();

    for (final loc in locations) {
      if (buffer.isNotEmpty) buffer.write(' | ');
      buffer.write('${loc.name}: ${loc.quantity}');
    }

    return buffer.toString();
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    // =========================
    // IMAGEN
    // =========================

    String firstImage = 'https://via.placeholder.com/150';

    final images = json['images'];
    if (images is List && images.isNotEmpty) {
      final first = images.first;
      if (first is Map) {
        final src = first['src']?.toString().trim();
        if (src != null && src.isNotEmpty) {
          firstImage = src;
        }
      }
    }

    // =========================
    // DESCRIPCIONES
    // =========================

    final String rawShort = json['short_description']?.toString() ?? '';
    final String rawLong = json['description']?.toString() ?? '';

    final String cleanShort = _cleanHtml(rawShort);
    final String cleanLong = _cleanHtml(rawLong);

    // =========================
    // ATRIBUTOS + MARCA
    // =========================

    final parsedAttributes = (json['attributes'] as List?)
        ?.whereType<Map>()
        .map((attr) => ProductAttribute.fromJson(Map<String, dynamic>.from(attr)))
        .toList() ??
        <ProductAttribute>[];

    final extractedBrand = _extractBrandFromJson(json);

    final hasMarcaAttribute = parsedAttributes.any((attr) {
      final name = _normalizeText(attr.name);
      return name.contains('marca') || name.contains('brand') || name == 'pamarca';
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

    // =========================
    // STOCK MULTI-ALMACÉN
    // =========================

    final stockLocations = _extractStockLocationsFromJson(json);

    return Product(
      id: _parseInt(json['id']),
      name: (json['name'] ?? 'Sin nombre').toString(),
      price: (json['price'] ?? '0.00').toString(),
      regularPrice: (json['regular_price'] ?? '').toString(),
      imageUrl: firstImage,
      sku: (json['sku'] ?? '').toString(),
      stockQuantity: _parseInt(json['stock_quantity']),
      onSale: json['on_sale'] == true,
      isInstock: json['stock_status']?.toString() == 'instock',
      shortDescription: cleanShort.trim().isEmpty
          ? 'Sin descripción'
          : cleanShort.trim(),
      description: cleanLong.trim().isEmpty
          ? 'Sin descripción detallada'
          : cleanLong.trim(),
      attributes: parsedAttributes,
      stockLocations: stockLocations,
    );
  }

  static List<StockLocation>? _extractStockLocationsFromJson(
      Map<String, dynamic> json,
      ) {
    final locations = <StockLocation>[];

    // Formato directo por si en el futuro el endpoint propio devuelve stock_locations.
    final rawStockLocations = json['stock_locations'] ?? json['stockLocations'];
    if (rawStockLocations is List) {
      for (final rawLocation in rawStockLocations) {
        if (rawLocation is! Map) continue;

        final name = rawLocation['name']?.toString().trim() ??
            rawLocation['location']?.toString().trim() ??
            rawLocation['almacen']?.toString().trim() ??
            '';

        final quantity = _parseInt(
          rawLocation['quantity'] ??
              rawLocation['qty'] ??
              rawLocation['stock'] ??
              rawLocation['value'],
        );

        if (name.isNotEmpty) {
          locations.add(
            StockLocation(
              name: name,
              quantity: quantity,
            ),
          );
        }
      }
    }

    // Formato actual desde WooCommerce meta_data: stock-gen / stock-tie.
    final metaData = json['meta_data'];
    if (metaData is List) {
      for (final meta in metaData) {
        if (meta is! Map) continue;

        final key = meta['key']?.toString().trim() ?? '';
        final value = meta['value'];

        if (key == 'stock-gen') {
          _upsertStockLocation(
            locations,
            const StockLocation(
              name: 'General',
              quantity: 0,
            ).copyWith(quantity: _parseInt(value)),
          );
        } else if (key == 'stock-tie') {
          _upsertStockLocation(
            locations,
            const StockLocation(
              name: 'Murcia',
              quantity: 0,
            ).copyWith(quantity: _parseInt(value)),
          );
        }
      }
    }

    return locations.isEmpty ? null : locations;
  }

  static void _upsertStockLocation(
      List<StockLocation> locations,
      StockLocation location,
      ) {
    final index = locations.indexWhere(
          (item) => _normalizeText(item.name) == _normalizeText(location.name),
    );

    if (index >= 0) {
      locations[index] = location;
    } else {
      locations.add(location);
    }
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

  static String _cleanHtml(String value) {
    return value
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</?p[^>]*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static String _normalizeText(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('ä', 'a')
        .replaceAll('â', 'a')
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ì', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('î', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ò', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ù', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('û', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  static int _parseInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();

    final raw = value.toString().trim();
    if (raw.isEmpty) return fallback;

    return int.tryParse(raw) ?? double.tryParse(raw)?.toInt() ?? fallback;
  }

  Map<String, dynamic> toJson() {
    final metaData = <Map<String, dynamic>>[];

    final locations = stockLocations;
    if (locations != null && locations.isNotEmpty) {
      for (final location in locations) {
        final normalizedName = _normalizeText(location.name);

        if (normalizedName == 'general') {
          metaData.add({
            'key': 'stock-gen',
            'value': location.quantity,
          });
        } else if (normalizedName == 'murcia' || normalizedName == 'tienda') {
          metaData.add({
            'key': 'stock-tie',
            'value': location.quantity,
          });
        }
      }
    }

    return {
      'id': id,
      'name': name,
      'price': price,
      'regular_price': regularPrice,
      'images': [
        {'src': imageUrl},
      ],
      'sku': sku,
      'stock_quantity': stockQuantity,
      'on_sale': onSale,
      'stock_status': isInstock ? 'instock' : 'outofstock',
      'short_description': shortDescription,
      'description': description,
      'attributes': attributes.map((a) => a.toJson()).toList(),
      if (stockLocations != null && stockLocations!.isNotEmpty)
        'stock_locations': stockLocations!.map((s) => s.toJson()).toList(),
      if (metaData.isNotEmpty) 'meta_data': metaData,
    };
  }
}

// =========================
// STOCK LOCATION
// =========================

class StockLocation {
  final String name;
  final int quantity;

  const StockLocation({
    required this.name,
    required this.quantity,
  });

  StockLocation copyWith({
    String? name,
    int? quantity,
  }) {
    return StockLocation(
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
    );
  }

  factory StockLocation.fromJson(Map<String, dynamic> json) {
    return StockLocation(
      name: json['name']?.toString() ??
          json['location']?.toString() ??
          json['almacen']?.toString() ??
          '',
      quantity: Product._parseInt(
        json['quantity'] ?? json['qty'] ?? json['stock'] ?? json['value'],
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'quantity': quantity,
  };
}

// =========================
// PRODUCT ATTRIBUTE
// =========================

class ProductAttribute {
  final String name;
  final List<String> options;

  ProductAttribute({
    required this.name,
    required this.options,
  });

  factory ProductAttribute.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    final rawOption = json['option'];

    final options = <String>[];

    if (rawOptions is List) {
      options.addAll(
        rawOptions
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty),
      );
    } else if (rawOptions != null) {
      final value = rawOptions.toString().trim();
      if (value.isNotEmpty) options.add(value);
    }

    if (options.isEmpty && rawOption != null) {
      final value = rawOption.toString().trim();
      if (value.isNotEmpty) options.add(value);
    }

    return ProductAttribute(
      name: json['name']?.toString() ?? json['slug']?.toString() ?? '',
      options: options,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'options': options,
  };
}

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

  /// Indica si WooCommerce permite comprar el producto.
  /// En productos de "Bajo consulta" suele venir como:
  /// - Store API: is_purchasable = false
  /// - WC REST v3: purchasable = false
  final bool isPurchasable;

  /// HTML de precio/estado devuelto por WooCommerce. Se usa solo como respaldo
  /// para detectar textos tipo "Bajo consulta" sin bloquear productos normales.
  final String priceHtml;

  /// Estado de stock original de WooCommerce.
  final String stockStatus;

  /// Categorías del producto para detectar apartados tipo "Bajo consulta".
  final List<int> categoryIds;
  final List<String> categoryNames;
  final List<String> categorySlugs;

  /// Stock por almacén/sede cuando el backend lo devuelve.
  /// Se usa para que perfiles internos (admin/comercial) puedan ver
  /// desglose de stock sin afectar a clientes normales.
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
    this.isPurchasable = true,
    this.priceHtml = '',
    this.stockStatus = '',
    this.categoryIds = const <int>[],
    this.categoryNames = const <String>[],
    this.categorySlugs = const <String>[],
    this.stockLocations,
  });

  List<StockLocation> get effectiveStockLocations =>
      stockLocations ?? const <StockLocation>[];

  bool get hasStockLocationDetails => effectiveStockLocations.isNotEmpty;

  int get stockTotalByLocations {
    if (effectiveStockLocations.isEmpty) return 0;
    return effectiveStockLocations.fold<int>(
      0,
          (total, location) => total + location.quantity,
    );
  }

  int get murciaStockQuantity {
    if (effectiveStockLocations.isEmpty) return 0;

    for (final location in effectiveStockLocations) {
      final normalized = _normalizeAttributeName(location.name);
      if (normalized.contains('murcia') ||
          normalized.contains('lorqui') ||
          normalized.contains('lorqui') ||
          normalized.contains('central')) {
        return location.quantity;
      }
    }

    return 0;
  }

  String? get stockDetailsText {
    final locations = effectiveStockLocations
        .where((location) => location.quantity > 0)
        .toList();

    if (locations.isNotEmpty) {
      final parts = locations
          .map((location) => '${location.displayName}: ${location.quantity}')
          .toList();

      final total = stockTotalByLocations;
      if (total > 0 && locations.length > 1) {
        parts.add('Total: $total');
      }

      return parts.join(' · ');
    }

    if (stockQuantity > 0) {
      return 'General: $stockQuantity';
    }

    return null;
  }

  bool get hasStock {
    if (stockQuantity > 0) return true;
    if (stockTotalByLocations > 0) return true;
    if (isInstock) return true;
    return false;
  }

  int get maxPurchaseQty {
    if (!canAddToCart) return 0;
    if (stockQuantity > 0) return stockQuantity;
    if (stockTotalByLocations > 0) return stockTotalByLocations;
    if (isInstock) return 999;
    return 0;
  }

  /// Producto visible, pero no accionable comercialmente.
  /// No usamos solo precio 0 porque en una app B2B puede haber precios ocultos
  /// por permisos. La fuente principal es purchasable/is_purchasable.
  bool get isUnderConsultation {
    if (!isPurchasable) return true;

    final commercialText = _normalizeCommercialText([
      priceHtml,
      ...categoryNames,
      ...categorySlugs,
    ].join(' '));

    return commercialText.contains('bajoconsulta') ||
        commercialText.contains('consultarprecio') ||
        commercialText.contains('solicitarprecio') ||
        commercialText.contains('nopurchasable') ||
        commercialText.contains('nocomprable');
  }

  bool get canAddToCart => !isUnderConsultation && hasStock;

  bool get canRequestQuote => !isUnderConsultation && hasStock;

  String get commercialStatusLabel {
    if (isUnderConsultation) return 'Bajo consulta';
    if (hasStock) return 'En stock';
    return 'Sin stock';
  }

  String? get brandName {
    for (final attr in attributes) {
      final attrName = _normalizeAttributeName(attr.name);

      if (_isBrandAttribute(attrName) && attr.options.isNotEmpty) {
        final value = attr.options.first.trim();
        if (value.isNotEmpty) return value;
      }
    }

    return null;
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    String firstImage = 'https://via.placeholder.com/150';

    if (json['images'] != null &&
        json['images'] is List &&
        (json['images'] as List).isNotEmpty) {
      final first = (json['images'] as List).first;
      if (first is Map) {
        firstImage = first['src']?.toString() ?? firstImage;
      }
    }

    final rawShort = json['short_description']?.toString() ?? '';
    final cleanShort = _cleanHtml(rawShort);

    final rawLong = json['description']?.toString() ?? '';
    final cleanLong = _cleanHtml(rawLong);

    final parsedAttributes = (json['attributes'] as List?)
        ?.whereType<Map>()
        .map((attr) => ProductAttribute.fromJson(
      Map<String, dynamic>.from(attr),
    ))
        .toList() ??
        <ProductAttribute>[];

    final extractedBrand = _extractBrandFromJson(json);

    final hasBrandAttribute = parsedAttributes.any((attr) {
      return _isBrandAttribute(_normalizeAttributeName(attr.name));
    });

    if (extractedBrand != null &&
        extractedBrand.trim().isNotEmpty &&
        !hasBrandAttribute) {
      parsedAttributes.add(
        ProductAttribute(
          name: 'Fabricante',
          options: [extractedBrand.trim()],
        ),
      );
    }

    final categories = _parseCategories(json['categories']);
    final stockStatus = (json['stock_status'] ?? '').toString().trim();
    final parsedStockLocations = StockLocation.parseList(json);

    return Product(
      id: _parseInt(json['id']),
      name: _cleanTextEntities(json['name']?.toString() ?? 'Sin nombre'),
      price: _extractPrice(json['price'] ?? json['prices']?['price']),
      regularPrice: _extractPrice(
        json['regular_price'] ?? json['prices']?['regular_price'],
      ),
      imageUrl: firstImage,
      sku: (json['sku'] ?? '').toString(),
      stockQuantity: _parseInt(json['stock_quantity']),
      onSale: json['on_sale'] == true,
      isInstock: stockStatus == 'instock' || json['is_in_stock'] == true,
      shortDescription:
      cleanShort.trim().isEmpty ? 'Sin descripción' : cleanShort.trim(),
      description: cleanLong.trim().isEmpty
          ? 'Sin descripción detallada'
          : cleanLong.trim(),
      attributes: parsedAttributes,
      isPurchasable: _parsePurchasable(json),
      priceHtml: json['price_html']?.toString() ?? '',
      stockStatus: stockStatus,
      categoryIds: categories.ids,
      categoryNames: categories.names,
      categorySlugs: categories.slugs,
      stockLocations:
      parsedStockLocations.isEmpty ? null : parsedStockLocations,
    );
  }

  static String _extractPrice(dynamic value) {
    if (value == null) return '0.00';
    final raw = value.toString().trim();
    if (raw.isEmpty) return '0.00';
    return raw;
  }

  static bool _parsePurchasable(Map<String, dynamic> json) {
    if (json.containsKey('is_purchasable')) {
      return json['is_purchasable'] == true;
    }

    if (json.containsKey('purchasable')) {
      return json['purchasable'] == true;
    }

    final addToCart = json['add_to_cart'];
    if (addToCart is Map) {
      final text = addToCart['text']?.toString().toLowerCase().trim() ?? '';
      if (text.contains('leer más') || text.contains('leer mas')) {
        return false;
      }
    }

    return true;
  }

  static _ParsedCategories _parseCategories(dynamic value) {
    final ids = <int>[];
    final names = <String>[];
    final slugs = <String>[];

    if (value is List) {
      for (final raw in value) {
        if (raw is! Map) continue;
        final category = Map<dynamic, dynamic>.from(raw);
        final id = _parseInt(category['id']);
        final name = category['name']?.toString().trim() ?? '';
        final slug = category['slug']?.toString().trim() ?? '';

        if (id > 0) ids.add(id);
        if (name.isNotEmpty) names.add(name);
        if (slug.isNotEmpty) slugs.add(slug);
      }
    }

    return _ParsedCategories(
      ids: ids,
      names: names,
      slugs: slugs,
    );
  }

  static String _cleanHtml(String value) {
    return _cleanTextEntities(
      value
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim(),
    );
  }

  static String _cleanTextEntities(String value) {
    return value
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&#8211;', '-')
        .replaceAll('&ndash;', '-')
        .replaceAll('&mdash;', '-')
        .replaceAll(RegExp(r'&[^;]+;'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _normalizeCommercialText(String value) {
    return _normalizeAttributeName(
      value
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&amp;', '&')
          .replaceAll(RegExp(r'<[^>]*>'), ' '),
    );
  }

  static String _normalizeAttributeName(String value) {
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
        .replaceAll(RegExp(r'[\s\-_]+'), '')
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static bool _isBrandAttribute(String normalizedName) {
    return normalizedName.contains('marca') ||
        normalizedName.contains('brand') ||
        normalizedName.contains('fabricante') ||
        normalizedName.contains('manufacturer') ||
        normalizedName == 'pamarca' ||
        normalizedName == 'pafabricante' ||
        normalizedName == 'productbrand';
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
      for (final firstBrand in brands) {
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
          'security360',
          'uniview',
          'uniarch',
          'zkteco',
          'ip-com',
          'ipcom',
          'seagate',
          'mci',
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
    'stock_quantity': stockQuantity,
    'stock_status': stockStatus.isNotEmpty
        ? stockStatus
        : (isInstock ? 'instock' : 'outofstock'),
    'is_purchasable': isPurchasable,
    'purchasable': isPurchasable,
    'price_html': priceHtml,
    'short_description': shortDescription,
    'description': description,
    'attributes': attributes.map((a) => a.toJson()).toList(),
    'categories': List.generate(categoryIds.length, (index) {
      return {
        'id': categoryIds[index],
        'name': index < categoryNames.length ? categoryNames[index] : '',
        'slug': index < categorySlugs.length ? categorySlugs[index] : '',
      };
    }),
    if (stockLocations != null && stockLocations!.isNotEmpty)
      'stock_locations': stockLocations!.map((item) => item.toJson()).toList(),
  };
}


class StockLocation {
  final int id;
  final String name;
  final int quantity;
  final bool isInstock;

  const StockLocation({
    required this.id,
    required this.name,
    required this.quantity,
    required this.isInstock,
  });

  String get displayName {
    final cleanName = name.trim();
    return cleanName.isEmpty ? 'Almacén' : cleanName;
  }

  factory StockLocation.fromJson(Map<String, dynamic> json) {
    final quantity = _parseIntValue(
      json['quantity'] ??
          json['qty'] ??
          json['stock'] ??
          json['stock_quantity'] ??
          json['available_stock'] ??
          json['available'] ??
          json['value'],
    );

    final rawStatus = (json['stock_status'] ?? json['status'] ?? '')
        .toString()
        .toLowerCase()
        .trim();

    final explicitInstock = json['is_in_stock'] == true ||
        json['in_stock'] == true ||
        json['instock'] == true;

    return StockLocation(
      id: _parseIntValue(
        json['id'] ??
            json['location_id'] ??
            json['warehouse_id'] ??
            json['term_id'],
      ),
      name: (json['name'] ??
          json['location_name'] ??
          json['warehouse_name'] ??
          json['label'] ??
          json['store'] ??
          json['almacen'] ??
          json['almacén'] ??
          '')
          .toString()
          .trim(),
      quantity: quantity,
      isInstock: quantity > 0 || explicitInstock || rawStatus == 'instock',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'quantity': quantity,
    'stock_status': isInstock ? 'instock' : 'outofstock',
  };

  static List<StockLocation> parseList(Map<String, dynamic> json) {
    final possibleValues = <dynamic>[
      json['stock_locations'],
      json['stockLocations'],
      json['stock_by_location'],
      json['stockByLocation'],
      json['stock_by_locations'],
      json['locations_stock'],
      json['locations'],
      json['warehouses'],
      json['almacenes'],
    ];

    for (final value in possibleValues) {
      final parsed = _parseRawList(value);
      if (parsed.isNotEmpty) return parsed;
    }

    final metaData = json['meta_data'];
    if (metaData is List) {
      for (final rawMeta in metaData) {
        if (rawMeta is! Map) continue;

        final meta = Map<dynamic, dynamic>.from(rawMeta);
        final key = meta['key']?.toString().toLowerCase().trim() ?? '';

        if (key.contains('stock_location') ||
            key.contains('stock_locations') ||
            key.contains('stock_by_location') ||
            key.contains('almacen') ||
            key.contains('almacén') ||
            key.contains('warehouse')) {
          final parsed = _parseRawList(meta['value']);
          if (parsed.isNotEmpty) return parsed;
        }
      }
    }

    return const <StockLocation>[];
  }

  static List<StockLocation> _parseRawList(dynamic value) {
    if (value == null) return const <StockLocation>[];

    if (value is List) {
      return value
          .whereType<Map>()
          .map((item) => StockLocation.fromJson(
        Map<String, dynamic>.from(item),
      ))
          .where((item) => item.name.isNotEmpty || item.quantity > 0)
          .toList();
    }

    if (value is Map) {
      final map = Map<dynamic, dynamic>.from(value);

      final nestedList = map['locations'] ??
          map['stock_locations'] ??
          map['warehouses'] ??
          map['items'] ??
          map['data'];

      final nestedParsed = _parseRawList(nestedList);
      if (nestedParsed.isNotEmpty) return nestedParsed;

      final result = <StockLocation>[];

      for (final entry in map.entries) {
        final entryValue = entry.value;

        if (entryValue is Map) {
          final locationJson = Map<String, dynamic>.from(entryValue);
          locationJson.putIfAbsent('name', () => entry.key.toString());
          result.add(StockLocation.fromJson(locationJson));
          continue;
        }

        final quantity = _parseIntValue(entryValue);
        if (quantity > 0) {
          result.add(
            StockLocation(
              id: 0,
              name: entry.key.toString(),
              quantity: quantity,
              isInstock: true,
            ),
          );
        }
      }

      return result
          .where((item) => item.name.isNotEmpty || item.quantity > 0)
          .toList();
    }

    return const <StockLocation>[];
  }

  static int _parseIntValue(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();

    final raw = value.toString().trim().replaceAll(',', '.');
    if (raw.isEmpty) return fallback;

    return int.tryParse(raw) ?? double.tryParse(raw)?.toInt() ?? fallback;
  }
}

class ProductAttribute {
  final String name;
  final List<String> options;

  ProductAttribute({required this.name, required this.options});

  factory ProductAttribute.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    final rawOption = json['option'];
    final rawTerms = json['terms'];

    final options = <String>[];

    if (rawOptions is List) {
      options.addAll(
        rawOptions
            .map((value) => value?.toString().trim() ?? '')
            .where((value) => value.isNotEmpty),
      );
    } else if (rawOptions != null) {
      final value = rawOptions.toString().trim();
      if (value.isNotEmpty) options.add(value);
    }

    if (options.isEmpty && rawTerms is List) {
      for (final rawTerm in rawTerms) {
        if (rawTerm is Map) {
          final name = rawTerm['name']?.toString().trim() ?? '';
          if (name.isNotEmpty) options.add(name);
        } else if (rawTerm != null) {
          final value = rawTerm.toString().trim();
          if (value.isNotEmpty) options.add(value);
        }
      }
    }

    if (options.isEmpty && rawOption != null) {
      final value = rawOption.toString().trim();
      if (value.isNotEmpty) options.add(value);
    }

    return ProductAttribute(
      name: json['name']?.toString() ??
          json['taxonomy']?.toString() ??
          json['slug']?.toString() ??
          '',
      options: options,
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'options': options};
}

class _ParsedCategories {
  final List<int> ids;
  final List<String> names;
  final List<String> slugs;

  const _ParsedCategories({
    required this.ids,
    required this.names,
    required this.slugs,
  });
}

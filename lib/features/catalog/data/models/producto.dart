// ARCHIVO: lib/features/catalog/data/models/producto.dart
// Sustituye el archivo completo por este contenido.

import 'dart:convert';

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
  ///
  /// Se usa especialmente para productos "Bajo consulta" o productos visibles
  /// en catálogo, pero no accionables comercialmente.
  final bool isPurchasable;

  /// Indica si el endpoint permite solicitar presupuesto para este producto.
  /// Regla MundiCam: si el producto está sin stock, no se debe poder
  /// comprar ni presupuestar desde la app.
  final bool remoteCanRequestQuote;

  /// HTML de precio/estado devuelto por WooCommerce.
  ///
  /// Sirve como respaldo para detectar textos tipo "Bajo consulta" sin depender
  /// únicamente del precio, ya que en entorno B2B puede haber precios ocultos.
  final String priceHtml;

  /// Estado de stock original de WooCommerce.
  final String stockStatus;

  /// Categorías del producto para detectar apartados tipo "Bajo consulta" y
  /// conservar compatibilidad con Store API / WooCommerce REST.
  final List<int> categoryIds;
  final List<String> categoryNames;
  final List<String> categorySlugs;

  /// Stock por almacén/sede.
  ///
  /// Compatible con:
  /// - stock_locations / stockLocations / warehouses / almacenes
  /// - meta_data stock-gen => General
  /// - meta_data stock-tie => Murcia
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
    this.remoteCanRequestQuote = true,
    this.priceHtml = '',
    this.stockStatus = '',
    this.categoryIds = const <int>[],
    this.categoryNames = const <String>[],
    this.categorySlugs = const <String>[],
    this.stockLocations,
  });

  Product copyWith({
    int? id,
    String? name,
    String? price,
    String? regularPrice,
    String? imageUrl,
    String? sku,
    int? stockQuantity,
    bool? onSale,
    bool? isInstock,
    String? shortDescription,
    String? description,
    List<ProductAttribute>? attributes,
    bool? isPurchasable,
    bool? remoteCanRequestQuote,
    String? priceHtml,
    String? stockStatus,
    List<int>? categoryIds,
    List<String>? categoryNames,
    List<String>? categorySlugs,
    List<StockLocation>? stockLocations,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      price: price ?? this.price,
      regularPrice: regularPrice ?? this.regularPrice,
      imageUrl: imageUrl ?? this.imageUrl,
      sku: sku ?? this.sku,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      onSale: onSale ?? this.onSale,
      isInstock: isInstock ?? this.isInstock,
      shortDescription: shortDescription ?? this.shortDescription,
      description: description ?? this.description,
      attributes: attributes ?? this.attributes,
      isPurchasable: isPurchasable ?? this.isPurchasable,
      remoteCanRequestQuote: remoteCanRequestQuote ?? this.remoteCanRequestQuote,
      priceHtml: priceHtml ?? this.priceHtml,
      stockStatus: stockStatus ?? this.stockStatus,
      categoryIds: categoryIds ?? this.categoryIds,
      categoryNames: categoryNames ?? this.categoryNames,
      categorySlugs: categorySlugs ?? this.categorySlugs,
      stockLocations: stockLocations ?? this.stockLocations,
    );
  }

  Product copyWithStockFrom(Product source) {
    return copyWith(
      stockQuantity: source.stockQuantity,
      isInstock: source.isInstock,
      isPurchasable: source.isPurchasable,
      remoteCanRequestQuote: source.remoteCanRequestQuote,
      stockStatus: source.stockStatus,
      stockLocations: source.stockLocations,
    );
  }

  // =========================
  // STOCK DETALLADO
  // =========================

  List<StockLocation> get effectiveStockLocations =>
      stockLocations ?? const <StockLocation>[];

  bool get hasStockLocations => effectiveStockLocations.isNotEmpty;

  bool get hasStockLocationDetails => hasStockLocations;

  int get totalStockLocations => stockTotalByLocations;

  int get stockTotalByLocations {
    if (effectiveStockLocations.isEmpty) return 0;

    return effectiveStockLocations.fold<int>(
      0,
          (total, location) => total + (location.quantity > 0 ? location.quantity : 0),
    );
  }

  bool get hasMundicamInternalStock {
    return effectiveStockLocations.any((location) {
      final normalized = _normalizeAttributeName(location.name);
      return normalized == 'general' ||
          normalized == 'stockgen' ||
          normalized == 'murcia' ||
          normalized == 'tienda' ||
          normalized == 'stocktie' ||
          normalized.contains('lorqui');
    });
  }

  int get generalStockQuantity {
    if (effectiveStockLocations.isEmpty) return stockQuantity > 0 ? stockQuantity : 0;

    for (final location in effectiveStockLocations) {
      final normalized = _normalizeAttributeName(location.name);

      if (normalized == 'general' || normalized == 'stockgen') {
        return location.quantity;
      }
    }

    return 0;
  }

  int get murciaStockQuantity {
    if (effectiveStockLocations.isEmpty) return 0;

    for (final location in effectiveStockLocations) {
      final normalized = _normalizeAttributeName(location.name);

      if (normalized.contains('murcia') ||
          normalized.contains('tienda') ||
          normalized.contains('lorqui') ||
          normalized.contains('central') ||
          normalized == 'stocktie') {
        return location.quantity;
      }
    }

    return 0;
  }

  /// Texto de stock interno para perfiles admin/comercial.
  ///
  /// A diferencia de la versión que ocultaba ubicaciones a 0, aquí se muestran
  /// todos los almacenes recibidos. Así un usuario interno puede ver:
  /// "General: 0 · Murcia: 0" cuando realmente no hay stock por almacén.
  String? get stockDetailsText {
    // Para usuarios admin/comercial: SIEMPRE mostramos exactamente
    // General y Murcia, sin totales ni textos raros.
    if (hasMundicamInternalStock || stockQuantity > 0) {
      return 'General: $generalStockQuantity | Murcia: $murciaStockQuantity';
    }

    return null;
  }

  // =========================
  // CONTROL REAL DE STOCK
  // =========================

  bool get hasStock {
    // Regla MundiCam / WooCommerce:
    // La autoridad comercial para mostrar/comprar como "En stock" o
    // "Sin stock" es WooCommerce stock_status / is_in_stock.
    //
    // Los stocks internos General/Murcia son informativos para perfiles
    // internos, pero NO deben convertir un producto en "Sin stock"
    // si WooCommerce lo tiene como instock/onbackorder.
    // Caso crítico: General: 0 | Murcia: 0 + WooCommerce instock
    // => En stock y comprable.
    final normalizedStatus = stockStatus.toLowerCase().trim();

    if (normalizedStatus == 'outofstock') {
      return false;
    }

    if (normalizedStatus == 'instock' || normalizedStatus == 'onbackorder') {
      return true;
    }

    if (isInstock) {
      return true;
    }

    if (stockQuantity > 0) {
      return true;
    }

    // Respaldo solo si WooCommerce no envía stock_status/is_in_stock.
    // Nunca usamos General/Murcia a 0 para bloquear.
    return (generalStockQuantity + murciaStockQuantity) > 0;
  }

  double get priceValue {
    final clean = price
        .replaceAll('€', '')
        .replaceAll(RegExp(r'[^0-9,.-]'), '')
        .trim();

    if (clean.isEmpty) return 0.0;

    if (clean.contains(',')) {
      final european = clean.replaceAll('.', '').replaceAll(',', '.');
      return double.tryParse(european) ?? 0.0;
    }

    return double.tryParse(clean) ?? 0.0;
  }

  bool get hasValidPrice => priceValue > 0;

  // =========================
  // CONTROL COMERCIAL
  // =========================

  /// Producto visible, pero no accionable comercialmente.
  ///
  /// Regla MundiCam:
  /// - Si viene de WooCommerce REST v3 con precio real, el cliente puede comprar.
  /// - Si el precio es 0 o vacío, NO se debe permitir compra a 0 €.
  /// - El desglose General/Murcia se controla por rol en UI, no aquí.
  bool get isUnderConsultation {
    final commercialText = _normalizeCommercialText([
      priceHtml,
      ...categoryNames,
      ...categorySlugs,
    ].join(' '));

    return commercialText.contains('bajoconsulta') ||
        commercialText.contains('consultarprecio') ||
        commercialText.contains('solicitarprecio');
  }

  bool get canAddToCart => isPurchasable && hasValidPrice && !isUnderConsultation && hasStock;

  // v1.6.2: sin stock no se compra ni se presupuesta.
  // Puede presupuestarse un producto sin precio directo si tiene stock y el
  // backend lo permite, pero nunca un producto marcado como sin stock.
  bool get canRequestQuote => id > 0 && remoteCanRequestQuote && hasStock;

  String get commercialStatusLabel {
    if (isUnderConsultation || !hasValidPrice) return 'Bajo consulta';
    if (hasStock) return 'En stock';
    return 'Sin stock';
  }

  // =========================
  // MÁXIMO COMPRABLE
  // =========================

  int get maxPurchaseQty {
    if (!canAddToCart) return 0;

    if (stockQuantity > 0) {
      return stockQuantity;
    }

    final internalTotal = generalStockQuantity + murciaStockQuantity;
    if (internalTotal > 0) {
      return internalTotal;
    }

    // Si WooCommerce permite comprar pero no gestiona cantidad concreta,
    // dejamos una cantidad alta para no bloquear la compra en la app.
    return 999;
  }

  // =========================
  // MARCA / FABRICANTE
  // =========================

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
    // =========================
    // IMAGEN
    // =========================

    String firstImage = _extractBestImageUrl(json);
    if (firstImage.trim().isEmpty) {
      firstImage = 'https://via.placeholder.com/800';
    }

    // =========================
    // DESCRIPCIONES
    // =========================

    final rawShort = json['short_description']?.toString() ?? '';
    final rawLong = json['description']?.toString() ?? '';

    final cleanShort = _cleanHtml(rawShort);
    final cleanLong = _cleanHtml(rawLong);

    // =========================
    // ATRIBUTOS + MARCA/FABRICANTE
    // =========================

    final parsedAttributes = (json['attributes'] as List?)
        ?.whereType<Map>()
        .map(
          (attr) => ProductAttribute.fromJson(
        Map<String, dynamic>.from(attr),
      ),
    )
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

    // =========================
    // CATEGORÍAS / ESTADO / STOCK
    // =========================

    final categories = _parseCategories(json['categories']);
    final pricesMap = json['prices'] is Map
        ? Map<String, dynamic>.from(json['prices'] as Map)
        : <String, dynamic>{};
    final minorUnit = _parseInt(pricesMap['currency_minor_unit'], fallback: 2);
    final stockStatus = (json['stock_status'] ?? json['stockStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final parsedStockLocations = StockLocation.parseList(json);
    final stockTotalByLocations = parsedStockLocations.fold<int>(
      0,
          (total, location) => total + (location.quantity > 0 ? location.quantity : 0),
    );

    return Product(
      id: _parseInt(json['id']),
      name: _cleanTextEntities(json['name']?.toString() ?? 'Sin nombre'),
      // En la app MundiCam el precio visible debe ser siempre el precio ya
      // resuelto por el backend para el usuario autenticado/rol actual.
      // Por eso se prioriza display_price / role_price frente a price bruto.
      price: _extractPrice(
        json['customer_price'] ??
            json['client_price'] ??
            json['b2b_price'] ??
            json['effective_price'] ??
            json['final_price'] ??
            json['role_price'] ??
            json['display_price'] ??
            json['sale_price'] ??
            json['price'] ??
            pricesMap['price'] ??
            json['raw_price'],
        minorUnit: minorUnit,
        fromMinorUnits: json['customer_price'] == null &&
            json['client_price'] == null &&
            json['b2b_price'] == null &&
            json['effective_price'] == null &&
            json['final_price'] == null &&
            json['role_price'] == null &&
            json['display_price'] == null &&
            json['sale_price'] == null &&
            json['price'] == null &&
            pricesMap.containsKey('price'),
      ),
      regularPrice: _extractPrice(
        json['display_regular_price'] ??
            json['regular_price'] ??
            pricesMap['regular_price'],
        minorUnit: minorUnit,
        fromMinorUnits: json['display_regular_price'] == null &&
            json['regular_price'] == null &&
            pricesMap.containsKey('regular_price'),
      ),
      imageUrl: firstImage,
      sku: (json['sku'] ?? '').toString(),
      stockQuantity: _parseInt(json['stock_quantity']),
      onSale: _parseBool(json['on_sale']),
      isInstock: stockStatus == 'outofstock'
          ? false
          : (stockStatus == 'instock' ||
              stockStatus == 'onbackorder' ||
              _parseBool(json['is_in_stock']) ||
              _parseBool(json['in_stock']) ||
              stockTotalByLocations > 0),
      shortDescription:
      cleanShort.trim().isEmpty ? 'Sin descripción' : cleanShort.trim(),
      description: cleanLong.trim().isEmpty
          ? 'Sin descripción detallada'
          : cleanLong.trim(),
      attributes: parsedAttributes,
      isPurchasable: _parsePurchasable(json),
      remoteCanRequestQuote: _parseBool(json['can_request_quote'], fallback: true),
      priceHtml: _safeString(json['price_html']),
      stockStatus: stockStatus,
      categoryIds: categories.ids,
      categoryNames: categories.names,
      categorySlugs: categories.slugs,
      stockLocations: parsedStockLocations.isEmpty ? null : parsedStockLocations,
    );
  }

  static String _extractPrice(
    dynamic value, {
    int minorUnit = 2,
    bool fromMinorUnits = false,
  }) {
    if (value == null) return '0.00';
    final raw = value.toString().trim();
    if (raw.isEmpty || raw.toLowerCase() == 'null') return '0.00';

    final cleaned = raw
        .replaceAll('€', '')
        .replaceAll(RegExp(r'[^0-9,.-]'), '')
        .trim();
    if (cleaned.isEmpty) return '0.00';

    if (fromMinorUnits &&
        !cleaned.contains(',') &&
        !cleaned.contains('.') &&
        RegExp(r'^-?\d+$').hasMatch(cleaned)) {
      final cents = int.tryParse(cleaned);
      if (cents != null) {
        var divisor = 1.0;
        for (var i = 0; i < minorUnit; i++) {
          divisor *= 10;
        }
        return (cents / divisor).toStringAsFixed(minorUnit <= 0 ? 0 : 2);
      }
    }

    if (cleaned.contains(',') && cleaned.contains('.')) {
      return cleaned.replaceAll('.', '').replaceAll(',', '.');
    }

    return cleaned.replaceAll(',', '.');
  }

  static String _extractBestImageUrl(Map<String, dynamic> json) {
    final direct = _firstImageCandidate([
      json['image_full'],
      json['image_full_url'],
      json['full_image'],
      json['full_src'],
      json['fullSrc'],
      json['image_url_full'],
      json['image_url'],
      json['imageUrl'],
      json['image'],
    ]);
    if (direct.isNotEmpty) return direct;

    final images = json['images'];
    if (images is List && images.isNotEmpty) {
      for (final raw in images) {
        if (raw is Map) {
          final map = Map<dynamic, dynamic>.from(raw);
          final candidate = _firstImageCandidate([
            map['full_src'],
            map['fullSrc'],
            map['full'],
            map['large_src'],
            map['largeSrc'],
            map['source_url'],
            map['src'],
            map['url'],
          ]);
          if (candidate.isNotEmpty) return candidate;
        } else if (raw is String && raw.trim().isNotEmpty) {
          return raw.trim();
        }
      }
    }

    return '';
  }

  static String _firstImageCandidate(List<dynamic> values) {
    for (final value in values) {
      final candidate = _extractImageCandidate(value);
      if (candidate.isNotEmpty) return candidate;
    }
    return '';
  }

  static String _extractImageCandidate(dynamic value) {
    if (value == null) return '';

    if (value is String) {
      final clean = value.trim();
      if (clean.isEmpty || clean.toLowerCase() == 'null' || clean.toLowerCase() == 'false') {
        return '';
      }
      return clean;
    }

    if (value is Map) {
      final map = Map<dynamic, dynamic>.from(value);
      return _firstImageCandidate([
        map['full_src'],
        map['fullSrc'],
        map['full'],
        map['large_src'],
        map['largeSrc'],
        map['source_url'],
        map['src'],
        map['url'],
      ]);
    }

    if (value is List) {
      return _firstImageCandidate(value);
    }

    return '';
  }

  static String _safeString(dynamic value) {
    if (value == null) return '';
    final clean = value.toString().trim();
    if (clean.isEmpty || clean.toLowerCase() == 'null') return '';
    return clean;
  }

  static bool _parseBool(dynamic value, {bool fallback = false}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final clean = value.toString().trim().toLowerCase();
    if (clean.isEmpty || clean == 'null') return fallback;
    if (clean == 'false' || clean == '0' || clean == 'no' || clean == 'off') {
      return false;
    }
    return clean == 'true' || clean == '1' || clean == 'yes' || clean == 'si' || clean == 'sí' || clean == 'on';
  }

  static bool _parsePurchasable(Map<String, dynamic> json) {
    if (json.containsKey('can_add_to_cart')) {
      return _parseBool(json['can_add_to_cart']);
    }

    if (json.containsKey('is_purchasable')) {
      return _parseBool(json['is_purchasable']);
    }

    if (json.containsKey('purchasable')) {
      return _parseBool(json['purchasable']);
    }

    final addToCart = json['add_to_cart'];
    if (addToCart is Map) {
      final text = addToCart['text']?.toString().toLowerCase().trim() ?? '';
      if (text.contains('leer más') ||
          text.contains('leer mas') ||
          text.contains('read more')) {
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
        final name = _cleanTextEntities(category['name']?.toString() ?? '');
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
    // Conserva separadores reales antes de eliminar HTML.
    // WooCommerce suele enviar fichas técnicas en tablas; si se borran las
    // etiquetas sin saltos, queda todo pegado: ParámetroValorVoltaje...,
    // que después se ve mal en la ficha de producto.
    return _cleanTextEntities(
      value
          .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'</(p|div|section|article|h[1-6])\s*>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'<(p|div|section|article|h[1-6])[^>]*>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '\n• ')
          .replaceAll(RegExp(r'</li\s*>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'<tr[^>]*>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'</tr\s*>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'<t[dh][^>]*>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'</t[dh]\s*>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'</?(table|thead|tbody|tfoot)[^>]*>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'<[^>]*>'), ' ')
          .replaceAll(RegExp(r'\n{3,}'), '\n\n')
          .trim(),
    );
  }

  static String _cleanTextEntities(String value) {
    return value
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&#8211;', '-')
        .replaceAll('&ndash;', '-')
        .replaceAll('&mdash;', '-')
        .replaceAll(RegExp(r'&[^;]+;'), ' ')
        .replaceAll(RegExp(r'[ \t\r\f\v]+'), ' ')
        .replaceAll(RegExp(r' *\n *'), '\n')
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
        normalizedName == 'pamarcas' ||
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
      for (final rawBrand in brands) {
        if (rawBrand is String && rawBrand.trim().isNotEmpty) {
          return rawBrand.trim();
        }

        if (rawBrand is Map) {
          final brand = Map<dynamic, dynamic>.from(rawBrand);
          final name = brand['name']?.toString().trim();
          if (name != null && name.isNotEmpty) return name;

          final slug = brand['slug']?.toString().trim();
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
          'safire',
          'ruijie',
          'reyee',
          'ubiquiti',
          'fermax',
          'golmar',
          'hikmicro',
          'akuvox',
          'milesight',
          'cambium',
          'aritech',
          'paradox',
          'dsc',
          'honeywell',
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

    final raw = value.toString().trim().replaceAll(',', '.');
    if (raw.isEmpty) return fallback;

    return int.tryParse(raw) ?? double.tryParse(raw)?.toInt() ?? fallback;
  }

  Map<String, dynamic> toJson() {
    final metaData = <Map<String, dynamic>>[];

    final locations = stockLocations;
    if (locations != null && locations.isNotEmpty) {
      for (final location in locations) {
        final normalizedName = _normalizeAttributeName(location.name);

        if (normalizedName == 'general' || normalizedName == 'stockgen') {
          metaData.add({
            'key': 'stock-gen',
            'value': location.quantity,
          });
        } else if (normalizedName == 'murcia' ||
            normalizedName == 'tienda' ||
            normalizedName == 'stocktie') {
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
      'stock_status': stockStatus.isNotEmpty
          ? stockStatus
          : (isInstock ? 'instock' : 'outofstock'),
      'is_purchasable': isPurchasable,
      'purchasable': isPurchasable,
      'price_html': priceHtml,
      'can_request_quote': remoteCanRequestQuote,
      'short_description': shortDescription,
      'description': description,
      'attributes': attributes.map((attribute) => attribute.toJson()).toList(),
      'categories': List.generate(categoryIds.length, (index) {
        return {
          'id': categoryIds[index],
          'name': index < categoryNames.length ? categoryNames[index] : '',
          'slug': index < categorySlugs.length ? categorySlugs[index] : '',
        };
      }),
      if (stockLocations != null && stockLocations!.isNotEmpty)
        'stock_locations': stockLocations!
            .map((stockLocation) => stockLocation.toJson())
            .toList(),
      if (metaData.isNotEmpty) 'meta_data': metaData,
    };
  }
}

// =========================
// STOCK LOCATION
// =========================

class StockLocation {
  final int id;
  final String name;
  final int quantity;
  final bool isInstock;

  const StockLocation({
    this.id = 0,
    required this.name,
    required this.quantity,
    this.isInstock = false,
  });

  String get displayName {
    final cleanName = name.trim();
    return cleanName.isEmpty ? 'Almacén' : cleanName;
  }

  StockLocation copyWith({
    int? id,
    String? name,
    int? quantity,
    bool? isInstock,
  }) {
    final newQuantity = quantity ?? this.quantity;

    return StockLocation(
      id: id ?? this.id,
      name: name ?? this.name,
      quantity: newQuantity,
      isInstock: isInstock ?? (this.isInstock || newQuantity > 0),
    );
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

    final rawName = (json['name'] ??
        json['location_name'] ??
        json['warehouse_name'] ??
        json['location'] ??
        json['warehouse'] ??
        json['label'] ??
        json['store'] ??
        json['almacen'] ??
        json['almacén'] ??
        '')
        .toString()
        .trim();

    return StockLocation(
      id: _parseIntValue(
        json['id'] ??
            json['location_id'] ??
            json['warehouse_id'] ??
            json['term_id'],
      ),
      name: _friendlyLocationName(rawName),
      quantity: quantity,
      isInstock: quantity > 0 || explicitInstock || rawStatus == 'instock',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'quantity': quantity,
    'stock_status': isInstock || quantity > 0 ? 'instock' : 'outofstock',
  };

  static List<StockLocation> parseList(Map<String, dynamic> json) {
    final locations = <StockLocation>[];

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
      for (final location in parsed) {
        _upsertStockLocation(locations, location);
      }
    }

    final metaData = json['meta_data'];
    if (metaData is List) {
      for (final rawMeta in metaData) {
        if (rawMeta is! Map) continue;

        final meta = Map<dynamic, dynamic>.from(rawMeta);
        final key = meta['key']?.toString().trim() ?? '';
        final normalizedKey = _normalizeLocationKey(key);
        final value = meta['value'];

        // Formato actual MundiCam desde WooCommerce meta_data.
        if (normalizedKey == 'stockgen') {
          _upsertStockLocation(
            locations,
            StockLocation(
              name: 'General',
              quantity: _parseIntValue(value),
              isInstock: _parseIntValue(value) > 0,
            ),
          );
          continue;
        }

        if (normalizedKey == 'stocktie') {
          _upsertStockLocation(
            locations,
            StockLocation(
              name: 'Murcia',
              quantity: _parseIntValue(value),
              isInstock: _parseIntValue(value) > 0,
            ),
          );
          continue;
        }

        // Formatos futuros/genéricos de stock por almacén.
        if (normalizedKey.contains('stocklocation') ||
            normalizedKey.contains('stocklocations') ||
            normalizedKey.contains('stockbylocation') ||
            normalizedKey.contains('almacen') ||
            normalizedKey.contains('warehouse')) {
          final parsed = _parseRawList(value);
          for (final location in parsed) {
            _upsertStockLocation(locations, location);
          }
        }
      }
    }

    return locations;
  }

  static List<StockLocation> _parseRawList(dynamic value) {
    if (value == null) return const <StockLocation>[];

    if (value is String) {
      final raw = value.trim();
      if (raw.isEmpty) return const <StockLocation>[];

      try {
        final decoded = jsonDecode(raw);
        return _parseRawList(decoded);
      } catch (_) {
        return const <StockLocation>[];
      }
    }

    if (value is List) {
      return value
          .whereType<Map>()
          .map(
            (item) => StockLocation.fromJson(
          Map<String, dynamic>.from(item),
        ),
      )
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
        final entryKey = entry.key.toString();
        final entryValue = entry.value;

        if (entryValue is Map) {
          final locationJson = Map<String, dynamic>.from(entryValue);
          locationJson.putIfAbsent('name', () => _friendlyLocationName(entryKey));
          result.add(StockLocation.fromJson(locationJson));
          continue;
        }

        final quantity = _parseIntValue(entryValue);
        if (quantity >= 0) {
          result.add(
            StockLocation(
              name: _friendlyLocationName(entryKey),
              quantity: quantity,
              isInstock: quantity > 0,
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

  static void _upsertStockLocation(
      List<StockLocation> locations,
      StockLocation location,
      ) {
    final normalizedName = _normalizeLocationKey(location.name);

    final index = locations.indexWhere(
          (item) => _normalizeLocationKey(item.name) == normalizedName,
    );

    if (index >= 0) {
      locations[index] = location;
    } else {
      locations.add(location);
    }
  }

  static String _friendlyLocationName(String value) {
    final normalized = _normalizeLocationKey(value);

    if (normalized == 'stockgen' || normalized == 'general') {
      return 'General';
    }

    if (normalized == 'stocktie' ||
        normalized == 'murcia' ||
        normalized == 'tienda' ||
        normalized == 'lorqui') {
      return 'Murcia';
    }

    return value.trim();
  }

  static String _normalizeLocationKey(String value) {
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

  static int _parseIntValue(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();

    final raw = value.toString().trim().replaceAll(',', '.');
    if (raw.isEmpty) return fallback;

    return int.tryParse(raw) ?? double.tryParse(raw)?.toInt() ?? fallback;
  }
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

  Map<String, dynamic> toJson() => {
    'name': name,
    'options': options,
  };
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


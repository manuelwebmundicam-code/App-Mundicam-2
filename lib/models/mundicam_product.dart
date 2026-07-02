class MundicamProduct {
  final int id;
  final String name;
  final String slug;
  final String sku;
  final String type;

  /// Precio final devuelto por WordPress/WooCommerce para el rol efectivo.
  /// Este es el precio que debe pintar Flutter.
  final double? price;

  final double? regularPrice;
  final double? salePrice;
  final String priceHtml;
  final double? displayPriceIncludingTax;
  final double? displayPriceExcludingTax;
  final bool onSale;
  final bool isInStock;
  final String stockStatus;
  final int? stockQuantity;
  final bool canViewStock;
  final String imageUrl;
  final String shortDescription;
  final String? description;
  final List<String> images;
  final Map<String, dynamic>? brand;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> attributes;
  final Map<String, dynamic>? stockLocations;

  const MundicamProduct({
    required this.id,
    required this.name,
    required this.slug,
    required this.sku,
    required this.type,
    required this.price,
    required this.regularPrice,
    required this.salePrice,
    required this.priceHtml,
    required this.displayPriceIncludingTax,
    required this.displayPriceExcludingTax,
    required this.onSale,
    required this.isInStock,
    required this.stockStatus,
    required this.stockQuantity,
    required this.canViewStock,
    required this.imageUrl,
    required this.shortDescription,
    required this.description,
    required this.images,
    required this.brand,
    required this.categories,
    required this.attributes,
    required this.stockLocations,
  });

  factory MundicamProduct.fromJson(Map<String, dynamic> json) {
    return MundicamProduct(
      id: _asInt(json['id']),
      name: _asString(json['name']),
      slug: _asString(json['slug']),
      sku: _asString(json['sku']),
      type: _asString(json['type']),
      price: _asDouble(json['price']),
      regularPrice: _asDouble(json['regular_price']),
      salePrice: _asDouble(json['sale_price']),
      priceHtml: _asString(json['price_html']),
      displayPriceIncludingTax: _asDouble(json['display_price_including_tax']),
      displayPriceExcludingTax: _asDouble(json['display_price_excluding_tax']),
      onSale: json['on_sale'] == true,
      isInStock: json['is_in_stock'] == true,
      stockStatus: _asString(json['stock_status']),
      stockQuantity: _asNullableInt(json['stock_quantity']),
      canViewStock: json['can_view_stock'] == true,
      imageUrl: _asString(json['image_url']),
      shortDescription: _asString(json['short_description']),
      description: json['description']?.toString(),
      images: _asStringList(json['images']),
      brand: _asMap(json['brand']),
      categories: _asMapList(json['categories']),
      attributes: _asMapList(json['attributes']),
      stockLocations: _asMap(json['stock_locations']),
    );
  }

  bool get hasRealPrice => price != null && price! > 0;

  String get displayPriceText {
    if (price == null || price! <= 0) return 'Consultar';
    return '${price!.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  String get displayPriceIncludingTaxText {
    final value = displayPriceIncludingTax ?? price;
    if (value == null || value <= 0) return 'Consultar';
    return '${value.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  String get stockText {
    if (!canViewStock) return '';
    if (stockQuantity == null) return isInStock ? 'Disponible' : 'Sin stock';
    return 'Stock: $stockQuantity';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'slug': slug,
      'sku': sku,
      'type': type,
      'price': price,
      'regular_price': regularPrice,
      'sale_price': salePrice,
      'price_html': priceHtml,
      'display_price_including_tax': displayPriceIncludingTax,
      'display_price_excluding_tax': displayPriceExcludingTax,
      'on_sale': onSale,
      'is_in_stock': isInStock,
      'stock_status': stockStatus,
      'stock_quantity': stockQuantity,
      'can_view_stock': canViewStock,
      'image_url': imageUrl,
      'short_description': shortDescription,
      'description': description,
      'images': images,
      'brand': brand,
      'categories': categories,
      'attributes': attributes,
      'stock_locations': stockLocations,
    };
  }

  static String _asString(dynamic value) => value?.toString() ?? '';

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int? _asNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    final cleaned = value.toString().replaceAll(',', '.').trim();
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  static List<String> _asStringList(dynamic value) {
    if (value is List) return value.map((e) => e.toString()).toList();
    return const <String>[];
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return null;
  }

  static List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((item) => item.map((key, val) => MapEntry(key.toString(), val)))
        .toList();
  }
}

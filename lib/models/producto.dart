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

    // WooCommerce stock numérico
    if (stockQuantity > 0) {
      return true;
    }

    // Productos instock sin gestión numérica
    if (isInstock) {
      return true;
    }

    return false;
  }

  // =========================
  // MÁXIMO COMPRABLE
  // =========================

  int get maxPurchaseQty {

    // Si WooCommerce controla stock real
    if (stockQuantity > 0) {
      return stockQuantity;
    }

    // Si WooCommerce dice instock
    // pero sin stock_quantity
    if (isInstock) {
      return 999;
    }

    return 0;
  }

  factory Product.fromJson(Map<String, dynamic> json) {

    // =========================
    // IMAGEN
    // =========================

    String firstImage = 'https://via.placeholder.com/150';

    if (json['images'] != null &&
        (json['images'] as List).isNotEmpty) {

      firstImage =
          json['images'][0]['src'] ?? firstImage;
    }

    // =========================
    // DESCRIPCIÓN CORTA
    // =========================

    final String rawShort =
        json['short_description']?.toString() ?? '';

    final String cleanShort =
    rawShort.replaceAll(
      RegExp(r'<[^>]*>|&[^;]+;'),
      '',
    );

    // =========================
    // DESCRIPCIÓN LARGA
    // =========================

    final String rawLong =
        json['description']?.toString() ?? '';

    final String cleanLong =
    rawLong.replaceAll(
      RegExp(r'<[^>]*>|&[^;]+;'),
      '',
    );

    return Product(
      id: json['id'] ?? 0,

      name: json['name'] ?? 'Sin nombre',

      price:
      (json['price'] ?? '0.00').toString(),

      regularPrice:
      (json['regular_price'] ?? '').toString(),

      imageUrl: firstImage,

      sku:
      (json['sku'] ?? '').toString(),

      // =========================
      // STOCK SEGURO
      // =========================

      stockQuantity:
      (json['stock_quantity'] ?? 0) as int,

      onSale:
      json['on_sale'] ?? false,

      isInstock:
      json['stock_status']?.toString() ==
          'instock',

      shortDescription:
      cleanShort.trim().isEmpty
          ? 'Sin descripción'
          : cleanShort.trim(),

      description:
      cleanLong.trim().isEmpty
          ? 'Sin descripción detallada'
          : cleanLong.trim(),

      attributes:
      (json['attributes'] as List?)
          ?.map(
            (attr) =>
            ProductAttribute.fromJson(attr),
      )
          .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'price': price,
    'regular_price': regularPrice,
    'images': [
      {'src': imageUrl}
    ],
    'sku': sku,
    'on_sale': onSale,
    'stock_status':
    isInstock
        ? 'instock'
        : 'outofstock',
    'short_description':
    shortDescription,
    'description':
    description,
    'attributes':
    attributes
        .map((a) => a.toJson())
        .toList(),
  };
}

class ProductAttribute {

  final String name;
  final List<String> options;

  ProductAttribute({
    required this.name,
    required this.options,
  });

  factory ProductAttribute.fromJson(
      Map<String, dynamic> json) {

    return ProductAttribute(
      name: json['name'] ?? '',
      options: List<String>.from(
        json['options'] ?? [],
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'options': options,
  };
}
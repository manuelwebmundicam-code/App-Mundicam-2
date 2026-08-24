import 'package:equatable/equatable.dart';

// Modelo para items dentro del presupuesto local
class LocalQuoteItem extends Equatable {
  final int productId;
  final int variationId;
  final String productName;
  final int quantity;
  final double price;

  const LocalQuoteItem({
    required this.productId,
    this.variationId = 0,
    required this.productName,
    required this.quantity,
    required this.price,
  });

  double get subtotal => price * quantity;

  @override
  List<Object?> get props => [productId, variationId, productName, quantity, price];

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'variationId': variationId,
    'productName': productName,
    'quantity': quantity,
    'price': price,
  };

  factory LocalQuoteItem.fromJson(Map<String, dynamic> json) => LocalQuoteItem(
    productId: _itemInt(json['productId'] ?? json['product_id']),
    variationId: _itemInt(json['variationId'] ?? json['variation_id']),
    productName: (json['productName'] ?? json['product_name'] ?? '').toString(),
    quantity: _itemInt(json['quantity'], fallback: 1),
    price: _itemDouble(json['price']),
  );

  static int _itemInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static double _itemDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }
}

// Modelo principal de presupuesto local
class LocalQuote extends Equatable {
  final String orderId;        // ID real de WooCommerce
  final String nombre;
  final DateTime fechaCreacion;
  final List<LocalQuoteItem> items;

  const LocalQuote({
    required this.orderId,
    required this.nombre,
    required this.fechaCreacion,
    this.items = const [],
  });

  double get total => items.fold(0, (sum, item) => sum + item.subtotal);

  bool get isExpired => DateTime.now().difference(fechaCreacion).inDays >= 15;

  LocalQuote copyWith({
    String? orderId,
    String? nombre,
    DateTime? fechaCreacion,
    List<LocalQuoteItem>? items,
  }) {
    return LocalQuote(
      orderId: orderId ?? this.orderId,
      nombre: nombre ?? this.nombre,
      fechaCreacion: fechaCreacion ?? this.fechaCreacion,
      items: items ?? this.items,
    );
  }

  Map<String, dynamic> toJson() => {
    'orderId': orderId,
    'nombre': nombre,
    'fechaCreacion': fechaCreacion.toIso8601String(),
    'items': items.map((e) => e.toJson()).toList(),
  };

  factory LocalQuote.fromJson(Map<String, dynamic> json) => LocalQuote(
    orderId: json['orderId'] as String,
    nombre: json['nombre'] as String,
    fechaCreacion: DateTime.parse(json['fechaCreacion'] as String),
    items: (json['items'] as List)
        .map((e) => LocalQuoteItem.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  factory LocalQuote.fromServerPayload(Map<String, dynamic> json) {
    final rawItems = json['items'] is List ? json['items'] as List : const [];
    final parsedItems = rawItems.whereType<Map>().map((raw) {
      final item = Map<String, dynamic>.from(raw);
      return LocalQuoteItem(
        productId: _parseInt(item['product_id'] ?? item['productId']),
        variationId: _parseInt(item['variation_id'] ?? item['variationId']),
        productName: _parseString(
          item['product_name'] ?? item['productName'] ?? item['name'],
        ),
        quantity: _parseInt(item['quantity'], fallback: 1).clamp(1, 999999).toInt(),
        price: _parseDouble(item['price']),
      );
    }).where((item) => item.productId > 0 && item.productName.isNotEmpty).toList();

    final rawDate = _parseString(
      json['created_at'] ?? json['fechaCreacion'] ?? json['date_created'],
    );

    return LocalQuote(
      orderId: _parseString(
        json['order_id'] ?? json['orderId'] ?? json['local_quote_uuid'],
      ),
      nombre: _parseString(json['name'] ?? json['nombre']).isNotEmpty
          ? _parseString(json['name'] ?? json['nombre'])
          : 'Presupuesto local',
      fechaCreacion: DateTime.tryParse(rawDate) ?? DateTime.now(),
      items: parsedItems,
    );
  }

  static int _parseInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static double _parseDouble(dynamic value) {
    if (value is num) return value.toDouble();
    final raw = value?.toString().trim().replaceAll(',', '.') ?? '';
    return double.tryParse(raw) ?? 0;
  }

  static String _parseString(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    return raw.toLowerCase() == 'null' ? '' : raw;
  }

  @override
  List<Object?> get props => [orderId, nombre, fechaCreacion, items];
}
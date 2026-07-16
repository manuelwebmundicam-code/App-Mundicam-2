import 'package:equatable/equatable.dart';

// Modelo para items dentro del presupuesto local
class LocalQuoteItem extends Equatable {
  final int productId;
  final String productName;
  final int quantity;
  final double price;

  const LocalQuoteItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.price,
  });

  double get subtotal => price * quantity;

  @override
  List<Object?> get props => [productId, productName, quantity, price];

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'productName': productName,
    'quantity': quantity,
    'price': price,
  };

  factory LocalQuoteItem.fromJson(Map<String, dynamic> json) => LocalQuoteItem(
    productId: json['productId'] as int,
    productName: json['productName'] as String,
    quantity: json['quantity'] as int,
    price: (json['price'] as num).toDouble(),
  );
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

  @override
  List<Object?> get props => [orderId, nombre, fechaCreacion, items];
}
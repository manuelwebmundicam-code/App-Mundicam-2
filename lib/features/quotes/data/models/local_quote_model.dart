class LocalQuote {
  final String orderId;
  final String nombre;
  final DateTime fechaCreacion;
  final List<LocalQuoteItem> items;

  const LocalQuote({
    required this.orderId,
    required this.nombre,
    required this.fechaCreacion,
    required this.items,
  });

  bool get isExpired {
    return DateTime.now().difference(fechaCreacion) > const Duration(days: 15);
  }

  double get total {
    return items.fold<double>(0, (sum, item) => sum + item.subtotal);
  }

  int get totalUnits {
    return items.fold<int>(0, (sum, item) => sum + item.quantity);
  }

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

  factory LocalQuote.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];

    return LocalQuote(
      orderId: _safeString(json['orderId'] ?? json['order_id']),
      nombre: _safeString(json['nombre'], fallback: 'Presupuesto'),
      fechaCreacion: _parseDate(json['fechaCreacion'] ?? json['fecha_creacion']),
      items: rawItems is List
          ? rawItems
          .whereType<Map>()
          .map((item) => LocalQuoteItem.fromJson(Map<String, dynamic>.from(item)))
          .toList()
          : <LocalQuoteItem>[],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'orderId': orderId,
      'nombre': nombre,
      'fechaCreacion': fechaCreacion.toIso8601String(),
      'items': items.map((item) => item.toJson()).toList(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocalQuote &&
        other.orderId == orderId &&
        other.nombre == nombre &&
        other.fechaCreacion == fechaCreacion &&
        _listEquals(other.items, items);
  }

  @override
  int get hashCode => Object.hash(orderId, nombre, fechaCreacion, Object.hashAll(items));
}

class LocalQuoteItem {
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

  LocalQuoteItem copyWith({
    int? productId,
    String? productName,
    int? quantity,
    double? price,
  }) {
    return LocalQuoteItem(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
    );
  }

  factory LocalQuoteItem.fromJson(Map<String, dynamic> json) {
    return LocalQuoteItem(
      productId: _parseInt(json['productId'] ?? json['product_id']),
      productName: _safeString(json['productName'] ?? json['product_name']),
      quantity: _parseInt(json['quantity'], fallback: 1),
      price: _parseDouble(json['price']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'productId': productId,
      'productName': productName,
      'quantity': quantity,
      'price': price,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocalQuoteItem &&
        other.productId == productId &&
        other.productName == productName &&
        other.quantity == quantity &&
        other.price == price;
  }

  @override
  int get hashCode => Object.hash(productId, productName, quantity, price);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _safeString(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = value.toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'null') return fallback;
  return text;
}

int _parseInt(dynamic value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  final raw = value.toString().trim().replaceAll(',', '.');
  if (raw.isEmpty) return fallback;
  return int.tryParse(raw) ?? double.tryParse(raw)?.toInt() ?? fallback;
}

double _parseDouble(dynamic value, {double fallback = 0}) {
  if (value == null) return fallback;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  final raw = value.toString().trim().replaceAll('€', '').replaceAll(',', '.');
  if (raw.isEmpty) return fallback;
  return double.tryParse(raw.replaceAll(RegExp(r'[^0-9.\-]'), '')) ?? fallback;
}

DateTime _parseDate(dynamic value) {
  if (value is DateTime) return value;
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return DateTime.now();
  return DateTime.tryParse(text) ?? DateTime.now();
}

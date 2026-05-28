class OrderMundicam {
  final int id;
  final String status;
  final DateTime dateCreated;
  final String total;
  final List<OrderItem> items;

  OrderMundicam({
    required this.id,
    required this.status,
    required this.dateCreated,
    required this.total,
    required this.items,
  });

  factory OrderMundicam.fromJson(Map<String, dynamic> json) {
    final rawItems = json['line_items'];
    final lineItems = rawItems is List ? rawItems : <dynamic>[];

    return OrderMundicam(
      id: _parseInt(json['id']),
      status: json['status']?.toString() ?? '',
      dateCreated: _parseDate(json['date_created']),
      total: json['total']?.toString() ?? '0',
      items: lineItems
          .whereType<Map>()
          .map((i) => OrderItem.fromJson(Map<String, dynamic>.from(i)))
          .where((item) => item.name.trim().isNotEmpty)
          .toList(),
    );
  }

  static int _parseInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  static DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();

    final raw = value.toString().trim();

    if (raw.isEmpty) return DateTime.now();

    return DateTime.tryParse(raw) ?? DateTime.now();
  }
}

class OrderItem {
  final int productId;
  final String name;
  final int quantity;
  final double total;

  OrderItem({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.total,
  });

  double get unitPrice {
    if (quantity <= 0) return total;
    return total / quantity;
  }

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    final subtotal = _parseDouble(json['subtotal']);
    final total = _parseDouble(json['total']);

    return OrderItem(
      productId: _parseInt(json['product_id'] ?? json['productId']),
      name: _cleanText(json['name']?.toString() ?? ''),
      quantity: _parseInt(
        json['quantity'] ?? json['qty'],
        fallback: 1,
      ),
      total: total > 0 ? total : subtotal,
    );
  }

  static int _parseInt(dynamic value, {int fallback = 1}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is num) return value.toInt();

    final raw = value.toString().trim();

    if (raw.isEmpty) return fallback;

    return int.tryParse(raw) ?? double.tryParse(raw)?.toInt() ?? fallback;
  }

  static double _parseDouble(dynamic value) {
    if (value == null) return 0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();

    final raw = value
        .toString()
        .trim()
        .replaceAll('€', '')
        .replaceAll(RegExp(r'\s+'), '');

    if (raw.contains(',') && raw.contains('.')) {
      return double.tryParse(
        raw.replaceAll('.', '').replaceAll(',', '.'),
      ) ??
          0;
    }

    return double.tryParse(raw.replaceAll(',', '.')) ?? 0;
  }

  static String _cleanText(String value) {
    return value.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }
}
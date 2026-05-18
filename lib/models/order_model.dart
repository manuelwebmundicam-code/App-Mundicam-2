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
    return OrderMundicam(
      id: json['id'],
      status: json['status'],
      dateCreated: DateTime.parse(json['date_created']),
      total: json['total'],
      items: (json['line_items'] as List)
          .map((i) => OrderItem.fromJson(i))
          .toList(),
    );
  }
}

class OrderItem {
  final int productId;
  final String name;
  final int quantity;

  OrderItem({
    required this.productId,
    required this.name,
    required this.quantity,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      productId: json['product_id'] ?? 0,
      name: json['name'] ?? '',
      quantity: json['quantity'] ?? 0,
    );
  }
}
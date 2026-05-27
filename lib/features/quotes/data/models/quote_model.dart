class QuoteMundicam {
  final String id;           // ID visible: PRE-12345
  final String orderIdRaw;   // ID real: "12345" (sin prefijo)
  final String description;
  final double total;
  final int daysLeft;
  final String status;

  QuoteMundicam({
    required this.id,
    required this.orderIdRaw,
    required this.description,
    required this.total,
    required this.daysLeft,
    required this.status,
  });

  factory QuoteMundicam.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'].toString();
    DateTime dateCreated = DateTime.parse(
      json['date_created'] ?? DateTime.now().toString(),
    );
    int diff = 30 - DateTime.now().difference(dateCreated).inDays;

    return QuoteMundicam(
      id: "PRE-$rawId",
      orderIdRaw: rawId,
      description: json['customer_note'] != ""
          ? json['customer_note']
          : "Presupuesto de equipos de seguridad",
      total: double.tryParse(json['total'].toString()) ?? 0.0,
      daysLeft: diff > 0 ? diff : 0,
      status: json['status'] ?? '',
    );
  }
}
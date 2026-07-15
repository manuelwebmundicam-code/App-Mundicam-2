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
    final rawId = _safeString(
      json['id'] ?? json['order_id'] ?? json['quote_id'] ?? json['number'],
    );
    final safeRawId = rawId.isEmpty ? '0' : rawId.replaceAll('PRE-', '').trim();

    final rawDate = _safeString(
      json['date_created'] ?? json['date'] ?? json['created_at'] ?? json['date_created_gmt'],
    );
    final dateCreated = DateTime.tryParse(rawDate) ?? DateTime.now();
    final diff = 30 - DateTime.now().difference(dateCreated).inDays;

    final rawNote = _safeString(
      json['customer_note'] ?? json['description'] ?? json['note'] ?? json['title'],
    );
    final rawStatus = _safeString(json['status']).isEmpty
        ? 'pending'
        : _safeString(json['status']);

    return QuoteMundicam(
      id: 'PRE-$safeRawId',
      orderIdRaw: safeRawId,
      description: rawNote.isNotEmpty
          ? rawNote
          : 'Presupuesto de equipos de seguridad',
      total: _parseTotal(json['total'] ?? json['amount'] ?? json['subtotal']),
      daysLeft: diff > 0 ? diff : 0,
      status: rawStatus,
    );
  }

  static String _safeString(dynamic value) {
    if (value == null) return '';
    final clean = value.toString().trim();
    if (clean.isEmpty || clean.toLowerCase() == 'null') return '';
    return clean;
  }

  static double _parseTotal(dynamic value) {
    final raw = _safeString(value)
        .replaceAll('€', '')
        .replaceAll(RegExp(r'[^0-9,.-]'), '')
        .trim();
    if (raw.isEmpty) return 0.0;

    if (raw.contains(',') && raw.contains('.')) {
      return double.tryParse(raw.replaceAll('.', '').replaceAll(',', '.')) ?? 0.0;
    }

    return double.tryParse(raw.replaceAll(',', '.')) ?? 0.0;
  }
}

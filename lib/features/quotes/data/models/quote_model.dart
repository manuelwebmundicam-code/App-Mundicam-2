class QuoteMundicam {
  final String id;           // ID visible: PRE-12345
  final String orderIdRaw;   // ID real: "12345" (sin prefijo)
  final String description;
  final double total;
  final int daysLeft;

  /// Estado bruto recibido desde WooCommerce/YITH.
  /// PHP 1.9.26 debe devolver `ywraq-pending` para que en web aparezca
  /// como `status-ywraq-pending` / "Presupuesto pendiente".
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
    final rawStatus = _safeString(
      json['status'] ??
          json['order_status'] ??
          json['quote_status'] ??
          json['post_status'],
    );
    final safeStatus = rawStatus.isEmpty ? 'pending' : rawStatus;

    return QuoteMundicam(
      id: 'PRE-$safeRawId',
      orderIdRaw: safeRawId,
      description: rawNote.isNotEmpty
          ? rawNote
          : 'Presupuesto de equipos de seguridad',
      total: _parseTotal(json['total'] ?? json['amount'] ?? json['subtotal']),
      daysLeft: diff > 0 ? diff : 0,
      status: safeStatus,
    );
  }

  /// Estado normalizado para comparar dentro de la app.
  /// WooCommerce guarda los estados con `wc-`, pero `WC_Order::get_status()`
  /// normalmente los devuelve sin ese prefijo.
  String get normalizedStatus => status
      .toLowerCase()
      .trim()
      .replaceFirst(RegExp(r'^wc-'), '');

  /// Texto seguro para mostrar al usuario en la app.
  String get statusLabel {
    switch (normalizedStatus) {
      case 'ywraq-pending':
        return 'Presupuesto pendiente';
      case 'ywraq-new':
        return 'Nueva solicitud';
      case 'ywraq-accepted':
        return 'Presupuesto aceptado';
      case 'ywraq-rejected':
        return 'Presupuesto rechazado';
      case 'pending':
        return 'Pendiente de pago';
      case 'on-hold':
        return 'En espera';
      case 'processing':
        return 'En proceso';
      case 'completed':
        return 'Completado';
      case 'checkout-draft':
        return 'Borrador';
      default:
        if (normalizedStatus.startsWith('ywraq-')) {
          return normalizedStatus
              .replaceAll('ywraq-', '')
              .replaceAll('-', ' ')
              .trim();
        }
        return status.isEmpty ? 'Presupuesto' : status;
    }
  }

  bool get isYithPending => normalizedStatus == 'ywraq-pending';

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

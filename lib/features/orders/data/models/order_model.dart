class OrderMundicam {
  final int id;
  final String number;
  final String orderKey;
  final String status;
  final String statusLabel;
  final DateTime dateCreated;
  final DateTime? datePaid;
  final DateTime? dateCompleted;
  final bool isQuote;

  final String subtotal;
  final String taxTotal;
  final String shippingTotal;
  final String discountTotal;
  final String feesTotal;
  final String total;
  final String currency;

  final String paymentMethod;
  final String paymentMethodTitle;
  final String shippingMethodTitle;
  final String customerNote;

  final OrderAddress billing;
  final OrderAddress shipping;
  final List<OrderItem> items;
  final OrderActions actions;

  OrderMundicam({
    required this.id,
    required this.status,
    required this.dateCreated,
    required this.total,
    required this.items,
    this.number = '',
    this.orderKey = '',
    this.statusLabel = '',
    this.datePaid,
    this.dateCompleted,
    this.isQuote = false,
    this.subtotal = '0',
    this.taxTotal = '0',
    this.shippingTotal = '0',
    this.discountTotal = '0',
    this.feesTotal = '0',
    this.currency = 'EUR',
    this.paymentMethod = '',
    this.paymentMethodTitle = '',
    this.shippingMethodTitle = '',
    this.customerNote = '',
    OrderAddress? billing,
    OrderAddress? shipping,
    OrderActions? actions,
  })  : billing = billing ?? OrderAddress.empty(),
        shipping = shipping ?? OrderAddress.empty(),
        actions = actions ?? OrderActions.defaults();

  bool get canRequestRma {
    final statusNormalized = normalizedStatus;
    final now = DateTime.now();
    final ageDays = now.difference(dateCreated).inDays;

    if (actions.hasExplicitValues) {
      return actions.canRequestRma;
    }

    return !isQuote &&
        ageDays <= 730 &&
        (statusNormalized == 'completed' || statusNormalized == 'processing');
  }

  String get normalizedStatus => status
      .toLowerCase()
      .trim()
      .replaceFirst(RegExp(r'^wc-'), '');

  String get displayStatusLabel {
    final clean = statusLabel.trim();
    if (clean.isNotEmpty) return clean;

    switch (normalizedStatus) {
      case 'completed':
        return 'Completado';
      case 'processing':
        return 'En proceso';
      case 'pending':
        return 'Pendiente';
      case 'on-hold':
        return 'En espera';
      case 'cancelled':
        return 'Cancelado';
      case 'refunded':
        return 'Reembolsado';
      case 'failed':
        return 'Fallido';
      case 'ywraq-new':
        return 'Presupuesto nuevo';
      case 'ywraq-pending':
        return 'Presupuesto pendiente';
      case 'ywraq-accepted':
        return 'Presupuesto aceptado';
      case 'ywraq-rejected':
        return 'Presupuesto rechazado';
      default:
        return _formatUnknownStatus(status);
    }
  }

  bool get hasPaymentOrShippingInfo => true;

  bool get hasCustomerInfo => billing.hasAnyVisibleValue || shipping.hasAnyVisibleValue;

  factory OrderMundicam.fromJson(Map<String, dynamic> json) {
    final rawItems = json['line_items'] ?? json['items'];
    final lineItems = rawItems is List ? rawItems : <dynamic>[];

    return OrderMundicam(
      id: _parseInt(json['id'] ?? json['order_id']),
      number: _safeString(json['number'] ?? json['order_number']),
      orderKey: _safeString(json['order_key'] ?? json['orderKey']),
      status: _safeString(
        json['status'] ?? json['order_status'] ?? json['post_status'],
      ),
      statusLabel: _safeString(json['status_label'] ?? json['statusLabel']),
      dateCreated: _parseDate(
        json['date_created'] ?? json['dateCreated'] ?? json['date'],
      ),
      datePaid: _parseNullableDate(json['date_paid'] ?? json['datePaid']),
      dateCompleted: _parseNullableDate(
        json['date_completed'] ?? json['dateCompleted'],
      ),
      isQuote: _parseBool(json['is_quote'] ?? json['isQuote']),
      subtotal: _safeMoney(json['subtotal']),
      taxTotal: _safeMoney(json['tax_total'] ?? json['taxTotal']),
      shippingTotal: _safeMoney(json['shipping_total'] ?? json['shippingTotal']),
      discountTotal: _safeMoney(json['discount_total'] ?? json['discountTotal']),
      feesTotal: _safeMoney(json['fees_total'] ?? json['feesTotal']),
      total: _safeMoney(json['total']),
      currency: _safeString(json['currency']).isEmpty
          ? 'EUR'
          : _safeString(json['currency']),
      paymentMethod: _safeString(json['payment_method'] ?? json['paymentMethod']),
      paymentMethodTitle: _safeString(
        json['payment_method_title'] ?? json['paymentMethodTitle'],
      ),
      shippingMethodTitle: _safeString(
        json['shipping_method_title'] ?? json['shippingMethodTitle'],
      ),
      customerNote: _safeString(json['customer_note'] ?? json['customerNote']),
      billing: OrderAddress.fromJson(json['billing']),
      shipping: OrderAddress.fromJson(json['shipping']),
      actions: OrderActions.fromJson(json['actions']),
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

  static bool _parseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final raw = value.toString().trim().toLowerCase();
    return raw == '1' || raw == 'true' || raw == 'yes' || raw == 'si';
  }

  static DateTime _parseDate(dynamic value) {
    return _parseNullableDate(value) ?? DateTime.now();
  }

  static DateTime? _parseNullableDate(dynamic value) {
    if (value == null) return null;

    final raw = value.toString().trim();
    if (raw.isEmpty || raw.toLowerCase() == 'null') return null;

    return DateTime.tryParse(raw);
  }

  static String _safeString(dynamic value) {
    if (value == null) return '';
    final raw = value.toString().trim();
    if (raw.isEmpty || raw.toLowerCase() == 'null') return '';
    return raw;
  }

  static String _safeMoney(dynamic value) {
    final raw = _safeString(value);
    return raw.isEmpty ? '0' : raw;
  }

  static String _formatUnknownStatus(String status) {
    final clean = status
        .replaceFirst(RegExp(r'^wc-', caseSensitive: false), '')
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .trim()
        .toLowerCase();

    if (clean.isEmpty) return 'Estado';

    return clean
        .split(' ')
        .where((word) => word.trim().isNotEmpty)
        .map(
          (word) => word.length == 1
              ? word.toUpperCase()
              : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }
}

class OrderAddress {
  final String firstName;
  final String lastName;
  final String company;
  final String address1;
  final String address2;
  final String postcode;
  final String city;
  final String state;
  final String country;
  final String phone;
  final String email;

  const OrderAddress({
    this.firstName = '',
    this.lastName = '',
    this.company = '',
    this.address1 = '',
    this.address2 = '',
    this.postcode = '',
    this.city = '',
    this.state = '',
    this.country = '',
    this.phone = '',
    this.email = '',
  });

  factory OrderAddress.empty() => const OrderAddress();

  factory OrderAddress.fromJson(dynamic json) {
    if (json is! Map) return OrderAddress.empty();

    return OrderAddress(
      firstName: _parseString(json['first_name'] ?? json['firstName']),
      lastName: _parseString(json['last_name'] ?? json['lastName']),
      company: _parseString(json['company']),
      address1: _parseString(json['address_1'] ?? json['address1']),
      address2: _parseString(json['address_2'] ?? json['address2']),
      postcode: _parseString(json['postcode'] ?? json['post_code']),
      city: _parseString(json['city']),
      state: _parseString(json['state']),
      country: _parseString(json['country']),
      phone: _parseString(json['phone']),
      email: _parseString(json['email']),
    );
  }

  String get fullName => [firstName, lastName]
      .where((part) => part.trim().isNotEmpty)
      .join(' ')
      .trim();

  String get addressLine => [address1, address2]
      .where((part) => part.trim().isNotEmpty)
      .join(', ')
      .trim();

  String get cityLine => [postcode, city, state, country]
      .where((part) => part.trim().isNotEmpty)
      .join(' · ')
      .trim();

  bool get hasAnyVisibleValue =>
      fullName.isNotEmpty ||
      company.trim().isNotEmpty ||
      addressLine.isNotEmpty ||
      cityLine.isNotEmpty ||
      phone.trim().isNotEmpty ||
      email.trim().isNotEmpty;

  static String _parseString(dynamic value) {
    if (value == null) return '';
    final raw = value.toString().trim();
    if (raw.isEmpty || raw.toLowerCase() == 'null') return '';
    return raw;
  }
}

class OrderActions {
  final bool canPay;
  final bool canCancel;
  final bool canRepeat;
  final bool canRequestQuote;
  final bool canRequestRma;
  final bool hasExplicitValues;

  const OrderActions({
    this.canPay = false,
    this.canCancel = false,
    this.canRepeat = true,
    this.canRequestQuote = false,
    this.canRequestRma = false,
    this.hasExplicitValues = false,
  });

  factory OrderActions.defaults() => const OrderActions();

  factory OrderActions.fromJson(dynamic json) {
    if (json is! Map) return OrderActions.defaults();

    return OrderActions(
      canPay: _parseBool(json['can_pay'] ?? json['canPay']),
      canCancel: _parseBool(json['can_cancel'] ?? json['canCancel']),
      canRepeat: _parseBool(json['can_repeat'] ?? json['canRepeat']),
      canRequestQuote: _parseBool(
        json['can_request_quote'] ?? json['canRequestQuote'],
      ),
      canRequestRma: _parseBool(json['can_request_rma'] ?? json['canRequestRma']),
      hasExplicitValues: true,
    );
  }

  static bool _parseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final raw = value.toString().trim().toLowerCase();
    return raw == '1' || raw == 'true' || raw == 'yes' || raw == 'si';
  }
}

class OrderItem {
  final int productId;
  final int variationId;
  final String name;
  final int quantity;
  final double price;
  final double subtotal;
  final double total;
  final double taxTotal;
  final String sku;
  final String imageUrl;
  final String permalink;

  OrderItem({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.total,
    this.variationId = 0,
    this.price = 0,
    this.subtotal = 0,
    this.taxTotal = 0,
    this.sku = '',
    this.imageUrl = '',
    this.permalink = '',
  });

  double get unitPrice {
    if (price > 0) return price;
    if (quantity <= 0) return total;
    if (subtotal > 0) return subtotal / quantity;
    return total / quantity;
  }

  double get totalWithTax => total + taxTotal;

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    final subtotal = _parseDouble(json['subtotal']);
    final total = _parseDouble(json['total']);
    final taxTotal = _parseDouble(
      json['tax_total'] ?? json['tax'] ?? json['line_tax'],
    );
    final price = _parseDouble(json['price'] ?? json['unit_price']);

    return OrderItem(
      productId: _parseInt(
        json['product_id'] ?? json['productId'] ?? json['id_product'],
        fallback: 0,
      ),
      variationId: _parseInt(json['variation_id'] ?? json['variationId'], fallback: 0),
      name: _cleanText(
        json['name']?.toString() ??
            json['product_name']?.toString() ??
            'Producto',
      ),
      quantity: _parseInt(
        json['quantity'] ?? json['qty'],
        fallback: 1,
      ),
      price: price,
      subtotal: subtotal,
      total: total > 0 ? total : subtotal,
      taxTotal: taxTotal,
      sku: _parseString(
        json['sku'] ??
            json['product_sku'] ??
            json['ref'] ??
            json['reference'],
      ),
      imageUrl: _extractImageUrl(json),
      permalink: _parseString(json['permalink'] ?? json['product_url']),
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

  static String _parseString(dynamic value) {
    if (value == null) return '';
    final raw = value.toString().trim();
    if (raw.isEmpty || raw.toLowerCase() == 'null') return '';
    return raw;
  }

  static String _cleanText(String value) {
    return value.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  static String _extractImageUrl(Map<dynamic, dynamic> map) {
    final direct = _parseString(
      map['image_url'] ??
          map['imageUrl'] ??
          map['product_image'] ??
          map['productImage'] ??
          map['image_src'] ??
          map['imageSrc'] ??
          map['thumbnail'] ??
          map['thumbnail_url'] ??
          map['thumbnailUrl'] ??
          map['src'] ??
          map['url'],
    );
    if (direct.isNotEmpty) return direct;

    final image = map['image'];
    if (image is Map) {
      return _parseString(image['src'] ?? image['url'] ?? image['thumbnail']);
    }

    final images = map['images'];
    if (images is List && images.isNotEmpty) {
      final first = images.first;
      if (first is Map) {
        return _parseString(first['src'] ?? first['url'] ?? first['thumbnail']);
      }
      return _parseString(first);
    }

    return '';
  }
}

import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/features/orders/data/models/order_model.dart';
import 'package:mundicam/features/quotes/data/models/quote_model.dart';

class MundiCamAssistantReply {
  final String text;
  final bool searchProducts;
  final String searchQuery;

  const MundiCamAssistantReply({
    required this.text,
    this.searchProducts = false,
    this.searchQuery = '',
  });
}

class MundiCamAssistantService {
  MundiCamAssistantService({ApiService? api}) : _api = api ?? ApiService();

  final ApiService _api;

  Future<MundiCamAssistantReply> answer(String rawText) async {
    final original = rawText.trim().replaceAll(RegExp(r'\s+'), ' ');
    final normalized = _normalize(original);

    if (original.isEmpty) {
      return const MundiCamAssistantReply(
        text: 'Escribe qué necesitas y te ayudo paso a paso.',
      );
    }

    if (_containsAny(normalized, const <String>[
      'pedido',
      'pedidos',
      'seguimiento',
      'donde esta',
      'estado del envio',
    ])) {
      return MundiCamAssistantReply(text: await _ordersAnswer(original));
    }

    if (_containsAny(normalized, const <String>[
      'presupuesto',
      'presupuestos',
      'oferta',
      'cotizacion',
    ])) {
      return MundiCamAssistantReply(text: await _quotesAnswer(original));
    }

    if (_containsAny(normalized, const <String>[
      'gestor',
      'comercial',
      'tecnico asignado',
      'contacto asignado',
    ])) {
      return MundiCamAssistantReply(text: await _managerAnswer());
    }

    if (_containsAny(normalized, const <String>[
      'credito',
      'giro',
      'aplazado',
      'forma de pago',
      'tarjeta',
      'redsys',
      'transferencia',
    ])) {
      return MundiCamAssistantReply(text: await _paymentAnswer());
    }

    if (_containsAny(normalized, const <String>[
      'envio',
      'transporte',
      'portes',
      'recoger',
      'recogida',
    ])) {
      return const MundiCamAssistantReply(
        text:
            'El coste exacto lo calcula el servidor de MundiCam con tu dirección y los productos del carrito. Con la regla de envío actualizada, por debajo de 350 € se muestran los envíos de pago disponibles; la recogida y tu propio transportista pueden seguir a 0 €. Abre el carrito para ver el importe final antes de confirmar.',
      );
    }

    if (_containsAny(normalized, const <String>[
      'rma',
      'garantia',
      'averia',
      'devolucion',
      'producto roto',
    ])) {
      return MundiCamAssistantReply(text: await _rmaAnswer());
    }

    if (_containsAny(normalized, const <String>[
      'telefono',
      'llamar',
      'whatsapp',
      'email',
      'correo',
      'contacto',
      'ayuda humana',
    ])) {
      return MundiCamAssistantReply(text: await _contactAnswer());
    }

    return MundiCamAssistantReply(
      text:
          'Voy a buscar “$original” en el catálogo. Puedes escribir una referencia, un SKU, una marca o una descripción sencilla.',
      searchProducts: true,
      searchQuery: original,
    );
  }

  Future<String> _ordersAnswer(String original) async {
    final email = await _api.currentSessionEmail();
    if (email == null || email.trim().isEmpty) {
      return 'No he podido identificar tu cuenta. Cierra esta pantalla, vuelve a iniciar sesión y prueba otra vez.';
    }

    final orders = await _api.getOrders(email);
    if (orders.isEmpty) {
      return 'No encuentro pedidos en tu cuenta. Si acabas de realizar uno, pulsa actualizar en “Mis pedidos” dentro de unos segundos.';
    }

    final requestedNumber = _firstNumber(original);
    OrderMundicam? selected;
    if (requestedNumber != null) {
      for (final order in orders) {
        final number = order.number.trim();
        if (order.id.toString() == requestedNumber ||
            number == requestedNumber ||
            number.replaceAll(RegExp(r'[^0-9]'), '') == requestedNumber) {
          selected = order;
          break;
        }
      }
    }

    final current = selected ?? orders.first;
    final label = current.number.trim().isNotEmpty
        ? current.number.trim()
        : current.id.toString();
    final total = _money(current.total, current.currency);

    if (requestedNumber != null && selected == null) {
      return 'No he encontrado el pedido $requestedNumber entre tus pedidos recientes. El último es el #$label, está “${current.displayStatusLabel}” y su total es $total. Abre “Mis pedidos” para verlos todos.';
    }

    return 'Tu pedido #$label está “${current.displayStatusLabel}”. Total: $total. Tienes ${orders.length} pedido${orders.length == 1 ? '' : 's'} en la cuenta. En “Mis pedidos” puedes abrir el detalle completo.';
  }

  Future<String> _quotesAnswer(String original) async {
    final email = await _api.currentSessionEmail();
    if (email == null || email.trim().isEmpty) {
      return 'No he podido identificar tu cuenta. Vuelve a iniciar sesión y prueba otra vez.';
    }

    final quotes = await _api.getPresupuestosPorEmail(email);
    if (quotes.isEmpty) {
      return 'No encuentro presupuestos pendientes en tu cuenta. Los presupuestos locales también se consultan desde la pestaña “Presupuestos”.';
    }

    final requestedNumber = _firstNumber(original);
    QuoteMundicam? selected;
    if (requestedNumber != null) {
      for (final quote in quotes) {
        if (quote.orderIdRaw == requestedNumber ||
            quote.id.replaceAll(RegExp(r'[^0-9]'), '') == requestedNumber) {
          selected = quote;
          break;
        }
      }
    }

    final current = selected ?? quotes.first;
    final total = '${current.total.toStringAsFixed(2)} €';

    if (requestedNumber != null && selected == null) {
      return 'No he encontrado el presupuesto $requestedNumber entre los pendientes. El más reciente es ${current.id}, está “${current.statusLabel}” y su importe es $total.';
    }

    return 'El presupuesto ${current.id} está “${current.statusLabel}” y su importe es $total. Tienes ${quotes.length} presupuesto${quotes.length == 1 ? '' : 's'} pendiente${quotes.length == 1 ? '' : 's'}. Abre “Mis presupuestos” para ver los productos y pagar cuando corresponda.';
  }

  Future<String> _managerAnswer() async {
    await _api.refreshSessionContextFromBackend(force: true);
    final user = await _api.currentSessionUser();
    final manager = _managerData(user);

    if (manager.name.isEmpty) {
      return 'No aparece un gestor asignado en tu ficha. Puedes usar los botones de WhatsApp, llamada o email de esta pantalla para que MundiCam te ayude.';
    }

    final parts = <String>['Tu gestor asignado es ${manager.name}.'];
    if (manager.email.isNotEmpty) parts.add('Correo: ${manager.email}.');
    if (manager.phone.isNotEmpty) parts.add('Teléfono: ${manager.phone}.');
    if (manager.email.isEmpty && manager.phone.isEmpty) {
      parts.add('Todavía no tengo sus datos de contacto; usa los botones generales de soporte.');
    }
    return parts.join(' ');
  }

  Future<String> _paymentAnswer() async {
    await _api.refreshSessionContextFromBackend(force: true);
    final user = await _api.currentSessionUser();
    final credit = _readNumber(user, const <String>[
      'credit_available',
      'credito_disponible',
      'saldo_credito',
    ]);

    final manager = _managerData(user);
    final parts = <String>[
      'En la pantalla de finalizar pedido verás únicamente las formas de pago disponibles para tu cuenta.',
      'Con el PHP de pago seguro actualizado, la tarjeta se abre mediante Redsys dentro de la app. Si aparece un login web, el servidor todavía está usando el enlace antiguo.',
    ];

    if (credit != null && credit > 0) {
      parts.add('Crédito disponible aproximado: ${credit.toStringAsFixed(2)} €.');
    } else {
      parts.add('El pago aplazado solo aparece cuando tu ficha tiene crédito autorizado.');
    }

    if (manager.name.isNotEmpty) {
      parts.add('Para cambios, consulta con ${manager.name}.');
    }
    return parts.join(' ');
  }

  Future<String> _rmaAnswer() async {
    final email = await _api.currentSessionEmail();
    if (email == null || email.trim().isEmpty) {
      return 'No he podido identificar tu cuenta. Vuelve a iniciar sesión para consultar las garantías.';
    }

    final orders = await _api.getOrders(email);
    final eligible = orders.where((order) => order.canRequestRma).toList();
    if (eligible.isEmpty) {
      return 'No encuentro ahora mismo pedidos recientes habilitados para solicitar RMA desde la app. Puedes abrir “Mis pedidos” o contactar con soporte indicando pedido, producto y número de serie.';
    }

    final first = eligible.first;
    final number = first.number.trim().isNotEmpty
        ? first.number.trim()
        : first.id.toString();
    return 'He encontrado ${eligible.length} pedido${eligible.length == 1 ? '' : 's'} desde los que puedes revisar una garantía o RMA. El más reciente es el #$number. Ábrelo en “Mis pedidos” y pulsa la opción de garantía cuando esté disponible.';
  }

  Future<String> _contactAnswer() async {
    final managerAnswer = await _managerAnswer();
    return '$managerAnswer También puedes usar los botones grandes de WhatsApp, llamada y email que aparecen arriba.';
  }

  _ManagerData _managerData(Map<String, dynamic> user) {
    final nested = _asMap(user['manager']);
    final name = _firstText(<dynamic>[
      user['manager_name'],
      user['assigned_manager'],
      user['gestor_asignado'],
      user['wpuef_cid_c30'],
      nested['name'],
    ]);
    final email = _firstText(<dynamic>[
      user['manager_email'],
      nested['email'],
    ]);
    final phone = _firstText(<dynamic>[
      user['manager_phone'],
      nested['phone'],
    ]);
    return _ManagerData(name: name, email: email, phone: phone);
  }

  double? _readNumber(Map<String, dynamic> user, List<String> keys) {
    for (final key in keys) {
      final parsed = _parseDouble(user[key]);
      if (parsed != null) return parsed;
    }

    final meta = user['meta_data'];
    if (meta is List) {
      for (final item in meta) {
        if (item is! Map) continue;
        final key = item['key']?.toString().trim().toLowerCase() ?? '';
        if (!keys.contains(key)) continue;
        final parsed = _parseDouble(item['value']);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final raw = value
        .toString()
        .replaceAll('€', '')
        .replaceAll(' ', '')
        .trim();
    if (raw.isEmpty) return null;
    if (raw.contains(',') && raw.contains('.')) {
      return double.tryParse(raw.replaceAll('.', '').replaceAll(',', '.'));
    }
    return double.tryParse(raw.replaceAll(',', '.'));
  }

  String _money(String raw, String currency) {
    final value = _parseDouble(raw) ?? 0;
    final symbol = currency.trim().toUpperCase() == 'EUR' ? '€' : currency.trim();
    return '${value.toStringAsFixed(2)} $symbol'.trim();
  }

  String? _firstNumber(String text) {
    final match = RegExp(r'\b\d{3,}\b').firstMatch(text);
    return match?.group(0);
  }

  String _firstText(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isEmpty || text.toLowerCase() == 'null' || text == '—') continue;
      return text;
    }
    return '';
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  bool _containsAny(String text, List<String> words) {
    return words.any(text.contains);
  }

  String _normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('ä', 'a')
        .replaceAll('â', 'a')
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ì', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('î', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ò', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ù', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('û', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class _ManagerData {
  final String name;
  final String email;
  final String phone;

  const _ManagerData({
    required this.name,
    required this.email,
    required this.phone,
  });
}

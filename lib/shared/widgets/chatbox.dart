import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:mundicam/features/orders/presentation/pages/orders_page.dart';
import 'package:mundicam/features/catalog/presentation/pages/productos_page.dart';
import 'package:mundicam/features/quotes/presentation/pages/quotes_page.dart';
import 'package:mundicam/core/network/api_service.dart';

// ================================================================
// PROVIDER
// ================================================================

final chatBoxProvider = StateProvider<bool>((ref) => false);

// ================================================================
// CHAT BOX
// ================================================================

class ChatBox extends ConsumerStatefulWidget {
  const ChatBox({super.key});

  @override
  ConsumerState<ChatBox> createState() => _ChatBoxState();
}

class _ChatBoxState extends ConsumerState<ChatBox> {
  // ---------------------------------------------------------------
  // COLORES CORPORATIVOS
  // ---------------------------------------------------------------

  static const Color _brandRed = Color(0xFFA60909);
  static const Color _brandRedLight = Color(0xFFD71920);
  static const Color _brandRedDark = Color(0xFF7A0505);
  static const Color _dark = Color(0xFF111827);
  static const Color _surface = Color(0xFFF8F9FB);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _onlineGreen = Color(0xFF34D399);

  // ---------------------------------------------------------------
  // CONTACTO
  // ---------------------------------------------------------------

  static const String _telefono = '968629383';
  static const String _telefonoFormateado = '968 62 93 83';
  static const String _whatsapp = '34619078632';
  static const String _whatsappFormateado = '619 078 632';
  static const String _email = 'info@mundicam.com';
  static const String _web = 'https://www.mundicam.com';
  static const String _academy = 'https://www.mundicam.com/academy/';

  static const String _welcomeMessage =
      '👋 ¡Hola! Soy el asistente de MundiCam. Puedo ayudarte con productos, pedidos, presupuestos, RMA, crédito y soporte.';

  // ---------------------------------------------------------------
  // ESTADO
  // ---------------------------------------------------------------

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();

  String _currentNodeKey = 'root';
  List<_ChatOption>? _contextOptions;
  bool _isTyping = false;

  final List<_ChatMessage> _messages = const [
    _ChatMessage(sender: _ChatSender.bot, text: _welcomeMessage),
  ].toList();

  late final Map<String, _ChatNode> _nodes = _buildNodes();

  final Map<String, String> _brandMap = {
    'ajax': 'Ajax',
    'dahua': 'Dahua',
    'hikvision': 'Hikvision',
    'hiwatch': 'HiWatch',
    'ksenia': 'Ksenia',
    'tp link': 'TP-Link',
    'tplink': 'TP-Link',
    'tp-link': 'TP-Link',
    'omada': 'Omada',
    'mobotix': 'Mobotix',
    'bosch': 'Bosch',
    'teletek': 'Teletek',
    'zkteco': 'ZKTeco',
    'zk teco': 'ZKTeco',
    'anviz': 'Anviz',
    'yale': 'Yale',
    'paradox': 'Paradox',
    'satel': 'Satel',
    'honeywell': 'Honeywell',
    'siemens': 'Siemens',
    'wisenet': 'Wisenet',
    'hanwha': 'Hanwha',
    'vivotek': 'Vivotek',
    'uniview': 'Uniview',
    'axis': 'Axis',
    'pelco': 'Pelco',
    'wisim': 'WISIM',
    'wis': 'WISIM',
    'evolve': 'Evolve Xtender',
    'xtender': 'Evolve Xtender',
  };

  final List<_CategoryDef> _categories = const [
    _CategoryDef(
      key: 'video',
      title: 'Videovigilancia',
      icon: Icons.videocam_rounded,
      search: 'videovigilancia camara cctv nvr dvr',
      prompt:
      '🎥 Videovigilancia profesional: cámaras, grabadores, accesorios, discos, PoE y analítica.',
      brands: [
        'Hikvision',
        'Dahua',
        'Mobotix',
        'Wisenet',
        'Hanwha',
        'Uniview',
        'Axis',
      ],
    ),
    _CategoryDef(
      key: 'alarmas',
      title: 'Alarmas e Intrusión',
      icon: Icons.security_rounded,
      search: 'alarmas intrusion detector sirena central',
      prompt:
      '🚨 Alarmas e intrusión: centrales, detectores, sirenas, teclados, mandos y accesorios.',
      brands: ['Ajax', 'Ksenia', 'Paradox', 'Satel', 'Honeywell', 'Bosch'],
    ),
    _CategoryDef(
      key: 'acceso',
      title: 'Control de Acceso',
      icon: Icons.lock_rounded,
      search: 'control de acceso lector cerradura biometrico',
      prompt:
      '🔐 Control de acceso: lectores, cerraduras, terminales, controladoras e identificación.',
      brands: ['ZKTeco', 'Anviz', 'Yale'],
    ),
    _CategoryDef(
      key: 'incendio',
      title: 'Incendio',
      icon: Icons.local_fire_department_rounded,
      search: 'incendio central detector humo pulsador sirena',
      prompt:
      '🔥 Incendio: centrales, detectores, pulsadores, sirenas, módulos y accesorios.',
      brands: ['Teletek', 'Honeywell', 'Siemens'],
    ),
    _CategoryDef(
      key: 'networking',
      title: 'Networking',
      icon: Icons.hub_rounded,
      search: 'networking switch poe router wifi omada',
      prompt:
      '🌐 Networking: switches PoE, routers, WiFi profesional, controladores y puntos de acceso.',
      brands: ['TP-Link', 'Omada'],
    ),
    _CategoryDef(
      key: 'iot',
      title: 'IoT / M2M',
      icon: Icons.sim_card_rounded,
      search: 'wisim sim m2m iot multioperador apn',
      prompt:
      '📡 IoT/M2M: conectividad multioperador para CCTV, alarmas, telemetría, movilidad e industria.',
      brands: ['WISIM'],
    ),
    _CategoryDef(
      key: 'autonoma',
      title: 'Seguridad autónoma',
      icon: Icons.solar_power_rounded,
      search: 'seguridad autonoma solar torre pod evolve xtender',
      prompt:
      '☀️ Seguridad autónoma: torres, POD, energía solar, vídeo, analítica y conectividad.',
      brands: ['Evolve Xtender'],
    ),
  ];

  final List<_FaqDef> _faqs = const [
    _FaqDef(
      key: 'pedido',
      title: '¿Cómo hago un pedido?',
      icon: Icons.shopping_cart_checkout_rounded,
      answer:
      '🛒 Para hacer un pedido: entra en catálogo, abre un producto, selecciona cantidad, añádelo al carrito y finaliza desde Checkout.',
      options: [
        _ChatOption(
          label: 'Abrir catálogo',
          icon: Icons.grid_view_rounded,
          action: _ChatAction.openCatalog,
          successMessage: '📋 Abriendo catálogo...',
        ),
      ],
    ),
    _FaqDef(
      key: 'presupuesto',
      title: '¿Cómo pido presupuesto?',
      icon: Icons.request_quote_rounded,
      answer:
      '📄 Puedes solicitar presupuesto desde el botón "Presupuesto" del producto. Si no hay stock, la compra queda bloqueada, pero puedes pedir valoración comercial.',
      options: [
        _ChatOption(
          label: 'Ir a presupuestos',
          icon: Icons.description_rounded,
          action: _ChatAction.navigateToQuotes,
          successMessage: '📄 Abriendo presupuestos...',
        ),
        _ChatOption(
          label: 'Contactar comercial',
          icon: Icons.chat_rounded,
          action: _ChatAction.whatsapp,
          whatsappText:
          'Hola MundiCam, necesito ayuda para preparar un presupuesto.',
        ),
      ],
    ),
    _FaqDef(
      key: 'pedidos',
      title: '¿Dónde veo mis pedidos?',
      icon: Icons.local_shipping_rounded,
      answer:
      '📦 Puedes consultar tus pedidos desde la sección "Pedidos". Verás estado, fecha, total y productos incluidos.',
      options: [
        _ChatOption(
          label: 'Ir a pedidos',
          icon: Icons.local_shipping_rounded,
          action: _ChatAction.navigateToOrders,
          successMessage: '📦 Abriendo pedidos...',
        ),
      ],
    ),
    _FaqDef(
      key: 'rma',
      title: '¿Cómo solicito RMA?',
      icon: Icons.assignment_return_rounded,
      answer:
      '🔧 Para solicitar una RMA, entra en pedidos, localiza un pedido completado y pulsa el botón RMA del producto correspondiente.',
      options: [
        _ChatOption(
          label: 'Ir a pedidos',
          icon: Icons.local_shipping_rounded,
          action: _ChatAction.navigateToOrders,
          successMessage: '📦 Abriendo pedidos para gestionar RMA...',
        ),
        _ChatOption(
          label: 'Contactar soporte',
          icon: Icons.chat_rounded,
          action: _ChatAction.whatsapp,
          whatsappText: 'Hola MundiCam, necesito ayuda para gestionar una RMA.',
        ),
      ],
    ),
    _FaqDef(
      key: 'credito',
      title: 'Crédito disponible',
      icon: Icons.account_balance_wallet_rounded,
      answer:
      '💳 Tu crédito se consulta desde Perfil. La app muestra límite, crédito usado y crédito disponible.',
      options: [
        _ChatOption(
          label: 'Contactar gestor',
          icon: Icons.support_agent_rounded,
          action: _ChatAction.whatsapp,
          whatsappText:
          'Hola MundiCam, necesito consultar mi crédito disponible.',
        ),
      ],
    ),
    _FaqDef(
      key: 'direccion',
      title: 'Cambiar dirección',
      icon: Icons.location_on_rounded,
      answer:
      '📍 La dirección de envío se puede editar durante el Checkout. Empresa y CIF/NIF permanecen bloqueados porque vienen de WooCommerce.',
      options: [
        _ChatOption(
          label: 'Abrir catálogo',
          icon: Icons.grid_view_rounded,
          action: _ChatAction.openCatalog,
          successMessage: '📋 Abriendo catálogo...',
        ),
      ],
    ),
    _FaqDef(
      key: 'gestor',
      title: 'Mi gestor',
      icon: Icons.support_agent_rounded,
      answer:
      '👤 Tu gestor asignado aparece en Perfil, dentro de los datos empresariales cargados desde WooCommerce.',
      options: [
        _ChatOption(
          label: 'Contactar gestor',
          icon: Icons.chat_rounded,
          action: _ChatAction.whatsapp,
          whatsappText:
          'Hola MundiCam, necesito contactar con mi gestor asignado.',
        ),
      ],
    ),
    _FaqDef(
      key: 'stock',
      title: 'Stock y disponibilidad',
      icon: Icons.inventory_2_rounded,
      answer:
      '📦 El stock aparece en la tarjeta y en la ficha del producto. Si no hay stock, la compra se bloquea y puedes solicitar presupuesto.',
      options: [
        _ChatOption(
          label: 'Abrir catálogo',
          icon: Icons.grid_view_rounded,
          action: _ChatAction.openCatalog,
          successMessage: '📋 Abriendo catálogo...',
        ),
      ],
    ),
  ];

  @override
  void dispose() {
    _scrollController.dispose();
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  Map<String, _ChatNode> _buildNodes() {
    final nodes = <String, _ChatNode>{
      'root': _ChatNode(
        prompt: '¿Qué necesitas?',
        options: [
          const _ChatOption(
            label: 'Catálogo',
            icon: Icons.grid_view_rounded,
            nextNodeKey: 'catalog',
          ),
          const _ChatOption(
            label: 'Buscar producto',
            icon: Icons.search_rounded,
            nextNodeKey: 'buscar',
          ),
          const _ChatOption(
            label: 'Pedidos',
            icon: Icons.local_shipping_rounded,
            action: _ChatAction.navigateToOrders,
            successMessage: '📦 Abriendo pedidos...',
          ),
          const _ChatOption(
            label: 'Presupuestos',
            icon: Icons.description_rounded,
            action: _ChatAction.navigateToQuotes,
            successMessage: '📄 Abriendo presupuestos...',
          ),
          const _ChatOption(
            label: 'Soporte / RMA',
            icon: Icons.build_rounded,
            nextNodeKey: 'soporte',
          ),
          const _ChatOption(
            label: 'Cuenta B2B',
            icon: Icons.business_center_rounded,
            nextNodeKey: 'cuenta',
          ),
          const _ChatOption(
            label: 'Contacto',
            icon: Icons.headset_mic_rounded,
            nextNodeKey: 'contacto',
          ),
        ],
      ),
      'buscar': _ChatNode(
        prompt:
        '🔎 Escribe una marca, referencia o tipo de producto. Ejemplos: "Ajax", "Dahua", "NVR", "cámara IP", "switch PoE" o "KSI".',
        options: [
          const _ChatOption(
            label: 'Abrir catálogo',
            icon: Icons.grid_view_rounded,
            action: _ChatAction.openCatalog,
          ),
          const _ChatOption(
            label: 'Hablar con MundiCam',
            icon: Icons.chat_rounded,
            action: _ChatAction.whatsapp,
          ),
          const _ChatOption(
            label: 'Volver',
            icon: Icons.arrow_back_rounded,
            nextNodeKey: 'root',
          ),
        ],
      ),
      'catalog': _ChatNode(
        prompt: 'Elige una familia o abre el catálogo completo:',
        options: [
          const _ChatOption(
            label: 'Catálogo completo',
            icon: Icons.shopping_bag_rounded,
            action: _ChatAction.openCatalog,
            successMessage: '📋 Abriendo catálogo completo...',
          ),
          ..._categories.map(
                (category) => _ChatOption(
              label: category.title,
              icon: category.icon,
              nextNodeKey: 'cat_${category.key}',
            ),
          ),
          const _ChatOption(
            label: 'Outlet / ofertas',
            icon: Icons.sell_rounded,
            action: _ChatAction.openCatalog,
            searchQuery: 'outlet oferta descuento',
            successMessage: '🔥 Abriendo catálogo para consultar ofertas...',
          ),
          const _ChatOption(
            label: 'Volver',
            icon: Icons.arrow_back_rounded,
            nextNodeKey: 'root',
          ),
        ],
      ),
      'pedidos': _ChatNode(
        prompt:
        '📦 Consulta pedidos, estados, productos incluidos y gestiones asociadas.',
        options: [
          const _ChatOption(
            label: 'Ir a pedidos',
            icon: Icons.local_shipping_rounded,
            action: _ChatAction.navigateToOrders,
            successMessage: '📦 Abriendo pedidos...',
          ),
          _faqOption('pedido'),
          _faqOption('pedidos'),
          _faqOption('rma'),
          const _ChatOption(
            label: 'Volver',
            icon: Icons.arrow_back_rounded,
            nextNodeKey: 'root',
          ),
        ],
      ),
      'presupuestos': _ChatNode(
        prompt: '📄 Gestiona presupuestos aceptables y solicitudes comerciales.',
        options: [
          const _ChatOption(
            label: 'Ir a presupuestos',
            icon: Icons.description_rounded,
            action: _ChatAction.navigateToQuotes,
            successMessage: '📄 Abriendo presupuestos...',
          ),
          _faqOption('presupuesto'),
          const _ChatOption(
            label: 'Pedir ayuda comercial',
            icon: Icons.chat_rounded,
            action: _ChatAction.whatsapp,
            whatsappText:
            'Hola MundiCam, necesito ayuda con un presupuesto profesional.',
          ),
          const _ChatOption(
            label: 'Volver',
            icon: Icons.arrow_back_rounded,
            nextNodeKey: 'root',
          ),
        ],
      ),
      'soporte': _ChatNode(
        prompt: '🔧 Soporte técnico, RMA, documentación y garantía.',
        options: [
          _faqOption('rma'),
          const _ChatOption(
            label: 'Consulta técnica',
            icon: Icons.engineering_rounded,
            action: _ChatAction.whatsapp,
            whatsappText:
            'Hola MundiCam, necesito soporte técnico sobre un producto o instalación.',
          ),
          const _ChatOption(
            label: 'Pedir documentación',
            icon: Icons.menu_book_rounded,
            action: _ChatAction.whatsapp,
            whatsappText:
            'Hola MundiCam, necesito documentación técnica de un producto.',
          ),
          const _ChatOption(
            label: 'Garantía',
            icon: Icons.verified_user_rounded,
            action: _ChatAction.whatsapp,
            whatsappText:
            'Hola MundiCam, necesito consultar la garantía de un producto.',
          ),
          const _ChatOption(
            label: 'Volver',
            icon: Icons.arrow_back_rounded,
            nextNodeKey: 'root',
          ),
        ],
      ),
      'cuenta': _ChatNode(
        prompt:
        '👤 Datos de empresa, crédito, gestor asignado, dirección y condiciones B2B.',
        options: [
          _faqOption('credito'),
          _faqOption('gestor'),
          _faqOption('direccion'),
          const _ChatOption(
            label: 'Contactar gestor',
            icon: Icons.chat_rounded,
            action: _ChatAction.whatsapp,
            whatsappText:
            'Hola MundiCam, necesito contactar con mi gestor comercial.',
          ),
          const _ChatOption(
            label: 'Volver',
            icon: Icons.arrow_back_rounded,
            nextNodeKey: 'root',
          ),
        ],
      ),
      'contacto': _ChatNode(
        prompt: '📞 Elige cómo quieres contactar con MundiCam:',
        options: [
          const _ChatOption(
            label: 'WhatsApp ($_whatsappFormateado)',
            icon: Icons.chat_rounded,
            action: _ChatAction.whatsapp,
            whatsappText:
            'Hola MundiCam, necesito ayuda desde la app profesional.',
          ),
          const _ChatOption(
            label: 'Llamar ($_telefonoFormateado)',
            icon: Icons.call_rounded,
            action: _ChatAction.phone,
          ),
          const _ChatOption(
            label: 'Email ($_email)',
            icon: Icons.email_rounded,
            action: _ChatAction.email,
            emailSubject: 'Consulta desde App MundiCam',
          ),
          const _ChatOption(
            label: 'Web MundiCam',
            icon: Icons.language_rounded,
            action: _ChatAction.web,
            webUrl: _web,
          ),
          const _ChatOption(
            label: 'MundiCam Academy',
            icon: Icons.school_rounded,
            action: _ChatAction.web,
            webUrl: _academy,
          ),
          const _ChatOption(
            label: 'Volver',
            icon: Icons.arrow_back_rounded,
            nextNodeKey: 'root',
          ),
        ],
      ),
    };

    for (final category in _categories) {
      nodes['cat_${category.key}'] = _ChatNode(
        prompt: category.prompt,
        options: [
          _ChatOption(
            label: 'Ver ${category.title}',
            icon: Icons.grid_view_rounded,
            action: _ChatAction.openCatalog,
            searchQuery: category.search,
            successMessage: '📋 Abriendo catálogo de ${category.title}...',
          ),
          ...category.brands.map(
                (brand) => _ChatOption(
              label: brand,
              icon: Icons.sell_outlined,
              action: _ChatAction.searchBrand,
              brandName: brand,
              successMessage: '🔎 Buscando $brand...',
            ),
          ),
          const _ChatOption(
            label: 'Asesoramiento',
            icon: Icons.chat_rounded,
            action: _ChatAction.whatsapp,
            whatsappText:
            'Hola MundiCam, necesito asesoramiento sobre un proyecto profesional.',
          ),
          const _ChatOption(
            label: 'Volver',
            icon: Icons.arrow_back_rounded,
            nextNodeKey: 'catalog',
          ),
        ],
      );
    }

    for (final faq in _faqs) {
      nodes['faq_${faq.key}'] = _ChatNode(
        prompt: faq.answer,
        options: [
          ...faq.options,
          const _ChatOption(
            label: 'Volver al menú',
            icon: Icons.home_rounded,
            nextNodeKey: 'root',
          ),
        ],
      );
    }

    return nodes;
  }

  _ChatOption _faqOption(String key) {
    final faq = _faqs.firstWhere((item) => item.key == key);
    return _ChatOption(
      label: faq.title,
      icon: faq.icon,
      nextNodeKey: 'faq_$key',
    );
  }

  void _toggleChat() {
    final isOpen = ref.read(chatBoxProvider);
    ref.read(chatBoxProvider.notifier).state = !isOpen;

    if (isOpen) {
      FocusScope.of(context).unfocus();
    } else {
      _scrollToBottom();
    }
  }

  void _resetChat() {
    setState(() {
      _messages
        ..clear()
        ..add(
          const _ChatMessage(sender: _ChatSender.bot, text: _welcomeMessage),
        );
      _currentNodeKey = 'root';
      _contextOptions = null;
      _isTyping = false;
      _inputController.clear();
    });

    _scrollToBottom();
  }

  void _addMessage(_ChatSender sender, String text) {
    if (!mounted) return;

    setState(() {
      _messages.add(_ChatMessage(sender: sender, text: text));
    });

    _scrollToBottom();
  }

  Future<void> _simulateTyping({int milliseconds = 450}) async {
    if (!mounted) return;

    setState(() => _isTyping = true);
    _scrollToBottom();

    await Future.delayed(Duration(milliseconds: milliseconds));

    if (!mounted) return;

    setState(() => _isTyping = false);
    _scrollToBottom();
  }

  String _normalize(String input) {
    return input
        .toLowerCase()
        .trim()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n');
  }

  bool _containsAny(String text, List<String> terms) {
    final normalized = _normalize(text);
    return terms.any((term) => normalized.contains(_normalize(term)));
  }

  String? _detectBrand(String text) {
    final normalized = _normalize(text);

    for (final entry in _brandMap.entries) {
      if (normalized.contains(entry.key)) {
        return entry.value;
      }
    }

    return null;
  }

  bool _looksLikeReference(String raw) {
    final value = raw.trim().toUpperCase();

    return RegExp(r'[A-Z]{2,}[-_][A-Z0-9]').hasMatch(value) ||
        RegExp(r'\b[A-Z]{2,}[0-9]{2,}[A-Z0-9-]*\b').hasMatch(value) ||
        value.startsWith('IPC') ||
        value.startsWith('DHI') ||
        value.startsWith('DS-') ||
        value.startsWith('AJ-') ||
        value.startsWith('KSI') ||
        value.startsWith('DH-');
  }

  void _showNode(String key) {
    final node = _nodes[key];
    if (node == null) return;

    setState(() {
      _currentNodeKey = key;
      _contextOptions = null;
    });

    _addMessage(_ChatSender.bot, node.prompt);
  }

  Future<void> _handleOption(_ChatOption option) async {
    if (_isTyping) return;

    FocusScope.of(context).unfocus();
    _addMessage(_ChatSender.user, option.label);

    await _simulateTyping();

    if (option.successMessage != null && option.successMessage!.isNotEmpty) {
      _addMessage(_ChatSender.bot, option.successMessage!);
    }

    if (option.action != null) {
      await _handleAction(option);
      return;
    }

    if (option.nextNodeKey != null) {
      _showNode(option.nextNodeKey!);
    }
  }

  Future<void> _handleAction(_ChatOption option) async {
    switch (option.action!) {
      case _ChatAction.openCatalog:
        _openCatalog(
          searchQuery: option.searchQuery,
          brandName: option.brandName,
        );
        break;

      case _ChatAction.searchBrand:
        final brand = option.brandName;
        if (brand == null) return;

        _addMessage(
          _ChatSender.bot,
          'Te llevo al catálogo para buscar $brand.',
        );

        _openCatalog(searchQuery: brand, brandName: brand);
        break;

      case _ChatAction.navigateToOrders:
        _navigateToOrders();
        break;

      case _ChatAction.navigateToQuotes:
        _navigateToQuotes();
        break;

      case _ChatAction.whatsapp:
        await _openWhatsApp(
          option.whatsappText ??
              'Hola MundiCam, necesito ayuda desde la app profesional.',
        );
        break;

      case _ChatAction.phone:
        await _safeLaunch(
          Uri.parse('tel:$_telefono'),
          errorMessage: 'No he podido iniciar la llamada.',
        );
        break;

      case _ChatAction.email:
        await _safeLaunch(
          Uri(
            scheme: 'mailto',
            path: _email,
            queryParameters: {
              'subject': option.emailSubject ?? 'Consulta desde App MundiCam',
            },
          ),
          errorMessage: 'No he podido abrir el correo.',
        );
        break;

      case _ChatAction.web:
        await _safeLaunch(
          Uri.parse(option.webUrl ?? _web),
          mode: LaunchMode.externalApplication,
          errorMessage: 'No he podido abrir el enlace.',
        );
        break;
    }
  }

  void _navigateToOrders() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const OrdersPage()),
    );
    _closeChatAfterNavigation();
  }

  void _navigateToQuotes() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QuotesPage()),
    );
    _closeChatAfterNavigation();
  }

  void _openCatalog({String? searchQuery, String? brandName}) {
    final args = <String, String>{};

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      args['searchQuery'] = searchQuery.trim();
    }

    if (brandName != null && brandName.trim().isNotEmpty) {
      args['brandName'] = brandName.trim();
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductosPage(
          onGoHome: () => Navigator.pop(context),
          onGoCart: () {},
          onGoQuotes: () {},
        ),
        settings: RouteSettings(arguments: args.isEmpty ? null : args),
      ),
    );
    _closeChatAfterNavigation();
  }

  void _closeChatAfterNavigation() {
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      ref.read(chatBoxProvider.notifier).state = false;
      FocusScope.of(context).unfocus();
    });
  }

  Future<void> _openWhatsApp(String text) async {
    await _safeLaunch(
      Uri.https('wa.me', '/$_whatsapp', {'text': text}),
      mode: LaunchMode.externalApplication,
      errorMessage: 'No he podido abrir WhatsApp.',
    );
  }

  Future<void> _safeLaunch(
      Uri uri, {
        LaunchMode mode = LaunchMode.platformDefault,
        required String errorMessage,
      }) async {
    try {
      final launched = await launchUrl(uri, mode: mode);
      if (!launched && mounted) {
        _addMessage(_ChatSender.bot, '⚠️ $errorMessage');
      }
    } catch (_) {
      if (mounted) {
        _addMessage(_ChatSender.bot, '⚠️ $errorMessage');
      }
    }
  }

  Future<void> _searchProductAndNavigate(String query) async {
    try {
      final api = ApiService();
      final productos = await api.buscarProductos(query);

      if (!mounted) return;

      if (productos.isEmpty) {
        _addMessage(
          _ChatSender.bot,
          'No he encontrado productos con "$query". ¿Quieres abrir el catálogo para buscar?',
        );
        _setContextOptions([
          _ChatOption(
            label: 'Abrir catálogo',
            icon: Icons.grid_view_rounded,
            action: _ChatAction.openCatalog,
            searchQuery: query,
          ),
          const _ChatOption(
            label: 'Volver al menú',
            icon: Icons.home_rounded,
            nextNodeKey: 'root',
          ),
        ]);
        return;
      }

      if (productos.length == 1) {
        final producto = productos.first;
        _addMessage(_ChatSender.bot, '✅ Encontrado: ${producto.name}');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProductosPage(
              onGoHome: () => Navigator.pop(context),
              onGoCart: () {},
              onGoQuotes: () {},
            ),
          ),
        );
        _closeChatAfterNavigation();
        return;
      }

      final message =
          'Encontrados ${productos.length} productos. ¿Quieres verlos en el catálogo?';
      _addMessage(_ChatSender.bot, message);
      _setContextOptions([
        _ChatOption(
          label: 'Ver en catálogo',
          icon: Icons.grid_view_rounded,
          action: _ChatAction.openCatalog,
          searchQuery: query,
          successMessage: '📋 Abriendo catálogo...',
        ),
        const _ChatOption(
          label: 'Volver al menú',
          icon: Icons.home_rounded,
          nextNodeKey: 'root',
        ),
      ]);
    } catch (e) {
      if (mounted) {
        _addMessage(
          _ChatSender.bot,
          'No he podido buscar productos. Inténtalo de nuevo.',
        );
      }
    }
  }

  Future<void> _handleFreeText() async {
    final raw = _inputController.text.trim();
    if (raw.isEmpty || _isTyping) return;

    _inputController.clear();
    _addMessage(_ChatSender.user, raw);

    await _simulateTyping(milliseconds: 550);
    if (!mounted) return;

    await _searchProductAndNavigate(raw);
  }

  void _setContextOptions(List<_ChatOption> options) {
    setState(() {
      _contextOptions = [
        ...options,
        const _ChatOption(
          label: 'Volver al menú',
          icon: Icons.home_rounded,
          nextNodeKey: 'root',
        ),
      ];
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isOpen = ref.watch(chatBoxProvider);
    final node = _nodes[_currentNodeKey] ?? _nodes['root']!;
    final visibleOptions = _contextOptions ?? node.options;
    final size = MediaQuery.sizeOf(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    final panelWidth = math.min(size.width - 24, 370.0);
    final panelHeight = math.max(
      330.0,
      math.min(520.0, size.height - bottomInset - 148),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (isOpen)
          Positioned(
            right: 12,
            bottom: 76 + bottomInset,
            width: panelWidth,
            height: panelHeight,
            child: AnimatedScale(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              scale: isOpen ? 1 : 0.96,
              alignment: Alignment.bottomRight,
              child: _buildChatPanel(visibleOptions),
            ),
          ),
        Positioned(
          right: 14,
          bottom: 16,
          child: _buildFloatingButton(isOpen),
        ),
      ],
    );
  }

  Widget _buildChatPanel(List<_ChatOption> visibleOptions) {
    return Material(
      elevation: 18,
      borderRadius: BorderRadius.circular(24),
      shadowColor: Colors.black.withValues(alpha: 0.16),
      child: Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _border, width: 1.1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                itemCount: _messages.length + (_isTyping ? 1 : 0),
                itemBuilder: (_, index) {
                  if (_isTyping && index == _messages.length) {
                    return const _TypingIndicator();
                  }
                  return _buildBubble(_messages[index]);
                },
              ),
            ),
            _buildQuickOptions(visibleOptions),
            _buildInput(),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingButton(bool isOpen) {
    return GestureDetector(
      onTap: _toggleChat,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 230),
        curve: Curves.easeOutCubic,
        width: isOpen ? 46 : 106,
        height: 42,
        padding: EdgeInsets.symmetric(horizontal: isOpen ? 0 : 8),
        decoration: BoxDecoration(
          color: isOpen ? Colors.white : _dark,
          borderRadius: BorderRadius.circular(isOpen ? 23 : 15),
          border: Border.all(
            color: isOpen
                ? _brandRed.withValues(alpha: 0.30)
                : Colors.white.withValues(alpha: 0.10),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: isOpen
              ? const Icon(
            Icons.close_rounded,
            key: ValueKey('close'),
            color: _brandRed,
            size: 22,
          )
              : Row(
            key: const ValueKey('help'),
            children: [
              Container(
                width: 25,
                height: 25,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Image.asset(
                  'assets/images/mundicamlogochatbox.png',
                  width: 18,
                  height: 18,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.support_agent_rounded,
                    color: _brandRedLight,
                    size: 17,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  '¿Dudas?\nTe ayudo',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10.8,
                    height: 1.02,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'Oswald',
                  ),
                ),
              ),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: _onlineGreen,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _onlineGreen.withValues(alpha: 0.50),
                      blurRadius: 5,
                      spreadRadius: 0.8,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_brandRed, _brandRedDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _dark,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Image.asset(
                'assets/images/mundicamlogochatbox.png',
                width: 28,
                height: 28,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.support_agent_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Asistente MundiCam',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    fontFamily: 'Oswald',
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: _onlineGreen,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'Operativo · ayuda rápida profesional',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _resetChat,
            tooltip: 'Reiniciar',
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: _toggleChat,
            tooltip: 'Cerrar',
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(_ChatMessage msg) {
    final isBot = msg.sender == _ChatSender.bot;

    return Align(
      alignment: isBot ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: EdgeInsets.only(
          bottom: 10,
          left: isBot ? 0 : 38,
          right: isBot ? 38 : 0,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        constraints: const BoxConstraints(maxWidth: 285),
        decoration: BoxDecoration(
          color: isBot ? Colors.white : _brandRed,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isBot ? 8 : 20),
            bottomRight: Radius.circular(isBot ? 20 : 8),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
          border: isBot ? Border.all(color: _border, width: 1) : null,
        ),
        child: Text(
          msg.text,
          style: TextStyle(
            color: isBot ? _dark : Colors.white,
            fontSize: 13.4,
            height: 1.42,
            fontWeight: isBot ? FontWeight.w500 : FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildQuickOptions(List<_ChatOption> options) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 134),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map(_buildChip).toList(),
        ),
      ),
    );
  }

  Widget _buildChip(_ChatOption option) {
    return InkWell(
      onTap: _isTyping ? null : () => _handleOption(option),
      borderRadius: BorderRadius.circular(24),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: _isTyping ? 0.55 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _brandRed.withValues(alpha: 0.28)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (option.icon != null) ...[
                Icon(option.icon, size: 16, color: _brandRed),
                const SizedBox(width: 6),
              ],
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 215),
                child: Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _dark,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              focusNode: _inputFocusNode,
              minLines: 1,
              maxLines: 2,
              textInputAction: TextInputAction.send,
              enabled: !_isTyping,
              cursorColor: _brandRed,
              decoration: InputDecoration(
                hintText: 'Escribe aquí tu duda...',
                hintStyle: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 13,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(26),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(26),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(26)),
                  borderSide: BorderSide(color: _brandRed, width: 1.5),
                ),
                filled: true,
                fillColor: _surface,
              ),
              onSubmitted: (_) => _handleFreeText(),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: _isTyping ? Colors.grey.shade300 : _brandRed,
              shape: BoxShape.circle,
              boxShadow: _isTyping
                  ? null
                  : [
                BoxShadow(
                  color: _brandRed.withValues(alpha: 0.25),
                  blurRadius: 9,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: IconButton(
              icon: const Icon(
                Icons.send_rounded,
                color: Colors.white,
                size: 20,
              ),
              onPressed: _isTyping ? null : _handleFreeText,
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================
// MODELOS INTERNOS
// ================================================================

enum _ChatSender { bot, user }

enum _ChatAction {
  openCatalog,
  searchBrand,
  navigateToOrders,
  navigateToQuotes,
  whatsapp,
  phone,
  email,
  web,
}

class _ChatMessage {
  final _ChatSender sender;
  final String text;

  const _ChatMessage({
    required this.sender,
    required this.text,
  });
}

class _ChatNode {
  final String prompt;
  final List<_ChatOption> options;

  const _ChatNode({
    required this.prompt,
    required this.options,
  });
}

class _ChatOption {
  final String label;
  final IconData? icon;
  final String? nextNodeKey;
  final _ChatAction? action;
  final String? successMessage;
  final String? brandName;
  final String? searchQuery;
  final String? whatsappText;
  final String? emailSubject;
  final String? webUrl;
  final bool requiresLogin;

  const _ChatOption({
    required this.label,
    this.icon,
    this.nextNodeKey,
    this.action,
    this.successMessage,
    this.brandName,
    this.searchQuery,
    this.whatsappText,
    this.emailSubject,
    this.webUrl,
    this.requiresLogin = false,
  });
}

class _CategoryDef {
  final String key;
  final String title;
  final IconData icon;
  final String search;
  final String prompt;
  final List<String> brands;

  const _CategoryDef({
    required this.key,
    required this.title,
    required this.icon,
    required this.search,
    required this.prompt,
    required this.brands,
  });
}

class _FaqDef {
  final String key;
  final String title;
  final IconData icon;
  final String answer;
  final List<_ChatOption> options;

  const _FaqDef({
    required this.key,
    required this.title,
    required this.icon,
    required this.answer,
    this.options = const [],
  });
}

// ================================================================
// INDICADOR DE ESCRIBIR
// ================================================================

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.circular(22)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _TypingDot(),
                SizedBox(width: 5),
                _TypingDot(delay: 180),
                SizedBox(width: 5),
                _TypingDot(delay: 360),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TypingDot extends StatefulWidget {
  final int delay;

  const _TypingDot({this.delay = 0});

  @override
  State<_TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<_TypingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    _opacity = Tween<double>(
      begin: 0.25,
      end: 1,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) {
        _controller.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: _ChatBoxState._brandRed.withValues(alpha: 0.55),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
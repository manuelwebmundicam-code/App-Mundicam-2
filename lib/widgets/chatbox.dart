import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../pages/orders_page.dart';
import '../pages/productos_page.dart';
import '../pages/quotes_page.dart';
import '../providers/user_provider.dart';

// ================================================================
// PROVIDERS
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
  // COLORES VERDES
  // ---------------------------------------------------------------

  static const Color _greenPrimary = Color(0xFF2E7D32);
  static const Color _greenLight = Color(0xFF4CAF50);
  static const Color _greenDark = Color(0xFF1B5E20);
  static const Color _greenSurface = Color(0xFFE8F5E9);

  // ---------------------------------------------------------------
  // CONSTANTES DE CONTACTO
  // ---------------------------------------------------------------

  static const String _telefono = '968629383';
  static const String _telefonoFormateado = '968 62 93 83';
  static const String _whatsapp = '34619078632';
  static const String _whatsappFormateado = '619 078 632';
  static const String _email = 'info@mundicam.com';
  static const String _web = 'https://www.mundicam.com';
  static const String _academy = 'https://www.mundicam.com/academy/';

  static const String _welcomeMessage =
      '👋 ¡Hola! Soy el asistente de Mundicam. Puedo ayudarte con '
      'productos, pedidos, presupuestos, RMA, crédito y soporte.';

  // ---------------------------------------------------------------
  // CONTROLADORES Y ESTADO
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

  // ---------------------------------------------------------------
  // MAPAS Y LISTAS DE DATOS
  // ---------------------------------------------------------------

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
          '🎥 Videovigilancia profesional: cámaras, grabadores, accesorios, '
          'discos, PoE y analítica.',
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
          '🚨 Alarmas e intrusión: centrales, detectores, sirenas, teclados, '
          'mandos y accesorios.',
      brands: ['Ajax', 'Ksenia', 'Paradox', 'Satel', 'Honeywell', 'Bosch'],
    ),
    _CategoryDef(
      key: 'acceso',
      title: 'Control de Acceso',
      icon: Icons.lock_rounded,
      search: 'control de acceso lector cerradura biometrico',
      prompt:
          '🔐 Control de acceso: lectores, cerraduras, terminales, '
          'controladoras e identificación.',
      brands: ['ZKTeco', 'Anviz', 'Yale'],
    ),
    _CategoryDef(
      key: 'incendio',
      title: 'Incendio',
      icon: Icons.local_fire_department_rounded,
      search: 'incendio central detector humo pulsador sirena',
      prompt:
          '🔥 Incendio: centrales, detectores, pulsadores, sirenas, módulos '
          'y accesorios.',
      brands: ['Teletek', 'Honeywell', 'Siemens'],
    ),
    _CategoryDef(
      key: 'networking',
      title: 'Networking',
      icon: Icons.hub_rounded,
      search: 'networking switch poe router wifi omada',
      prompt:
          '🌐 Networking: switches PoE, routers, WiFi profesional, '
          'controladores y puntos de acceso.',
      brands: ['TP-Link', 'Omada'],
    ),
    _CategoryDef(
      key: 'iot',
      title: 'IoT / M2M',
      icon: Icons.sim_card_rounded,
      search: 'wisim sim m2m iot multioperador apn',
      prompt:
          '📡 IoT/M2M: conectividad multioperador para CCTV, alarmas, '
          'telemetría, movilidad e industria.',
      brands: ['WISIM'],
    ),
    _CategoryDef(
      key: 'autonoma',
      title: 'Seguridad autónoma',
      icon: Icons.solar_power_rounded,
      search: 'seguridad autonoma solar torre pod evolve xtender',
      prompt:
          '☀️ Seguridad autónoma: torres, POD, energía solar, vídeo, '
          'analítica y conectividad.',
      brands: ['Evolve Xtender'],
    ),
  ];

  final List<_FaqDef> _faqs = const [
    _FaqDef(
      key: 'pedido',
      title: '¿Cómo hago un pedido?',
      icon: Icons.shopping_cart_checkout_rounded,
      answer:
          '🛒 Para hacer un pedido: entra en catálogo, abre un producto, '
          'selecciona cantidad, añádelo al carrito y finaliza desde Checkout.',
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
          '📄 Puedes solicitar presupuesto desde el botón "Presupuesto" del '
          'producto. Si no hay stock, la compra queda bloqueada, pero puedes '
          'pedir valoración comercial.',
      options: [
        _ChatOption(
          label: 'Abrir presupuestos',
          icon: Icons.description_rounded,
          action: _ChatAction.navigateToQuotes,
          successMessage: '📄 Abriendo presupuestos...',
          requiresLogin: true,
        ),
        _ChatOption(
          label: 'Contactar comercial',
          icon: Icons.chat_rounded,
          action: _ChatAction.whatsapp,
          whatsappText:
              'Hola Mundicam, necesito ayuda para preparar un presupuesto.',
        ),
      ],
    ),
    _FaqDef(
      key: 'pedidos',
      title: '¿Dónde veo mis pedidos?',
      icon: Icons.local_shipping_rounded,
      answer:
          '📦 Puedes consultar tus pedidos desde la sección "Pedidos". Verás '
          'estado, fecha, total y productos incluidos.',
      options: [
        _ChatOption(
          label: 'Abrir pedidos',
          icon: Icons.local_shipping_rounded,
          action: _ChatAction.navigateToOrders,
          successMessage: '📦 Abriendo pedidos...',
          requiresLogin: true,
        ),
      ],
    ),
    _FaqDef(
      key: 'rma',
      title: '¿Cómo solicito RMA?',
      icon: Icons.assignment_return_rounded,
      answer:
          '🔧 Para solicitar una RMA, entra en pedidos, localiza un pedido '
          'completado y pulsa el botón RMA del producto correspondiente.',
      options: [
        _ChatOption(
          label: 'Abrir pedidos',
          icon: Icons.local_shipping_rounded,
          action: _ChatAction.navigateToOrders,
          successMessage: '📦 Abriendo pedidos para gestionar RMA...',
          requiresLogin: true,
        ),
        _ChatOption(
          label: 'Contactar soporte',
          icon: Icons.chat_rounded,
          action: _ChatAction.whatsapp,
          whatsappText: 'Hola Mundicam, necesito ayuda para gestionar una RMA.',
        ),
      ],
    ),
    _FaqDef(
      key: 'credito',
      title: 'Crédito disponible',
      icon: Icons.account_balance_wallet_rounded,
      answer:
          '💳 Tu crédito se consulta desde Perfil. La app muestra límite, '
          'crédito usado y crédito disponible.',
      options: [
        _ChatOption(
          label: 'Contactar gestor',
          icon: Icons.support_agent_rounded,
          action: _ChatAction.whatsapp,
          whatsappText:
              'Hola Mundicam, necesito consultar mi crédito disponible.',
        ),
      ],
    ),
    _FaqDef(
      key: 'direccion',
      title: 'Cambiar dirección',
      icon: Icons.location_on_rounded,
      answer:
          '📍 La dirección de envío se puede editar durante el Checkout. '
          'Empresa y CIF/NIF permanecen bloqueados porque vienen de WooCommerce.',
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
          '👤 Tu gestor asignado aparece en Perfil, dentro de los datos '
          'empresariales cargados desde WooCommerce.',
      options: [
        _ChatOption(
          label: 'Contactar gestor',
          icon: Icons.chat_rounded,
          action: _ChatAction.whatsapp,
          whatsappText:
              'Hola Mundicam, necesito contactar con mi gestor asignado.',
        ),
      ],
    ),
    _FaqDef(
      key: 'stock',
      title: 'Stock y disponibilidad',
      icon: Icons.inventory_2_rounded,
      answer:
          '📦 El stock aparece en la tarjeta y en la ficha del producto. Si '
          'no hay stock, la compra se bloquea y puedes solicitar presupuesto.',
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

  // ---------------------------------------------------------------
  // CICLO DE VIDA
  // ---------------------------------------------------------------

  @override
  void dispose() {
    _scrollController.dispose();
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------
  // CONSTRUCCIÓN DEL ÁRBOL DE NODOS
  // ---------------------------------------------------------------

  Map<String, _ChatNode> _buildNodes() {
    final nodes = <String, _ChatNode>{
      // Raíz -------------------------------------------------------
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
            nextNodeKey: 'pedidos',
          ),
          const _ChatOption(
            label: 'Presupuestos',
            icon: Icons.description_rounded,
            nextNodeKey: 'presupuestos',
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

      // Buscar -----------------------------------------------------
      'buscar': _ChatNode(
        prompt:
            '🔎 Escribe una marca, referencia o tipo de producto. Ejemplos: '
            '"Ajax", "Dahua", "NVR", "cámara IP", "switch PoE" o "KSI".',
        options: [
          const _ChatOption(
            label: 'Abrir catálogo',
            icon: Icons.grid_view_rounded,
            action: _ChatAction.openCatalog,
          ),
          const _ChatOption(
            label: 'Hablar con Mundicam',
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

      // Catálogo ---------------------------------------------------
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

      // Pedidos ----------------------------------------------------
      'pedidos': _ChatNode(
        prompt:
            '📦 Consulta pedidos, estados, productos incluidos y gestiones asociadas.',
        options: [
          const _ChatOption(
            label: 'Abrir pedidos',
            icon: Icons.local_shipping_rounded,
            action: _ChatAction.navigateToOrders,
            successMessage: '📦 Abriendo pedidos...',
            requiresLogin: true,
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

      // Presupuestos -----------------------------------------------
      'presupuestos': _ChatNode(
        prompt:
            '📄 Gestiona presupuestos aceptables y solicitudes comerciales.',
        options: [
          const _ChatOption(
            label: 'Abrir presupuestos',
            icon: Icons.description_rounded,
            action: _ChatAction.navigateToQuotes,
            successMessage: '📄 Abriendo presupuestos...',
            requiresLogin: true,
          ),
          _faqOption('presupuesto'),
          const _ChatOption(
            label: 'Pedir ayuda comercial',
            icon: Icons.chat_rounded,
            action: _ChatAction.whatsapp,
            whatsappText:
                'Hola Mundicam, necesito ayuda con un presupuesto profesional.',
          ),
          const _ChatOption(
            label: 'Volver',
            icon: Icons.arrow_back_rounded,
            nextNodeKey: 'root',
          ),
        ],
      ),

      // Soporte ----------------------------------------------------
      'soporte': _ChatNode(
        prompt: '🔧 Soporte técnico, RMA, documentación y garantía.',
        options: [
          _faqOption('rma'),
          const _ChatOption(
            label: 'Consulta técnica',
            icon: Icons.engineering_rounded,
            action: _ChatAction.whatsapp,
            whatsappText:
                'Hola Mundicam, necesito soporte técnico sobre un producto o instalación.',
          ),
          const _ChatOption(
            label: 'Pedir documentación',
            icon: Icons.menu_book_rounded,
            action: _ChatAction.whatsapp,
            whatsappText:
                'Hola Mundicam, necesito documentación técnica de un producto.',
          ),
          const _ChatOption(
            label: 'Garantía',
            icon: Icons.verified_user_rounded,
            action: _ChatAction.whatsapp,
            whatsappText:
                'Hola Mundicam, necesito consultar la garantía de un producto.',
          ),
          const _ChatOption(
            label: 'Volver',
            icon: Icons.arrow_back_rounded,
            nextNodeKey: 'root',
          ),
        ],
      ),

      // Cuenta -----------------------------------------------------
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
                'Hola Mundicam, necesito contactar con mi gestor comercial.',
          ),
          const _ChatOption(
            label: 'Volver',
            icon: Icons.arrow_back_rounded,
            nextNodeKey: 'root',
          ),
        ],
      ),

      // Contacto ---------------------------------------------------
      'contacto': _ChatNode(
        prompt: '📞 Elige cómo quieres contactar con Mundicam:',
        options: [
          const _ChatOption(
            label: 'WhatsApp ($_whatsappFormateado)',
            icon: Icons.chat_rounded,
            action: _ChatAction.whatsapp,
            whatsappText:
                'Hola Mundicam, necesito ayuda desde la app profesional.',
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
            emailSubject: 'Consulta desde App Mundicam',
          ),
          const _ChatOption(
            label: 'Web Mundicam',
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

    // Nodos de categorías -----------------------------------------
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
                'Hola Mundicam, necesito asesoramiento sobre un proyecto profesional.',
          ),
          const _ChatOption(
            label: 'Volver',
            icon: Icons.arrow_back_rounded,
            nextNodeKey: 'catalog',
          ),
        ],
      );
    }

    // Nodos de FAQ ------------------------------------------------
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

  // ---------------------------------------------------------------
  // HELPERS DE CONSTRUCCIÓN DE NODOS
  // ---------------------------------------------------------------

  _ChatOption _faqOption(String key) {
    final faq = _faqs.firstWhere((item) => item.key == key);
    return _ChatOption(
      label: faq.title,
      icon: faq.icon,
      nextNodeKey: 'faq_$key',
    );
  }

  // ---------------------------------------------------------------
  // MANEJO DEL CHAT
  // ---------------------------------------------------------------

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

  // ---------------------------------------------------------------
  // PROCESAMIENTO DE TEXTO
  // ---------------------------------------------------------------

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

  // ---------------------------------------------------------------
  // NAVEGACIÓN POR NODOS Y OPCIONES
  // ---------------------------------------------------------------

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

    if (option.requiresLogin) {
      final user = ref.read(currentUserProvider).value;
      if (user == null) {
        await _simulateTyping(milliseconds: 300);
        _addMessage(
          _ChatSender.bot,
          '⚠️ Necesitas iniciar sesión para acceder a esta sección.',
        );
        return;
      }
    }

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

  // ---------------------------------------------------------------
  // EJECUCIÓN DE ACCIONES
  // ---------------------------------------------------------------

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
          'Te llevo al catálogo para buscar $brand. Si el filtro automático no '
          'se aplica, escribe "$brand" en el buscador del catálogo.',
        );
        _openCatalog(searchQuery: brand, brandName: brand);
        break;

      case _ChatAction.navigateToOrders:
        _navigateTo(const OrdersPage());
        break;

      case _ChatAction.navigateToQuotes:
        _navigateTo(const QuotesPage());
        break;

      case _ChatAction.whatsapp:
        await _openWhatsApp(
          option.whatsappText ??
              'Hola Mundicam, necesito ayuda desde la app profesional.',
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
              'subject': option.emailSubject ?? 'Consulta desde App Mundicam',
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

  void _openCatalog({String? searchQuery, String? brandName}) {
    final args = <String, String>{};
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      args['searchQuery'] = searchQuery.trim();
    }
    if (brandName != null && brandName.trim().isNotEmpty) {
      args['brandName'] = brandName.trim();
    }
    _navigateTo(const ProductosPage(), arguments: args.isEmpty ? null : args);
  }

  void _navigateTo(Widget page, {Object? arguments}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => page,
        settings: RouteSettings(arguments: arguments),
      ),
    );
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
      if (!launched) {
        _addMessage(_ChatSender.bot, '⚠️ $errorMessage');
      }
    } catch (_) {
      _addMessage(_ChatSender.bot, '⚠️ $errorMessage');
    }
  }

  // ---------------------------------------------------------------
  // TEXTO LIBRE DEL USUARIO
  // ---------------------------------------------------------------

  Future<void> _handleFreeText() async {
    final raw = _inputController.text.trim();
    if (raw.isEmpty || _isTyping) return;

    _inputController.clear();
    _addMessage(_ChatSender.user, raw);
    await _simulateTyping(milliseconds: 550);

    if (!mounted) return;

    final normalized = _normalize(raw);

    // Detección de marca
    final brand = _detectBrand(raw);
    if (brand != null) {
      _setContextOptions([
        _ChatOption(
          label: 'Ver $brand',
          icon: Icons.sell_outlined,
          action: _ChatAction.searchBrand,
          brandName: brand,
        ),
        const _ChatOption(
          label: 'Abrir catálogo',
          icon: Icons.grid_view_rounded,
          action: _ChatAction.openCatalog,
        ),
        const _ChatOption(
          label: 'Contactar comercial',
          icon: Icons.chat_rounded,
          action: _ChatAction.whatsapp,
          whatsappText:
              'Hola Mundicam, necesito asesoramiento comercial sobre una marca o producto.',
        ),
      ]);
      _addMessage(
        _ChatSender.bot,
        'He detectado la marca $brand. ¿Quieres ver productos o contactar con Mundicam?',
      );
      return;
    }

    // Detección de referencia
    if (_looksLikeReference(raw)) {
      _setContextOptions([
        _ChatOption(
          label: 'Buscar referencia',
          icon: Icons.search_rounded,
          action: _ChatAction.openCatalog,
          searchQuery: raw,
        ),
        const _ChatOption(
          label: 'Pedir ayuda',
          icon: Icons.chat_rounded,
          action: _ChatAction.whatsapp,
          whatsappText:
              'Hola Mundicam, necesito ayuda para localizar una referencia de producto.',
        ),
      ]);
      _addMessage(
        _ChatSender.bot,
        'Parece una referencia o SKU. Puedo buscarla en catálogo o ayudarte por WhatsApp.',
      );
      return;
    }

    // Detección de categoría
    final category = _detectCategory(normalized);
    if (category != null) {
      _showNode('cat_${category.key}');
      return;
    }

    // Detección de intención (FAQ)
    final intentNode = _detectIntent(normalized);
    if (intentNode != null) {
      _showNode(intentNode);
      return;
    }

    // Saludos
    if (_containsAny(normalized, [
      'hola',
      'buenas',
      'buenos dias',
      'buenas tardes',
    ])) {
      _addMessage(
        _ChatSender.bot,
        '¡Hola! 😊 Puedes escribir una marca, referencia o elegir una opción rápida.',
      );
      return;
    }

    // Agradecimientos
    if (_containsAny(normalized, ['gracias', 'perfecto', 'ok', 'vale'])) {
      _addMessage(_ChatSender.bot, '¡De nada! ¿Te ayudo con algo más?');
      return;
    }

    // Fallback
    _setContextOptions([
      const _ChatOption(
        label: 'Abrir catálogo',
        icon: Icons.grid_view_rounded,
        action: _ChatAction.openCatalog,
      ),
      const _ChatOption(
        label: 'FAQ',
        icon: Icons.help_outline_rounded,
        nextNodeKey: 'faq_pedido',
      ),
      const _ChatOption(
        label: 'Contactar Mundicam',
        icon: Icons.chat_rounded,
        action: _ChatAction.whatsapp,
        whatsappText:
            'Hola Mundicam, necesito ayuda con una consulta desde la app.',
      ),
    ]);
    _addMessage(
      _ChatSender.bot,
      'No he podido identificar exactamente tu consulta. Prueba con una marca, '
      'referencia, "cámaras", "alarmas", "pedido", "RMA" o "presupuesto".',
    );
  }

  // ---------------------------------------------------------------
  // DETECCIÓN DE CATEGORÍAS E INTENCIONES
  // ---------------------------------------------------------------

  _CategoryDef? _detectCategory(String normalized) {
    final checks = <String, List<String>>{
      'video': [
        'camara',
        'camaras',
        'cctv',
        'videovigilancia',
        'nvr',
        'dvr',
        'grabador',
        'ip',
        'poe',
      ],
      'alarmas': [
        'alarma',
        'alarmas',
        'intrusion',
        'detector',
        'sensor',
        'sirena',
        'teclado',
        'central',
      ],
      'acceso': [
        'acceso',
        'cerradura',
        'lector',
        'biometrico',
        'huella',
        'tarjeta',
      ],
      'incendio': ['incendio', 'fuego', 'humo', 'pulsador'],
      'networking': [
        'red',
        'switch',
        'router',
        'wifi',
        'wi-fi',
        'networking',
        'omada',
        'punto de acceso',
      ],
      'iot': [
        'sim',
        'm2m',
        'iot',
        'datos',
        'multioperador',
        'apn',
        'conectividad',
        'wisim',
      ],
      'autonoma': [
        'solar',
        'autonoma',
        'torre',
        'pod',
        'obra',
        'evento',
        'evolve',
        'xtender',
      ],
    };

    for (final entry in checks.entries) {
      if (_containsAny(normalized, entry.value)) {
        return _categories.firstWhere((category) => category.key == entry.key);
      }
    }
    return null;
  }

  String? _detectIntent(String normalized) {
    final checks = <String, List<String>>{
      'faq_stock': ['stock', 'disponible', 'existencias', 'sin stock'],
      'faq_presupuesto': [
        'presupuesto',
        'presupuestos',
        'cotizacion',
        'oferta',
      ],
      'faq_pedidos': [
        'pedido',
        'pedidos',
        'estado',
        'seguimiento',
        'donde esta',
        'cuando llega',
      ],
      'faq_rma': ['rma', 'garantia', 'averia', 'reparacion', 'devolucion'],
      'faq_credito': ['credito', 'limite', 'forma de pago', 'pago'],
      'faq_gestor': ['gestor', 'comercial', 'asesor'],
      'faq_direccion': ['direccion', 'envio', 'entrega', 'checkout'],
      'contacto': [
        'contacto',
        'telefono',
        'whatsapp',
        'email',
        'correo',
        'hablar',
        'soporte',
      ],
    };

    for (final entry in checks.entries) {
      if (_containsAny(normalized, entry.value)) {
        return entry.key;
      }
    }
    return null;
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

  // ---------------------------------------------------------------
  // SCROLL
  // ---------------------------------------------------------------

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

  // ---------------------------------------------------------------
  // BUILD PRINCIPAL
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isOpen = ref.watch(chatBoxProvider);
    final node = _nodes[_currentNodeKey] ?? _nodes['root']!;
    final visibleOptions = _contextOptions ?? node.options;
    final size = MediaQuery.sizeOf(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    final panelWidth = math.min(size.width - 24, 360.0);
    final panelHeight = math.max(
      320.0,
      math.min(520.0, size.height - bottomInset - 138),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Panel del chat ------------------------------------------
        if (isOpen)
          Positioned(
            right: 12,
            bottom: 92 + bottomInset,
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

        // Botón flotante ------------------------------------------
        Positioned(right: 16, bottom: 18, child: _buildFloatingButton(isOpen)),
      ],
    );
  }

  // ---------------------------------------------------------------
  // PANEL DEL CHAT
  // ---------------------------------------------------------------

  Widget _buildChatPanel(List<_ChatOption> visibleOptions) {
    return Material(
      elevation: 20,
      borderRadius: BorderRadius.circular(28),
      shadowColor: _greenDark.withOpacity(0.3),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FB),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _greenLight.withOpacity(0.3), width: 1.2),
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

  // ---------------------------------------------------------------
  // BOTÓN FLOTANTE
  // ---------------------------------------------------------------

  Widget _buildFloatingButton(bool isOpen) {
    return GestureDetector(
      onTap: _toggleChat,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        width: isOpen ? 60 : 154,
        height: 60,
        padding: EdgeInsets.only(left: isOpen ? 0 : 12, right: isOpen ? 0 : 14),
        decoration: BoxDecoration(
          gradient: isOpen
              ? null
              : const LinearGradient(
                  colors: [_greenPrimary, _greenLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          color: isOpen ? Colors.white : null,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isOpen
                ? _greenPrimary.withOpacity(0.3)
                : Colors.white.withOpacity(0.2),
            width: isOpen ? 1.5 : 2,
          ),
          boxShadow: [
            BoxShadow(
              color: _greenPrimary.withOpacity(isOpen ? 0.2 : 0.45),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: isOpen
              ? Center(
                  key: const ValueKey('close'),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _greenSurface,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: _greenPrimary,
                      size: 24,
                    ),
                  ),
                )
              : Row(
                  key: const ValueKey('help'),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: Image.asset(
                        'assets/images/mundicamlogochatbox.png',
                        width: 20,
                        height: 20,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(width: 9),
                    const Expanded(
                      child: Text(
                        '¿Dudas?\nTe ayudo',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          height: 1.05,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.greenAccent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.greenAccent.withOpacity(0.6),
                            blurRadius: 6,
                            spreadRadius: 1,
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

  // ---------------------------------------------------------------
  // HEADER DEL CHAT
  // ---------------------------------------------------------------

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_greenPrimary, _greenLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.all(3),
            child: CircleAvatar(
              backgroundColor: Colors.white24,
              radius: 18,
              child: Image.asset(
                'assets/images/mundicamlogochatbox.png',
                width: 22,
                height: 22,
              ),
            ),
          ),
          const SizedBox(width: 11),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Asistente Mundicam',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    fontFamily: 'Oswald',
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Ayuda rápida para profesionales',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.refresh_rounded,
              color: Colors.white,
              size: 20,
            ),
            onPressed: _resetChat,
            tooltip: 'Reiniciar',
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(
              Icons.close_rounded,
              color: Colors.white,
              size: 20,
            ),
            onPressed: _toggleChat,
            tooltip: 'Cerrar',
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // BURBUJA DE MENSAJE
  // ---------------------------------------------------------------

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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          gradient: isBot
              ? null
              : const LinearGradient(
                  colors: [_greenPrimary, _greenLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          color: isBot ? Colors.white : null,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(22),
            topRight: const Radius.circular(22),
            bottomLeft: Radius.circular(isBot ? 8 : 22),
            bottomRight: Radius.circular(isBot ? 22 : 8),
          ),
          boxShadow: [
            BoxShadow(
              color: (isBot ? Colors.black : _greenPrimary).withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: isBot
              ? Border.all(color: _greenLight.withOpacity(0.15), width: 1)
              : null,
        ),
        child: Text(
          msg.text,
          style: TextStyle(
            color: isBot ? const Color(0xFF111827) : Colors.white,
            fontSize: 13.4,
            height: 1.42,
            fontWeight: isBot ? FontWeight.w500 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------
  // OPCIONES RÁPIDAS
  // ---------------------------------------------------------------

  Widget _buildQuickOptions(List<_ChatOption> options) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 134),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _greenLight.withOpacity(0.2))),
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _greenPrimary.withOpacity(0.5)),
            boxShadow: [
              BoxShadow(
                color: _greenPrimary.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (option.icon != null) ...[
                Icon(option.icon, size: 16, color: _greenPrimary),
                const SizedBox(width: 6),
              ],
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 215),
                child: Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _greenPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------
  // INPUT DE TEXTO
  // ---------------------------------------------------------------

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
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
              cursorColor: _greenPrimary,
              decoration: InputDecoration(
                hintText: 'Escribe aquí tu duda...',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
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
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(26),
                  borderSide: const BorderSide(
                    color: _greenPrimary,
                    width: 1.5,
                  ),
                ),
                filled: true,
                fillColor: const Color(0xFFF8F9FB),
              ),
              onSubmitted: (_) => _handleFreeText(),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              gradient: _isTyping
                  ? null
                  : const LinearGradient(
                      colors: [_greenPrimary, _greenLight],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              color: _isTyping ? Colors.grey.shade300 : null,
              shape: BoxShape.circle,
              boxShadow: _isTyping
                  ? null
                  : [
                      BoxShadow(
                        color: _greenPrimary.withOpacity(0.35),
                        blurRadius: 10,
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

  const _ChatMessage({required this.sender, required this.text});
}

class _ChatNode {
  final String prompt;
  final List<_ChatOption> options;

  const _ChatNode({required this.prompt, required this.options});
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
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
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
          color: _ChatBoxState._greenPrimary.withOpacity(0.55),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

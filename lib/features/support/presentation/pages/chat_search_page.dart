import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:mundicam/features/catalog/data/models/producto.dart';
import 'package:mundicam/features/catalog/presentation/pages/producto_detalles_page.dart';
import 'package:mundicam/features/catalog/presentation/providers/products_provider.dart';
import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/shared/widgets/professional_page_app_bar.dart';

// ================================================================
// CONFIGURACIÓN CONTACTO MUNDICAM
// Cambia estos valores aquí, sin tocar el resto de la pantalla.
// ================================================================

const String mundicamSupportPhone = '968629383';
const String mundicamSupportPhoneLabel = '968 62 93 83';
const String mundicamWhatsappPhone = '34619078632';
const String mundicamWhatsappPhoneLabel = '619 078 632';
const String mundicamSupportEmail = 'info@mundicam.com';
const String mundicamWebsiteUrl = 'https://www.mundicam.com';

// ================================================================
// PROVIDER DE ESTADO DEL CHAT
// Usa Riverpod, igual que el resto de la app. El buscador de productos usa
// el SearchProvider EXISTENTE: searchProductsProvider(query).
// ================================================================

final chatSearchControllerProvider =
    StateNotifierProvider<ChatSearchController, ChatSearchState>((ref) {
  return ChatSearchController();
});

class ChatSearchController extends StateNotifier<ChatSearchState> {
  ChatSearchController()
      : super(
          ChatSearchState(
            messages: const <ChatSearchMessage>[
              ChatSearchMessage(
                fromBot: true,
                text:
                    'Hola. Soy el asistente de MundiCam. Escribe una referencia, SKU, marca o producto y te ayudo a encontrarlo.',
              ),
            ],
          ),
        );

  void reset() {
    state = ChatSearchState(
      messages: const <ChatSearchMessage>[
        ChatSearchMessage(
          fromBot: true,
          text:
              'Hola. Soy el asistente de MundiCam. Escribe una referencia, SKU, marca o producto y te ayudo a encontrarlo.',
        ),
      ],
    );
  }


  void clearSearchOnly() {
    state = state.copyWith(lastSearchQuery: '');
  }

  void ask(String rawText) {
    final text = rawText.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) return;

    final messages = <ChatSearchMessage>[
      ...state.messages,
      ChatSearchMessage(fromBot: false, text: text),
    ];

    final lower = _normalize(text);
    final answer = _answerForText(lower, text);
    final shouldSearch = _shouldSearchProduct(lower);

    state = state.copyWith(
      messages: <ChatSearchMessage>[
        ...messages,
        ChatSearchMessage(fromBot: true, text: answer),
      ],
      // Si el usuario pregunta por pedidos, crédito, contacto, etc., limpiamos
      // la búsqueda anterior para que no se queden productos viejos en pantalla.
      lastSearchQuery: shouldSearch ? text : '',
    );
  }

  void searchDirect(String query) {
    final clean = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) return;

    state = state.copyWith(
      messages: <ChatSearchMessage>[
        ...state.messages,
        ChatSearchMessage(fromBot: false, text: clean),
        ChatSearchMessage(
          fromBot: true,
          text: 'Buscando "$clean" en el catálogo profesional...',
        ),
      ],
      lastSearchQuery: clean,
    );
  }

  String _answerForText(String lower, String original) {
    if (_containsAny(lower, const <String>[
      'telefono',
      'teléfono',
      'llamar',
      'whatsapp',
      'contacto',
      'comercial',
      'gestor',
    ])) {
      return 'Puedes llamar a MundiCam o abrir WhatsApp desde los botones grandes de contacto.';
    }

    if (_containsAny(lower, const <String>[
      'pedido',
      'pedidos',
      'seguimiento',
      'estado',
      'envio',
      'envío',
      'transporte',
    ])) {
      return 'Para ver el estado de tu pedido, entra en la sección Pedidos de la app. Si no lo encuentras, escribe el número de pedido o contacta con MundiCam por WhatsApp.';
    }

    if (_containsAny(lower, const <String>[
      'credito',
      'crédito',
      'giro',
      'aplazado',
      'pago aplazado',
    ])) {
      return 'El pago aplazado depende del límite de crédito asignado en tu ficha de cliente. Si no aparece disponible, contacta con tu gestor.';
    }

    if (_containsAny(lower, const <String>[
      'rma',
      'garantia',
      'garantía',
      'averia',
      'avería',
      'devolucion',
      'devolución',
    ])) {
      return 'Para RMA o garantías, indícanos el pedido, producto y número de serie. También puedes contactar con soporte por WhatsApp.';
    }

    return 'Voy a buscar "$original" en el catálogo. Puedes usar SKU, marca, modelo o descripción del producto.';
  }

  bool _shouldSearchProduct(String lower) {
    if (lower.length < 2) return false;

    if (_containsAny(lower, const <String>[
      'telefono',
      'teléfono',
      'llamar',
      'whatsapp',
      'contacto',
      'credito',
      'crédito',
      'giro',
      'aplazado',
      'pedido',
      'pedidos',
      'rma',
      'garantia',
      'garantía',
    ])) {
      return false;
    }

    return true;
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
        .replaceAll('ñ', 'n');
  }
}

class ChatSearchState {
  final List<ChatSearchMessage> messages;
  final String lastSearchQuery;

  const ChatSearchState({
    required this.messages,
    this.lastSearchQuery = '',
  });

  ChatSearchState copyWith({
    List<ChatSearchMessage>? messages,
    String? lastSearchQuery,
  }) {
    return ChatSearchState(
      messages: messages ?? this.messages,
      lastSearchQuery: lastSearchQuery ?? this.lastSearchQuery,
    );
  }
}

class ChatSearchMessage {
  final bool fromBot;
  final String text;

  const ChatSearchMessage({
    required this.fromBot,
    required this.text,
  });
}

// ================================================================
// PANTALLA CHAT + BUSCADOR
// ================================================================

class ChatSearchPage extends ConsumerStatefulWidget {
  final VoidCallback? onGoCart;
  final VoidCallback? onGoQuotes;

  const ChatSearchPage({
    super.key,
    this.onGoCart,
    this.onGoQuotes,
  });

  @override
  ConsumerState<ChatSearchPage> createState() => _ChatSearchPageState();
}

class _ChatSearchPageState extends ConsumerState<ChatSearchPage> {
  static const Color _red = AppColors.primary;
  static const Color _dark = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _softBg = Color(0xFFF5F6F8);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _whatsappGreen = Color(0xFF128C4A);

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    ref.read(chatSearchControllerProvider.notifier).ask(text);
    _scrollToBottom();
  }

  void _quickSearch(String query) {
    _controller.clear();
    FocusScope.of(context).unfocus();
    ref.read(chatSearchControllerProvider.notifier).searchDirect(query);
    _scrollToBottom();
  }

  void _askQuick(String text) {
    _controller.clear();
    FocusScope.of(context).unfocus();
    ref.read(chatSearchControllerProvider.notifier).ask(text);
    _scrollToBottom();
  }

  void _clearChat() {
    _controller.clear();
    FocusScope.of(context).unfocus();
    ref.read(chatSearchControllerProvider.notifier).reset();
  }

  void _closeAndReset() {
    _clearChat();
    Navigator.of(context).pop();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _callPhone() async {
    await _launch(Uri.parse('tel:$mundicamSupportPhone'));
  }

  Future<void> _openWhatsApp() async {
    await _launch(
      Uri.https(
        'wa.me',
        '/$mundicamWhatsappPhone',
        <String, String>{
          'text': 'Hola MundiCam, necesito ayuda desde la app profesional.',
        },
      ),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _sendEmail() async {
    await _launch(
      Uri(
        scheme: 'mailto',
        path: mundicamSupportEmail,
        queryParameters: const <String, String>{
          'subject': 'Consulta desde App MundiCam',
        },
      ),
    );
  }

  Future<void> _launch(
    Uri uri, {
    LaunchMode mode = LaunchMode.platformDefault,
  }) async {
    try {
      final launched = await launchUrl(uri, mode: mode);
      if (!launched && mounted) {
        _showSnack('No se pudo abrir la aplicación solicitada.');
      }
    } catch (_) {
      if (mounted) {
        _showSnack('No se pudo abrir la aplicación solicitada.');
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatSearchControllerProvider);
    final query = state.lastSearchQuery.trim();
    final AsyncValue<List<Product>> results = query.isEmpty
        ? const AsyncData<List<Product>>(<Product>[])
        : ref.watch(searchProductsProvider(query));

    return WillPopScope(
      onWillPop: () async {
        _clearChat();
        return true;
      },
      child: Scaffold(
        backgroundColor: _softBg,
        appBar: ProfessionalPageAppBar(
          title: 'AYUDA Y BUSCADOR',
          subtitle: 'Chat rápido + búsqueda de productos',
          icon: Icons.support_agent_rounded,
          onBack: _closeAndReset,
        ),
        body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            _buildContactPanel(),
            Expanded(
              child: ListView(
                controller: _scrollController,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                children: <Widget>[
                  _buildQuickActions(),
                  const SizedBox(height: 14),
                  ...state.messages.map(_buildMessage),
                  if (query.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 14),
                    _buildResultsTitle(query),
                    const SizedBox(height: 10),
                    _buildSearchResults(results),
                  ],
                ],
              ),
            ),
            _buildInput(),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildContactPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _BigContactButton(
              label: 'WhatsApp',
              subtitle: mundicamWhatsappPhoneLabel,
              icon: Icons.chat_rounded,
              color: _whatsappGreen,
              onTap: _openWhatsApp,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _BigContactButton(
              label: 'Llamar',
              subtitle: mundicamSupportPhoneLabel,
              icon: Icons.call_rounded,
              color: _dark,
              onTap: _callPhone,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _BigContactButton(
              label: 'Email',
              subtitle: 'Enviar',
              icon: Icons.email_rounded,
              color: _red,
              onTap: _sendEmail,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Búsquedas rápidas',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: _dark,
              fontFamily: 'Oswald',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _QuickButton(label: 'Cámara IP', onTap: () => _quickSearch('camara ip')),
              _QuickButton(label: 'Dahua', onTap: () => _quickSearch('dahua')),
              _QuickButton(label: 'Hikvision', onTap: () => _quickSearch('hikvision')),
              _QuickButton(label: 'NVR', onTap: () => _quickSearch('nvr')),
              _QuickButton(label: 'Switch PoE', onTap: () => _quickSearch('switch poe')),
              _QuickButton(label: 'Ajax', onTap: () => _quickSearch('ajax')),
              _QuickButton(label: '¿Dónde está mi pedido?', onTap: () => _askQuick('Dónde está mi pedido')),
              _QuickButton(label: 'Pago aplazado', onTap: () => _askQuick('Pago aplazado')),
              _QuickButton(label: 'Limpiar chat', onTap: _clearChat),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(ChatSearchMessage message) {
    final isBot = message.fromBot;
    return Align(
      alignment: isBot ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: EdgeInsets.only(
          top: 8,
          bottom: 8,
          left: isBot ? 0 : 34,
          right: isBot ? 34 : 0,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isBot ? Colors.white : _red,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(22),
            topRight: const Radius.circular(22),
            bottomLeft: Radius.circular(isBot ? 6 : 22),
            bottomRight: Radius.circular(isBot ? 22 : 6),
          ),
          border: isBot ? Border.all(color: _border) : null,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 9,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          message.text,
          style: TextStyle(
            fontSize: 16,
            height: 1.35,
            fontWeight: FontWeight.w700,
            color: isBot ? _dark : Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildResultsTitle(String query) {
    return Row(
      children: <Widget>[
        const Icon(Icons.search_rounded, color: _red, size: 26),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Resultados para "$query"',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: _dark,
              fontFamily: 'Oswald',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResults(AsyncValue<List<Product>> results) {
    return results.when(
      loading: () => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _border),
        ),
        child: const Row(
          children: <Widget>[
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(color: _red, strokeWidth: 3),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                'Buscando productos...',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
      error: (Object error, StackTrace stackTrace) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.red.shade100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'No se pudo completar la búsqueda.',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: _dark,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  final query = ref.read(chatSearchControllerProvider).lastSearchQuery;
                  ref.invalidate(searchProductsProvider(query));
                },
                icon: const Icon(Icons.refresh_rounded, size: 24),
                label: const Text(
                  'Reintentar búsqueda',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      data: (List<Product> products) {
        if (products.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'No he encontrado productos.',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: _dark,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Prueba con el SKU, la marca o una palabra más corta. También puedes contactar con MundiCam.',
                  style: TextStyle(fontSize: 16, height: 1.35, color: _muted),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _openWhatsApp,
                    icon: const Icon(Icons.chat_rounded, size: 24),
                    label: const Text(
                      'Pedir ayuda por WhatsApp',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _whatsappGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          children: products
              .take(12)
              .map((Product product) => _ProductSearchCard(
                    product: product,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ProductDetailScreen(
                            product: product,
                            onGoCart: widget.onGoCart,
                            onGoQuotes: widget.onGoQuotes,
                          ),
                        ),
                      );
                    },
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: _border)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              minLines: 1,
              maxLines: 2,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: 'Buscar producto o escribir duda...',
                hintStyle: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w600,
                ),
                filled: true,
                fillColor: _softBg,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                  borderSide: BorderSide(color: _red, width: 2),
                ),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 58,
            width: 58,
            child: ElevatedButton(
              onPressed: _send,
              style: ElevatedButton.styleFrom(
                backgroundColor: _red,
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(19),
                ),
              ),
              child: const Icon(Icons.send_rounded, size: 28),
            ),
          ),
        ],
      ),
    );
  }
}

class _BigContactButton extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _BigContactButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, color: Colors.white, size: 25),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF9FAFB),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductSearchCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const _ProductSearchCard({
    required this.product,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final stockText = product.hasStock ? 'En stock' : 'Sin stock';
    final stockColor = product.hasStock ? const Color(0xFF128C4A) : const Color(0xFFB91C1C);
    final priceText = product.hasValidPrice ? '${product.price} €' : 'Consultar precio';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(0.045),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: CachedNetworkImage(
                    imageUrl: product.imageUrl,
                    width: 86,
                    height: 86,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => Container(
                      width: 86,
                      height: 86,
                      color: const Color(0xFFF3F4F6),
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      width: 86,
                      height: 86,
                      color: const Color(0xFFF3F4F6),
                      child: const Icon(Icons.image_not_supported_outlined, size: 34),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        product.name,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          height: 1.18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF111827),
                        ),
                      ),
                      if (product.sku.trim().isNotEmpty) ...<Widget>[
                        const SizedBox(height: 7),
                        Text(
                          'SKU: ${product.sku}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              priceText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(
                              color: stockColor.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: stockColor.withOpacity(0.25)),
                            ),
                            child: Text(
                              stockText,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: stockColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: onTap,
                          icon: const Icon(Icons.visibility_rounded, size: 22),
                          label: const Text(
                            'Ver producto',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF111827),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// pages/quotes_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/network/api_service.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/professional_page_app_bar.dart';
import '../../../../shared/providers/badge_provider.dart';
import '../../../cart/presentation/providers/cart_provider.dart';
import '../../data/models/quote_model.dart';
import '../../data/models/local_quote_model.dart';
import '../providers/quote_provider.dart';
import '../providers/local_quote_provider.dart';

class QuotesPage extends ConsumerStatefulWidget {
  final VoidCallback? onGoHome;
  final VoidCallback? onGoCart;
  final Set<String> confirmedQuoteIds;
  final Future<void> Function(Set<String> quoteIds)? onQuotesConfirmed;

  const QuotesPage({
    super.key,
    this.onGoHome,
    this.onGoCart,
    this.confirmedQuoteIds = const <String>{},
    this.onQuotesConfirmed,
  });

  @override
  ConsumerState<QuotesPage> createState() => _QuotesPageState();
}

class _QuotesPageState extends ConsumerState<QuotesPage> {
  static const String _confirmedQuoteIdsKey = 'mundicam_confirmed_quote_ids';

  bool _isLoadingAction = false;
  String? _processingQuoteId;

  final Set<String> _hiddenQuoteIds = <String>{};
  final Set<String> _expandedQuoteIds = <String>{};
  final Set<String> _expandedLocalQuoteIds = <String>{};

  final Map<String, List<_QuoteLineItem>> _webItemsCache =
  <String, List<_QuoteLineItem>>{};

  final Map<String, Future<List<_QuoteLineItem>>> _webItemsFutures =
  <String, Future<List<_QuoteLineItem>>>{};

  @override
  void initState() {
    super.initState();
    _hiddenQuoteIds.addAll(widget.confirmedQuoteIds);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _loadPersistedData();
      ref.invalidate(quotesProvider);
      ref.invalidate(quoteBadgeProvider);
      ref.invalidate(cartBadgeProvider);
    });
  }

  Future<void> _loadPersistedData() async {
    final prefs = await SharedPreferences.getInstance();
    final hiddenIds = prefs.getStringList(_confirmedQuoteIdsKey) ?? <String>[];
    if (!mounted) return;
    setState(() {
      _hiddenQuoteIds.addAll(widget.confirmedQuoteIds);
      _hiddenQuoteIds.addAll(hiddenIds);
    });
  }

  Future<void> _refreshQuotes() async {
    if (!mounted) return;
    setState(() {
      _webItemsCache.clear();
      _webItemsFutures.clear();
      _expandedQuoteIds.clear();
      _expandedLocalQuoteIds.clear();
    });
    await _loadPersistedData();
    ref.invalidate(quotesProvider);
    ref.invalidate(quoteBadgeProvider);
    ref.invalidate(cartBadgeProvider);
  }

  Future<void> _saveHiddenIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_confirmedQuoteIdsKey, _hiddenQuoteIds.toList());
  }

  Future<void> _hideWebQuote(String quoteId) async {
    _hiddenQuoteIds.add(quoteId);
    await _saveHiddenIds();
    await widget.onQuotesConfirmed?.call(<String>{quoteId});
    if (!mounted) return;
    setState(() {
      _webItemsCache[quoteId] = <_QuoteLineItem>[];
      _webItemsFutures.remove(quoteId);
      _expandedQuoteIds.remove(quoteId);
    });
    ref.invalidate(quotesProvider);
    ref.invalidate(quoteBadgeProvider);
    ref.invalidate(cartBadgeProvider);
  }

  String _extractOrderId(QuoteMundicam quote) {
    final orderId = quote.id.replaceAll(RegExp(r'[^0-9]'), '');
    if (orderId.isEmpty) throw Exception('No se pudo identificar el ID del presupuesto.');
    return orderId;
  }

  Future<List<_QuoteLineItem>> _loadWebQuoteItems(QuoteMundicam quote, {bool forceRefresh = false}) {
    if (!forceRefresh && _webItemsCache.containsKey(quote.id)) return Future.value(_webItemsCache[quote.id]!);
    if (!forceRefresh && _webItemsFutures.containsKey(quote.id)) return _webItemsFutures[quote.id]!;
    final future = _fetchWebQuoteItems(quote);
    _webItemsFutures[quote.id] = future;
    return future;
  }

  Future<List<_QuoteLineItem>> _fetchWebQuoteItems(QuoteMundicam quote) async {
    try {
      final api = ApiService();
      final orderId = _extractOrderId(quote);
      final orden = await api.getOrdenCompleta(orderId);
      if (orden == null || orden['line_items'] == null) return <_QuoteLineItem>[];
      final rawItems = orden['line_items'];
      final lineItems = rawItems is List ? rawItems : <dynamic>[];
      final items = lineItems
          .map((item) => _QuoteLineItem.fromWooLineItem(item))
          .where((item) => item.name.trim().isNotEmpty)
          .toList();
      _webItemsCache[quote.id] = items;
      return items;
    } finally {
      _webItemsFutures.remove(quote.id);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ACCIONES
  // ═══════════════════════════════════════════════════════════════

  Future<void> _aceptarPresupuesto(QuoteMundicam quote) async {
    if (_isLoadingAction) return;
    final confirmar = await _showConfirmDialog(
      title: 'Aceptar presupuesto',
      icon: Icons.check_circle_rounded,
      iconColor: Colors.green,
      content: 'Se moverán todos los productos al carrito para proceder al pago.\n\n'
          'Presupuesto: #${quote.id}\nTotal: ${_formatMoney(quote.total)}',
      confirmText: 'ACEPTAR Y PAGAR',
      confirmColor: const Color(0xFF2E7D32),
    );
    if (confirmar != true || !mounted) return;
    setState(() { _isLoadingAction = true; _processingQuoteId = 'accept_${quote.id}'; });
    try {
      final api = ApiService();
      final orderId = _extractOrderId(quote);
      final items = await _loadWebQuoteItems(quote, forceRefresh: true);
      int productosAnadidos = 0;
      for (final item in items) {
        if (item.productId <= 0) continue;
        final producto = await api.getProductoById(item.productId);
        if (producto == null) continue;
        ref.read(cartProvider.notifier).addProduct(producto, item.quantity);
        productosAnadidos++;
        await api.eliminarProductoPresupuesto(orderId: orderId, productId: item.productId);
      }
      await _hideWebQuote(quote.id);
      if (!mounted) return;
      _showSnackBar('✅ $productosAnadidos producto${productosAnadidos != 1 ? 's' : ''} añadido${productosAnadidos != 1 ? 's' : ''} al carrito.', Colors.green.shade700);
      await Future.delayed(const Duration(milliseconds: 350));
      if (mounted && widget.onGoCart != null) widget.onGoCart!();
    } catch (e) {
      _showSnackBar('Error: $e', Colors.red);
    } finally {
      if (mounted) setState(() { _isLoadingAction = false; _processingQuoteId = null; });
    }
  }

  Future<void> _guardarPresupuesto(QuoteMundicam quote) async {
    if (_isLoadingAction) return;
    final confirmar = await _showConfirmDialog(
      title: 'Guardar presupuesto',
      icon: Icons.save_alt_rounded,
      iconColor: Colors.blue,
      content: 'Se preparará un email para pedidos@mundicam.com.\n\n'
          'Presupuesto: #${quote.id}\nTotal: ${_formatMoney(quote.total)}\n\n'
          'Después de guardarlo se quitará de pendientes.',
      confirmText: 'GUARDAR Y ENVIAR',
      confirmColor: const Color(0xFF1565C0),
    );
    if (confirmar != true || !mounted) return;
    setState(() { _isLoadingAction = true; _processingQuoteId = 'save_${quote.id}'; });
    try {
      final items = await _loadWebQuoteItems(quote, forceRefresh: true);
      if (items.isEmpty) throw Exception('Este presupuesto no tiene productos.');
      final cuerpo = _buildEmailBody(quote.id, items, quote.total);
      final mailtoUri = Uri(scheme: 'mailto', path: 'pedidos@mundicam.com', queryParameters: {
        'subject': 'Presupuesto #${quote.id} - ${_formatMoney(quote.total)}',
        'body': cuerpo,
      });
      if (!await canLaunchUrl(mailtoUri)) throw Exception('No se pudo abrir el cliente de correo.');
      await launchUrl(mailtoUri, mode: LaunchMode.externalApplication);
      await _hideWebQuote(quote.id);
      _showSnackBar('📧 Presupuesto #${quote.id} enviado por email.', const Color(0xFF1565C0));
    } catch (e) {
      _showSnackBar('Error: $e', Colors.red);
    } finally {
      if (mounted) setState(() { _isLoadingAction = false; _processingQuoteId = null; });
    }
  }

  Future<void> _eliminarPresupuesto(QuoteMundicam quote) async {
    if (_isLoadingAction) return;
    final confirmar = await _showConfirmDialog(
      title: 'Eliminar presupuesto',
      icon: Icons.delete_forever_rounded,
      iconColor: Colors.red,
      content: '¿Eliminar permanentemente el presupuesto #${quote.id}?',
      confirmText: 'ELIMINAR',
      confirmColor: Colors.red,
      isDestructive: true,
    );
    if (confirmar != true || !mounted) return;
    setState(() { _isLoadingAction = true; _processingQuoteId = 'delete_${quote.id}'; });
    try {
      final api = ApiService();
      final orderId = _extractOrderId(quote);
      final items = await _loadWebQuoteItems(quote, forceRefresh: true);
      for (final item in items) {
        if (item.productId <= 0) continue;
        await api.eliminarProductoPresupuesto(orderId: orderId, productId: item.productId);
      }
      await _hideWebQuote(quote.id);
      _showSnackBar('🗑️ Presupuesto eliminado.', Colors.grey.shade700);
    } catch (e) {
      _showSnackBar('Error: $e', Colors.red);
    } finally {
      if (mounted) setState(() { _isLoadingAction = false; _processingQuoteId = null; });
    }
  }

  Future<void> _aceptarLocalYIrAlCarrito(LocalQuote localQuote) async {
    if (_isLoadingAction) return;
    final confirmar = await _showConfirmDialog(
      title: 'Aceptar presupuesto',
      icon: Icons.check_circle_rounded,
      iconColor: Colors.green,
      content: 'Se moverán todos los productos al carrito.\n\n"${localQuote.nombre}"\n${localQuote.items.length} productos\nTotal: ${_formatMoney(localQuote.total)}',
      confirmText: 'ACEPTAR Y PAGAR',
      confirmColor: const Color(0xFF2E7D32),
    );
    if (confirmar != true || !mounted) return;
    setState(() { _isLoadingAction = true; _processingQuoteId = 'local_accept_${localQuote.orderId}'; });
    try {
      final api = ApiService();
      for (final item in localQuote.items) {
        final producto = await api.getProductoById(item.productId);
        if (producto != null) ref.read(cartProvider.notifier).addProduct(producto, item.quantity);
      }
      await ref.read(localQuotesProvider.notifier).eliminarPresupuesto(localQuote.orderId);
      ref.invalidate(cartBadgeProvider);
      ref.invalidate(quoteBadgeProvider);
      if (!mounted) return;
      _showSnackBar('✅ "${localQuote.nombre}" añadido al carrito.', Colors.green.shade700);
      await Future.delayed(const Duration(milliseconds: 350));
      if (mounted && widget.onGoCart != null) widget.onGoCart!();
    } catch (e) {
      _showSnackBar('Error: $e', Colors.red);
    } finally {
      if (mounted) setState(() { _isLoadingAction = false; _processingQuoteId = null; });
    }
  }

  Future<void> _guardarLocalPresupuesto(LocalQuote localQuote) async {
    if (_isLoadingAction) return;
    final confirmar = await _showConfirmDialog(
      title: 'Guardar presupuesto',
      icon: Icons.save_alt_rounded,
      iconColor: Colors.blue,
      content: 'Se preparará un email para pedidos@mundicam.com.\n\n"${localQuote.nombre}"\n${localQuote.items.length} productos\nTotal: ${_formatMoney(localQuote.total)}',
      confirmText: 'GUARDAR Y ENVIAR',
      confirmColor: const Color(0xFF1565C0),
    );
    if (confirmar != true || !mounted) return;
    setState(() { _isLoadingAction = true; _processingQuoteId = 'local_save_${localQuote.orderId}'; });
    try {
      final cuerpo = _buildLocalEmailBody(localQuote);
      final mailtoUri = Uri(scheme: 'mailto', path: 'pedidos@mundicam.com', queryParameters: {
        'subject': '${localQuote.nombre} - ${_formatMoney(localQuote.total)}',
        'body': cuerpo,
      });
      if (!await canLaunchUrl(mailtoUri)) throw Exception('No se pudo abrir el cliente de correo.');
      await launchUrl(mailtoUri, mode: LaunchMode.externalApplication);
      await ref.read(localQuotesProvider.notifier).eliminarPresupuesto(localQuote.orderId);
      ref.invalidate(quoteBadgeProvider);
      ref.invalidate(cartBadgeProvider);
      _showSnackBar('📧 "${localQuote.nombre}" enviado por email.', const Color(0xFF1565C0));
    } catch (e) {
      _showSnackBar('Error: $e', Colors.red);
    } finally {
      if (mounted) setState(() { _isLoadingAction = false; _processingQuoteId = null; });
    }
  }

  Future<void> _eliminarLocalQuote(String orderId, String nombre) async {
    if (_isLoadingAction) return;
    final confirmar = await _showConfirmDialog(
      title: 'Eliminar presupuesto',
      icon: Icons.delete_forever_rounded,
      iconColor: Colors.red,
      content: '¿Eliminar permanentemente "$nombre"?',
      confirmText: 'ELIMINAR',
      confirmColor: Colors.red,
      isDestructive: true,
    );
    if (confirmar != true || !mounted) return;
    setState(() { _isLoadingAction = true; _processingQuoteId = 'local_delete_$orderId'; });
    try {
      await ref.read(localQuotesProvider.notifier).eliminarPresupuesto(orderId);
      ref.invalidate(quoteBadgeProvider);
      ref.invalidate(cartBadgeProvider);
      _showSnackBar('"$nombre" eliminado.', Colors.grey.shade700);
    } finally {
      if (mounted) setState(() { _isLoadingAction = false; _processingQuoteId = null; });
    }
  }

  void _handleBack() {
    if (_isLoadingAction) return;
    if (_expandedQuoteIds.isNotEmpty || _expandedLocalQuoteIds.isNotEmpty) {
      setState(() { _expandedQuoteIds.clear(); _expandedLocalQuoteIds.clear(); });
      return;
    }
    if (widget.onGoHome != null) widget.onGoHome!();
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD PRINCIPAL
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final quotesAsync = ref.watch(quotesProvider);
    final localQuotes = ref.watch(localQuotesProvider);
    final localQuotesActivos = localQuotes.where((q) => !q.isExpired).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: ProfessionalPageAppBar(
        title: 'MIS PRESUPUESTOS',
        subtitle: 'Gestiona y acepta tus presupuestos',
        icon: Icons.description_outlined,
        onBack: _handleBack,
        onRefresh: _refreshQuotes,
      ),
      body: quotesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (err, stack) => _buildErrorState(),
        data: (allWebQuotes) {
          final webQuotes = allWebQuotes.where((q) => !_hiddenQuoteIds.contains(q.id)).toList();
          final total = localQuotesActivos.length + webQuotes.length;

          if (total == 0) return _buildEmptyState();

          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildSummaryBar(locales: localQuotesActivos.length, web: webQuotes.length)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                        (context, index) {
                      if (index < localQuotesActivos.length) {
                        return _buildLocalQuoteCard(localQuotesActivos[index]);
                      }
                      final webIndex = index - localQuotesActivos.length;
                      return _buildWebQuoteCard(webQuotes[webIndex]);
                    },
                    childCount: total,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // WIDGETS
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSummaryBar({required int locales, required int web}) {
    final total = locales + web;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.primary, Color(0xFFE53935)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: const Icon(Icons.request_quote_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$total presupuesto${total != 1 ? 's' : ''}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF1A1A1A))),
              if (locales > 0 && web > 0)
                Text('$locales local${locales != 1 ? 'es' : ''} · $web servidor', style: TextStyle(fontSize: 11, color: Colors.grey[500], fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  // ──── LOCAL CARD ────
  Widget _buildLocalQuoteCard(LocalQuote quote) {
    final isExpanded = _expandedLocalQuoteIds.contains(quote.orderId);
    final isProcessing = _processingQuoteId != null && _processingQuoteId!.contains(quote.orderId);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 6))],
        border: Border.all(color: const Color(0xFFF0F0F0)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: ExpansionTile(
          initiallyExpanded: isExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          onExpansionChanged: (expanded) => setState(() {
            expanded ? _expandedLocalQuoteIds.add(quote.orderId) : _expandedLocalQuoteIds.remove(quote.orderId);
          }),
          leading: Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.folder_rounded, color: Colors.orange, size: 24),
          ),
          title: Row(
            children: [
              Expanded(child: Text(quote.nombre, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF1A1A1A)))),
              const SizedBox(width: 8),
              _buildBadge('LOCAL', Colors.orange),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(Icons.inventory_2_outlined, size: 13, color: Colors.grey[400]),
                const SizedBox(width: 4),
                Text('${quote.items.length} productos', style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w500)),
                const SizedBox(width: 12),
                Icon(Icons.euro_rounded, size: 13, color: Colors.grey[400]),
                const SizedBox(width: 2),
                Text(_formatMoney(quote.total), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
              ],
            ),
          ),
          trailing: _buildTrailing(isExpanded, isProcessing),
          children: [
            const Divider(height: 1),
            const SizedBox(height: 12),
            ...quote.items.map((item) => _buildLocalItemTile(item)),
            const SizedBox(height: 14),
            if (!isProcessing) _buildCardButtons(
              onDelete: () => _eliminarLocalQuote(quote.orderId, quote.nombre),
              onSave: () => _guardarLocalPresupuesto(quote),
              onAccept: () => _aceptarLocalYIrAlCarrito(quote),
            ),
          ],
        ),
      ),
    );
  }

  // ──── WEB CARD ────
  Widget _buildWebQuoteCard(QuoteMundicam quote) {
    final isExpanded = _expandedQuoteIds.contains(quote.id);
    final isProcessing = _processingQuoteId != null && _processingQuoteId!.contains(quote.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 6))],
        border: Border.all(color: const Color(0xFFF0F0F0)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: ExpansionTile(
          initiallyExpanded: isExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          onExpansionChanged: (expanded) {
            setState(() => expanded ? _expandedQuoteIds.add(quote.id) : _expandedQuoteIds.remove(quote.id));
            if (expanded) _loadWebQuoteItems(quote);
          },
          leading: Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.cloud_rounded, color: Colors.blue, size: 24),
          ),
          title: Row(
            children: [
              Expanded(child: Text('Presupuesto #${quote.id}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF1A1A1A)))),
              const SizedBox(width: 8),
              _buildBadge('WEB', Colors.blue),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(Icons.euro_rounded, size: 13, color: Colors.grey[400]),
                const SizedBox(width: 2),
                Text(_formatMoney(quote.total), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
              ],
            ),
          ),
          trailing: _buildTrailing(isExpanded, isProcessing),
          children: [
            const Divider(height: 1),
            const SizedBox(height: 12),
            _buildWebExpandedContent(quote),
            if (!isProcessing) ...[
              const SizedBox(height: 14),
              _buildCardButtons(
                onDelete: () => _eliminarPresupuesto(quote),
                onSave: () => _guardarPresupuesto(quote),
                onAccept: () => _aceptarPresupuesto(quote),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWebExpandedContent(QuoteMundicam quote) {
    return FutureBuilder<List<_QuoteLineItem>>(
      future: _loadWebQuoteItems(quote),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))));
        }
        if (snapshot.hasError) return const Padding(padding: EdgeInsets.all(14), child: Text('Error al cargar.', style: TextStyle(color: Colors.red)));
        final items = snapshot.data ?? [];
        if (items.isEmpty) return const Padding(padding: EdgeInsets.all(14), child: Text('Sin productos.', style: TextStyle(color: Colors.grey)));
        return Column(children: items.map((item) => _buildWebItemTile(item)).toList());
      },
    );
  }

  // ──── ITEMS ────
  Widget _buildLocalItemTile(LocalQuoteItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF8F9FB), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: Colors.orange.shade300, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.productName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1A1A1A)), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Text('${item.quantity} ud × ${_formatMoney(item.price)} = ${_formatMoney(item.subtotal)}', style: TextStyle(fontSize: 11, color: Colors.grey[500], fontWeight: FontWeight.w500)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildWebItemTile(_QuoteLineItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF8F9FB), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: Colors.blue.shade300, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1A1A1A)), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Text('${item.quantity} ud × ${_formatMoney(item.unitPrice)} = ${_formatMoney(item.total)}', style: TextStyle(fontSize: 11, color: Colors.grey[500], fontWeight: FontWeight.w500)),
            ]),
          ),
        ],
      ),
    );
  }

  // ──── BOTONES DE ACCIÓN ────
  Widget _buildCardButtons({required VoidCallback onDelete, required VoidCallback onSave, required VoidCallback onAccept}) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildOutlinedButton('Eliminar', Icons.delete_outline_rounded, Colors.red.shade600, onDelete)),
            const SizedBox(width: 10),
            Expanded(child: _buildOutlinedButton('Guardar', Icons.save_outlined, const Color(
                0xFF000000), onSave)),
          ],
        ),
        const SizedBox(height: 10),
        _buildGradientButton('ACEPTAR Y PAGAR', Icons.shopping_cart_rounded, onAccept),
      ],
    );
  }

  Widget _buildOutlinedButton(String text, IconData icon, Color color, VoidCallback onPressed) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 15, color: color),
      label: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color.withOpacity(0.4)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 11),
        backgroundColor: color.withOpacity(0.03),
      ),
    );
  }

  Widget _buildGradientButton(String text, IconData icon, VoidCallback onPressed) {
    return Container(
      width: double.infinity,
      height: 46,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFA60909), Color(
            0xFFD60808)], begin: Alignment.centerLeft, end: Alignment.centerRight),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: const Color(0xFFA60909).withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18, color: Colors.white),
        label: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      ),
    );
  }

  // ──── COMPONENTES REUTILIZABLES ────
  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.5)),
    );
  }

  Widget _buildTrailing(bool isExpanded, bool isProcessing) {
    if (isProcessing) return const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary));
    return AnimatedRotation(
      turns: isExpanded ? 0.5 : 0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        width: 32, height: 32,
        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF1A1A1A), size: 20),
      ),
    );
  }

  Future<bool> _showConfirmDialog({
    required String title,
    required IconData icon,
    required Color iconColor,
    required String content,
    required String confirmText,
    required Color confirmColor,
    bool isDestructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(color: iconColor.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Color(0xFF1A1A1A)), textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text(content, style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280), height: 1.5), textAlign: TextAlign.center),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.5))),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: confirmColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
            child: Text(confirmText, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.5)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showSnackBar(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)));
  }

  String _buildEmailBody(String quoteId, List<_QuoteLineItem> items, double total) {
    final buf = StringBuffer();
    buf.writeln('═══════════════════════════════════');
    buf.writeln('  PRESUPUESTO #$quoteId');
    buf.writeln('═══════════════════════════════════');
    buf.writeln('');
    for (final item in items) {
      buf.writeln('  • ${item.name}');
      buf.writeln('    Ref: ${item.productId} | Cant: ${item.quantity} | ${_formatMoney(item.total)}');
      buf.writeln('');
    }
    buf.writeln('───────────────────────────────────');
    buf.writeln('  TOTAL: ${_formatMoney(total)}');
    buf.writeln('  Productos: ${items.length}');
    buf.writeln('───────────────────────────────────');
    buf.writeln('');
    buf.writeln('Fecha: ${_formatDateTime(DateTime.now())}');
    buf.writeln('Enviado desde la app Mundicam');
    return buf.toString();
  }

  String _buildLocalEmailBody(LocalQuote quote) {
    final buf = StringBuffer();
    buf.writeln('═══════════════════════════════════');
    buf.writeln('  ${quote.nombre.toUpperCase()}');
    buf.writeln('═══════════════════════════════════');
    buf.writeln('');
    for (final item in quote.items) {
      buf.writeln('  • ${item.productName}');
      buf.writeln('    Ref: ${item.productId} | Cant: ${item.quantity} | ${_formatMoney(item.subtotal)}');
      buf.writeln('');
    }
    buf.writeln('───────────────────────────────────');
    buf.writeln('  TOTAL: ${_formatMoney(quote.total)}');
    buf.writeln('  Productos: ${quote.items.length}');
    buf.writeln('───────────────────────────────────');
    buf.writeln('');
    buf.writeln('Fecha: ${_formatDateTime(DateTime.now())}');
    buf.writeln('Enviado desde la app Mundicam');
    return buf.toString();
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
              child: Icon(Icons.receipt_long_outlined, size: 52, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 28),
            const Text('No tienes presupuestos', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
            const SizedBox(height: 10),
            Text('Añade productos desde el catálogo\npara crear presupuestos locales.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey[500], height: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 100, height: 100, decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle), child: const Icon(Icons.error_outline, size: 48, color: Colors.redAccent)),
        const SizedBox(height: 24),
        const Text('Error al cargar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        ElevatedButton.icon(onPressed: _refreshQuotes, icon: const Icon(Icons.refresh), label: const Text('REINTENTAR'), style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
      ]),
    );
  }

  String _formatMoney(double value) {
    final abs = value.abs();
    final fixed = abs.toStringAsFixed(2);
    final parts = fixed.split('.');
    final groups = <String>[];
    for (int i = parts[0].length; i > 0; i -= 3) {
      groups.insert(0, parts[0].substring((i - 3).clamp(0, parts[0].length), i));
    }
    return '${value < 0 ? '-' : ''}${groups.join('.')},${parts.length > 1 ? parts[1] : '00'} €';
  }

  String _formatDateTime(DateTime dt) => '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

// ═══════════════════════════════════════════════════════════════
// MODELO
// ═══════════════════════════════════════════════════════════════

class _QuoteLineItem {
  final int lineItemId, productId, quantity;
  final String name;
  final double total;

  const _QuoteLineItem({required this.lineItemId, required this.productId, required this.name, required this.quantity, required this.total});

  double get unitPrice => quantity <= 0 ? total : total / quantity;

  factory _QuoteLineItem.fromWooLineItem(dynamic raw) {
    final map = raw is Map ? raw : const <dynamic, dynamic>{};
    final subtotal = _parseDouble(map['subtotal']);
    final total = _parseDouble(map['total']);
    return _QuoteLineItem(
      lineItemId: _parseInt(map['id']),
      productId: _parseInt(map['product_id']),
      name: (map['name']?.toString() ?? 'Producto').replaceAll(RegExp(r'<[^>]*>'), '').trim(),
      quantity: _parseInt(map['quantity'], fallback: 1),
      total: total > 0 ? total : subtotal,
    );
  }

  static int _parseInt(dynamic v, {int fallback = 0}) => v is int ? v : v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? fallback;
  static double _parseDouble(dynamic v) {
    if (v == null) return 0;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    final raw = v.toString().trim().replaceAll('€', '').replaceAll(RegExp(r'\s+'), '');
    if (raw.contains(',') && raw.contains('.')) return double.tryParse(raw.replaceAll('.', '').replaceAll(',', '.')) ?? 0;
    return double.tryParse(raw.replaceAll(',', '.')) ?? 0;
  }
}
// pages/quotes_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/network/api_service.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/professional_page_app_bar.dart';
import '../../../checkout/presentation/pages/payment_page.dart';
import '../../../../shared/providers/badge_provider.dart';
import '../../../catalog/data/models/producto.dart';
import '../../../catalog/presentation/pages/producto_detalles_page.dart';
import '../../data/models/quote_model.dart';
import '../../data/models/local_quote_model.dart';
import '../providers/quote_provider.dart';
import '../providers/local_quote_provider.dart';
import '../providers/quotes_sync_provider.dart';

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
  String? _deletingItemKey;

  final Set<String> _hiddenQuoteIds = <String>{};
  final Set<String> _expandedQuoteIds = <String>{};
  final Set<String> _expandedLocalQuoteIds = <String>{};

  final Map<String, List<_QuoteLineItem>> _webItemsCache =
  <String, List<_QuoteLineItem>>{};

  final Map<String, Future<List<_QuoteLineItem>>> _webItemsFutures =
  <String, Future<List<_QuoteLineItem>>>{};

  final Map<String, Map<String, dynamic>> _webDetailsCache =
  <String, Map<String, dynamic>>{};

  final Map<int, Product?> _productPreviewCache = <int, Product?>{};

  final Map<int, Future<Product?>> _productPreviewFutures = <int, Future<Product?>>{};

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
      _webDetailsCache.clear();
      _expandedQuoteIds.clear();
      _expandedLocalQuoteIds.clear();
    });
    await _loadPersistedData();
    ref.invalidate(quotesProvider);
    ref.invalidate(quoteBadgeProvider);
    ref.invalidate(cartBadgeProvider);
  }

  Future<void> _openProductDetail(
    int productId,
    String productName, {
    String sku = '',
  }) async {
    if ((productId <= 0 && sku.trim().isEmpty && productName.trim().isEmpty) ||
        _isLoadingAction) {
      return;
    }

    final navigator = Navigator.of(context);

    try {
      final product = await _loadProductPreview(
        productId,
        sku: sku,
        productName: productName,
        forceRetry: true,
      );

      if (!mounted) return;

      if (product == null) {
        _showSnackBar('No se pudo abrir el producto "$productName".', Colors.red);
        return;
      }

      navigator.push(
        MaterialPageRoute(
          builder: (_) => ProductDetailScreen(
            product: product,
            onGoCart: widget.onGoCart,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Error abriendo producto: $e', Colors.red);
    }
  }


  Future<Product?> _loadProductPreview(
    int productId, {
    String sku = '',
    String productName = '',
    bool forceRetry = false,
  }) {
    final cleanSku = sku.trim().toLowerCase();
    final cleanName = productName.trim().toLowerCase();
    final cacheKey = productId > 0
        ? productId
        : (cleanSku.isNotEmpty ? cleanSku.hashCode : cleanName.hashCode);
    if (cacheKey == 0) return Future.value(null);
    if (!forceRetry && _productPreviewCache.containsKey(cacheKey)) {
      return Future.value(_productPreviewCache[cacheKey]);
    }
    if (!forceRetry && _productPreviewFutures.containsKey(cacheKey)) {
      return _productPreviewFutures[cacheKey]!;
    }

    final future = _fetchProductPreview(
      productId,
      sku: sku,
      productName: productName,
      cacheKey: cacheKey,
    );
    _productPreviewFutures[cacheKey] = future;
    return future;
  }

  Future<Product?> _fetchProductPreview(
    int productId, {
    required int cacheKey,
    String sku = '',
    String productName = '',
  }) async {
    final api = ApiService();

    Product? product;

    if (productId > 0) {
      for (var attempt = 0; attempt < 2; attempt++) {
        product = await api.getProductoById(productId);
        if (product != null) break;
        await Future.delayed(Duration(milliseconds: 180 + (attempt * 220)));
      }
    }

    product ??= await _findProductFallback(
      api,
      sku: sku,
      productName: productName,
      productId: productId,
    );

    _productPreviewCache[cacheKey] = product;
    _productPreviewFutures.remove(cacheKey);
    return product;
  }

  Future<Product?> _findProductFallback(
    ApiService api, {
    required String sku,
    required String productName,
    required int productId,
  }) async {
    final cleanSku = sku.trim();
    final cleanName = productName.trim();

    final queries = <String>[
      if (cleanSku.isNotEmpty) cleanSku,
      if (cleanName.isNotEmpty) cleanName,
    ];

    for (final query in queries) {
      try {
        final result = await api.getProductosCatalogoFiltrado(
          search: query,
          page: 1,
          perPage: 8,
        );
        if (result.products.isEmpty) continue;

        if (productId > 0) {
          final byId = result.products.where((p) => p.id == productId).toList();
          if (byId.isNotEmpty) return byId.first;
        }

        if (cleanSku.isNotEmpty) {
          final normalizedSku = cleanSku.toLowerCase();
          final bySku = result.products.where(
            (p) => p.sku.trim().toLowerCase() == normalizedSku,
          ).toList();
          if (bySku.isNotEmpty) return bySku.first;
        }

        return result.products.first;
      } catch (_) {
        // La imagen de presupuestos no debe romper la pantalla. Si una búsqueda
        // auxiliar falla, probamos la siguiente fuente y dejamos el placeholder.
      }
    }

    return null;
  }

  Widget _buildDeleteProductButton({
    required bool isDeleting,
    required VoidCallback onPressed,
  }) {
    if (isDeleting) {
      return const SizedBox(
        width: 44,
        height: 44,
        child: Padding(
          padding: EdgeInsets.all(10),
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red),
        ),
      );
    }

    return Tooltip(
      message: 'Eliminar producto',
      child: Material(
        color: Colors.red.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          child: const SizedBox(
            width: 44,
            height: 44,
            child: Icon(Icons.close_rounded, size: 24, color: Colors.red),
          ),
        ),
      ),
    );
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
      _webDetailsCache.remove(quoteId);
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
      if (orden == null) return <_QuoteLineItem>[];
      _webDetailsCache[quote.id] = Map<String, dynamic>.from(orden);

      // PHP 1.9.26 devuelve el detalle completo en `items`; versiones anteriores
      // podían devolver `line_items`. Aceptamos ambas formas para no volver a
      // mostrar "Sin productos" cuando el presupuesto sí está correcto en la web.
      final rawItems = orden['items'] ?? orden['line_items'] ?? orden['products'];
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
  // ELIMINAR PRODUCTO INDIVIDUAL - WEB
  // ═══════════════════════════════════════════════════════════════

  Future<void> _eliminarProductoWeb(QuoteMundicam quote, _QuoteLineItem item) async {
    if (_isLoadingAction || _deletingItemKey != null) return;

    final itemKey = '${quote.id}_${item.productId}';
    setState(() { _deletingItemKey = itemKey; });

    try {
      final api = ApiService();
      final orderId = _extractOrderId(quote);
      final eliminado = await api.eliminarProductoPresupuesto(orderId: orderId, productId: item.productId);

      if (!eliminado) throw Exception('No se pudo eliminar el producto.');

      // Actualizar caché
      final items = List<_QuoteLineItem>.from(_webItemsCache[quote.id] ?? []);
      items.removeWhere((i) => i.productId == item.productId);

      if (items.isEmpty) {
        await _hideWebQuote(quote.id);
      } else {
        setState(() => _webItemsCache[quote.id] = items);
      }

      ref.invalidate(quotesProvider);
      ref.invalidate(quoteBadgeProvider);

      _showSnackBar('${item.name} eliminado del presupuesto.', Colors.green.shade700);
    } catch (e) {
      _showSnackBar('Error: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _deletingItemKey = null);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ELIMINAR PRODUCTO INDIVIDUAL - LOCAL
  // ═══════════════════════════════════════════════════════════════

  Future<void> _eliminarProductoLocal(LocalQuote quote, int productId, String productName) async {
    if (_isLoadingAction || _deletingItemKey != null) return;

    final itemKey = '${quote.orderId}_$productId';
    setState(() { _deletingItemKey = itemKey; });

    try {
      final notifier = ref.read(localQuotesProvider.notifier);

      await notifier.eliminarItem(orderId: quote.orderId, productId: productId);

      // Verificar si el presupuesto quedó vacío
      final updated = notifier.getPresupuesto(quote.orderId);
      if (updated == null || updated.items.isEmpty) {
        _expandedLocalQuoteIds.remove(quote.orderId);
      }

      ref.invalidate(quoteBadgeProvider);
      ref.invalidate(cartBadgeProvider);

      _showSnackBar('$productName eliminado del presupuesto.', Colors.green.shade700);
    } catch (e) {
      _showSnackBar('Error: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _deletingItemKey = null);
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
      content: 'Se abrirá el pago seguro del presupuesto.\n\n'
          'Si vuelves atrás o cancelas antes de pagar, el presupuesto seguirá visible en Mis presupuestos para que puedas intentarlo de nuevo.\n\n'
          'Presupuesto: #${quote.id}\nTotal: ${_formatMoney(quote.total)}',
      confirmText: 'ACEPTAR Y PAGAR',
      confirmColor: const Color(0xFF2E7D32),
    );
    if (confirmar != true || !mounted) return;
    setState(() { _isLoadingAction = true; _processingQuoteId = 'accept_${quote.id}'; });
    try {
      final api = ApiService();
      final quoteId = int.parse(_extractOrderId(quote));
      final result = await api.aceptarYPagarPresupuesto(quoteId: quoteId);

      if (!mounted) return;

      if (result.isPaid) {
        _showSnackBar('✅ El presupuesto ya aparece como pagado.', Colors.green.shade700);
        ref.invalidate(quotesProvider);
        ref.invalidate(quoteBadgeProvider);
        return;
      }

      if (!result.canPay || !result.hasPaymentUrl || result.pendingOrderId <= 0) {
        throw Exception('El servidor no devolvió una URL de pago válida.');
      }

      setState(() { _isLoadingAction = false; _processingQuoteId = null; });

      final paid = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => PaymentPage(
            orderId: result.pendingOrderId,
            orderKey: '',
            paymentUrl: result.paymentUrl,
            orderNumber: result.pendingOrderId.toString(),
            amount: quote.total,
            paymentMethodTitle: 'Pago seguro del presupuesto',
            quotePayment: true,
            quoteNumber: quote.id,
          ),
        ),
      );

      if (!mounted) return;

      ref.invalidate(quotesProvider);
      ref.invalidate(quoteBadgeProvider);
      ref.invalidate(cartBadgeProvider);

      if (paid == true) {
        _showSnackBar('✅ Pago confirmado. El presupuesto pasará a pedidos.', Colors.green.shade700);
      } else {
        _showSnackBar('El presupuesto sigue guardado para pagarlo más tarde.', const Color(0xFF1565C0));
      }
    } catch (e) {
      if (mounted) _showSnackBar('Error: $e', Colors.red);
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
      content: 'Este presupuesto ya está guardado en tu cuenta.\n\n'
          'Presupuesto: #${quote.id}\nTotal: ${_formatMoney(quote.total)}\n\n'
          'Seguirá visible en la sección Presupuestos de la app y en la web.',
      confirmText: 'ENTENDIDO',
      confirmColor: const Color(0xFF1565C0),
    );
    if (confirmar != true || !mounted) return;
    _showSnackBar('✅ Presupuesto #${quote.id} · ${quote.statusLabel}.', const Color(0xFF1565C0));
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
      content: 'Se guardará este presupuesto y se abrirá el pago seguro.\n\n'
          'Si vuelves atrás o cancelas antes de pagar, seguirá visible en Mis presupuestos.\n\n'
          '"${localQuote.nombre}"\n${localQuote.items.length} productos\nTotal: ${_formatMoney(localQuote.total)}',
      confirmText: 'ACEPTAR Y PAGAR',
      confirmColor: const Color(0xFF2E7D32),
    );
    if (confirmar != true || !mounted) return;
    setState(() { _isLoadingAction = true; _processingQuoteId = 'local_accept_${localQuote.orderId}'; });

    int createdQuoteId = 0;
    try {
      final api = ApiService();
      final created = await api.crearPresupuestoConProductosDetalle(
        items: localQuote.items
            .map((item) => {
                  'product_id': item.productId,
                  'quantity': item.quantity,
                })
            .toList(),
        customerNote: localQuote.nombre,
      );

      if (!created.success || created.quoteId <= 0) {
        throw Exception(created.message.isNotEmpty
            ? created.message
            : 'No se pudo guardar el presupuesto en el servidor.');
      }
      createdQuoteId = created.quoteId;

      // Ya existe como presupuesto real en /quotes. Quitamos solo la copia local
      // para evitar duplicados, pero NO lo mandamos al carrito.
      await ref.read(localQuotesProvider.notifier).eliminarPresupuesto(localQuote.orderId);
      ref.invalidate(quotesProvider);
      ref.invalidate(quoteBadgeProvider);
      ref.invalidate(cartBadgeProvider);

      final result = await api.aceptarYPagarPresupuesto(quoteId: created.quoteId);

      if (!mounted) return;

      if (result.isPaid) {
        _showSnackBar('✅ El presupuesto ya aparece como pagado.', Colors.green.shade700);
        ref.invalidate(quotesProvider);
        ref.invalidate(quoteBadgeProvider);
        return;
      }

      if (!result.canPay || !result.hasPaymentUrl || result.pendingOrderId <= 0) {
        throw Exception('El servidor no devolvió una URL de pago válida.');
      }

      setState(() { _isLoadingAction = false; _processingQuoteId = null; });

      final paid = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => PaymentPage(
            orderId: result.pendingOrderId,
            orderKey: '',
            paymentUrl: result.paymentUrl,
            orderNumber: result.pendingOrderId.toString(),
            amount: created.total > 0 ? created.total : localQuote.total,
            paymentMethodTitle: 'Pago seguro del presupuesto',
            quotePayment: true,
            quoteNumber: 'PRE-${created.quoteId}',
          ),
        ),
      );

      if (!mounted) return;

      ref.invalidate(quotesProvider);
      ref.invalidate(quoteBadgeProvider);
      ref.invalidate(cartBadgeProvider);

      if (paid == true) {
        _showSnackBar('✅ Pago confirmado. El presupuesto pasará a pedidos.', Colors.green.shade700);
      } else {
        _showSnackBar('El presupuesto sigue guardado para pagarlo más tarde.', const Color(0xFF1565C0));
      }
    } catch (e) {
      ref.invalidate(quotesProvider);
      ref.invalidate(quoteBadgeProvider);
      ref.invalidate(cartBadgeProvider);
      final extra = createdQuoteId > 0
          ? '\nEl presupuesto ya quedó guardado en Mis presupuestos.'
          : '';
      if (mounted) _showSnackBar('Error: $e$extra', Colors.red);
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
      content: 'Se guardará este presupuesto en tu cuenta para que aparezca en la app y en la web.\n\n'
          '"${localQuote.nombre}"\n${localQuote.items.length} productos\nTotal: ${_formatMoney(localQuote.total)}',
      confirmText: 'GUARDAR PRESUPUESTO',
      confirmColor: const Color(0xFF1565C0),
    );
    if (confirmar != true || !mounted) return;
    setState(() { _isLoadingAction = true; _processingQuoteId = 'local_save_${localQuote.orderId}'; });
    try {
      final email = await ref.read(currentQuoteEmailProvider.future);
      if (email == null || email.trim().isEmpty) {
        throw Exception('No se pudo identificar el email del cliente.');
      }

      await ref.read(quoteSyncProvider).syncAndRemoveLocalQuote(
        orderId: localQuote.orderId,
        email: email.trim(),
      );

      ref.invalidate(quotesProvider);
      ref.invalidate(quoteBadgeProvider);
      ref.invalidate(cartBadgeProvider);
      _showSnackBar('✅ "${localQuote.nombre}" guardado en la nube.', const Color(0xFF1565C0));
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
            decoration: BoxDecoration(color: Colors.orange.withOpacity(0.08), borderRadius: BorderRadius.circular(14)),
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
            ...quote.items.map((item) => _buildLocalItemTile(quote, item)),
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
            decoration: BoxDecoration(color: Colors.blue.withOpacity(0.08), borderRadius: BorderRadius.circular(14)),
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
                const SizedBox(width: 12),
                Icon(Icons.info_outline_rounded, size: 13, color: Colors.grey[400]),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    quote.statusLabel,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w600),
                  ),
                ),
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
        final detail = _webDetailsCache[quote.id] ?? <String, dynamic>{};
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...items.map((item) => _buildWebItemTile(quote, item)),
            const SizedBox(height: 8),
            _buildQuoteTotalsBreakdown(
              detail: detail,
              items: items,
              fallbackTotal: quote.total,
            ),
          ],
        );
      },
    );
  }


  Widget _buildQuoteTotalsBreakdown({
    required Map<String, dynamic> detail,
    required List<_QuoteLineItem> items,
    required double fallbackTotal,
  }) {
    final itemsSubtotal = items.fold<double>(0, (sum, item) => sum + item.total);
    final subtotal = _firstMoney([
      detail['subtotal'],
      detail['subtotal_ex_tax'],
      detail['items_subtotal'],
      detail['line_subtotal'],
    ], fallback: itemsSubtotal);
    final total = _firstMoney([
      detail['total'],
      detail['grand_total'],
      detail['amount'],
    ], fallback: fallbackTotal > 0 ? fallbackTotal : subtotal);
    final tax = _firstMoney([
      detail['tax_total'],
      detail['total_tax'],
      detail['iva'],
    ], fallback: total > subtotal ? total - subtotal : 0);
    final shipping = _firstMoney([
      detail['shipping_total'],
      detail['shipping'],
    ]);
    final discount = _firstMoney([
      detail['discount_total'],
      detail['discount'],
    ]);
    final fees = _firstMoney([
      detail['fees_total'],
      detail['fee_total'],
    ]);

    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECEFF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Total del presupuesto',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: Color(0xFF008F49),
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 10),
          _buildTotalRow('Subtotal', subtotal),
          if (tax > 0.004) _buildTotalRow('IVA 21%', tax),
          if (shipping > 0.004) _buildTotalRow('Envío', shipping),
          if (fees.abs() > 0.004) _buildTotalRow('Cargos', fees),
          if (discount > 0.004) _buildTotalRow('Descuento', -discount),
          const Divider(height: 18),
          _buildTotalRow('Total', total, strong: true),
        ],
      ),
    );
  }

  Widget _buildQuoteCustomerDetails(Map<String, dynamic> detail) {
    final billing = _asStringMap(detail['billing']);
    if (billing.isEmpty) return const SizedBox.shrink();

    final firstName = _cleanText(billing['first_name']);
    final lastName = _cleanText(billing['last_name']);
    final fullName = _firstText([
      '$firstName $lastName'.trim(),
      billing['name'],
      billing['display_name'],
    ]);
    final company = _cleanText(billing['company']);
    final address1 = _cleanText(billing['address_1']);
    final address2 = _cleanText(billing['address_2']);
    final address = address2.isNotEmpty && address2 != address1
        ? '$address1\n$address2'.trim()
        : address1;
    final city = _cleanText(billing['city']);
    final postcode = _cleanText(billing['postcode']);
    final state = _cleanText(billing['state']);
    final country = _formatCountry(_cleanText(billing['country']));
    final phone = _cleanText(billing['phone']);
    final email = _cleanText(billing['email']);

    final rows = <Widget>[
      if (fullName.isNotEmpty) _buildCustomerRow('Nombre', fullName),
      if (company.isNotEmpty) _buildCustomerRow('Empresa', company),
      if (address.isNotEmpty) _buildCustomerRow('Dirección', address),
      if (city.isNotEmpty) _buildCustomerRow('Ciudad', city),
      if (postcode.isNotEmpty) _buildCustomerRow('Código postal', postcode),
      if (state.isNotEmpty) _buildCustomerRow('Estado/Provincia', state),
      if (country.isNotEmpty) _buildCustomerRow('País', country),
      if (phone.isNotEmpty) _buildCustomerRow('Teléfono', phone),
      if (email.isNotEmpty) _buildCustomerRow('Email', email),
    ];

    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECEFF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Detalles de cliente',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: Color(0xFF008F49),
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 10),
          ...rows,
        ],
      ),
    );
  }

  Widget _buildTotalRow(String label, double value, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: strong ? 14 : 12,
                fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
                color: const Color(0xFF1A1A1A),
              ),
            ),
          ),
          Text(
            _formatMoney(value),
            style: TextStyle(
              fontSize: strong ? 16 : 12,
              fontWeight: FontWeight.w900,
              color: strong ? AppColors.primary : const Color(0xFF1A1A1A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.25,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A1A),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _asStringMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  double _firstMoney(List<dynamic> values, {double fallback = 0}) {
    for (final value in values) {
      final parsed = _parseMoney(value);
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  double? _parseMoney(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final raw = value.toString().trim();
    if (raw.isEmpty || raw.toLowerCase() == 'null') return null;
    final clean = raw
        .replaceAll('€', '')
        .replaceAll(RegExp(r'[^0-9,.-]'), '')
        .trim();
    if (clean.isEmpty) return null;
    if (clean.contains(',') && clean.contains('.')) {
      return double.tryParse(clean.replaceAll('.', '').replaceAll(',', '.'));
    }
    return double.tryParse(clean.replaceAll(',', '.'));
  }

  String _firstText(List<dynamic> values) {
    for (final value in values) {
      final clean = _cleanText(value);
      if (clean.isNotEmpty) return clean;
    }
    return '';
  }

  String _cleanText(dynamic value) {
    if (value == null) return '';
    final clean = value.toString().replaceAll(RegExp(r'<[^>]*>'), '').trim();
    if (clean.isEmpty || clean.toLowerCase() == 'null') return '';
    return clean;
  }

  String _formatCountry(String value) {
    final clean = value.trim();
    if (clean.toUpperCase() == 'ES') return 'España';
    return clean;
  }

  // ──── ITEMS ────
  Widget _buildLocalItemTile(LocalQuote quote, LocalQuoteItem item) {
    final itemKey = '${quote.orderId}_${item.productId}';
    final isDeleting = _deletingItemKey == itemKey;

    return _buildQuoteProductTile(
      accentColor: Colors.orange.shade300,
      productId: item.productId,
      productName: item.productName,
      quantity: item.quantity,
      unitPrice: item.price,
      total: item.subtotal,
      imageUrl: '',
      sku: '',
      isDeleting: isDeleting,
      onDelete: () => _eliminarProductoLocal(
        quote,
        item.productId,
        item.productName,
      ),
    );
  }

  Widget _buildWebItemTile(QuoteMundicam quote, _QuoteLineItem item) {
    final itemKey = '${quote.id}_${item.productId}';
    final isDeleting = _deletingItemKey == itemKey;

    return _buildQuoteProductTile(
      accentColor: Colors.blue.shade300,
      productId: item.productId,
      productName: item.name,
      quantity: item.quantity,
      unitPrice: item.unitPrice,
      total: item.total,
      taxTotal: item.taxTotal,
      imageUrl: item.imageUrl,
      sku: item.sku,
      isDeleting: isDeleting,
      onDelete: () => _eliminarProductoWeb(quote, item),
    );
  }

  Widget _buildQuoteProductTile({
    required Color accentColor,
    required int productId,
    required String productName,
    required int quantity,
    required double unitPrice,
    required double total,
    double taxTotal = 0,
    required String imageUrl,
    required String sku,
    required bool isDeleting,
    required VoidCallback onDelete,
  }) {
    final baseImageUrl = imageUrl.trim();
    final baseSku = sku.trim();
    final baseName = productName.trim();

    // Si el presupuesto ya trae imagen/SKU/nombre desde /quotes, no hacemos una
    // llamada extra por producto. Así la pantalla abre más rápido y solo se
    // consulta la ficha cuando falta información real.
    final canLookupProduct = productId > 0 || baseSku.isNotEmpty || baseName.isNotEmpty;
    final needsProductPreview = canLookupProduct &&
        (baseImageUrl.isEmpty || baseSku.isEmpty || baseName.isEmpty || baseName == 'Producto');

    if (!needsProductPreview) {
      return _buildQuoteProductTileContent(
        accentColor: accentColor,
        productId: productId,
        productName: baseName.isNotEmpty ? baseName : 'Producto',
        quantity: quantity,
        unitPrice: unitPrice,
        total: total,
        taxTotal: taxTotal,
        imageUrl: baseImageUrl,
        sku: baseSku,
        isDeleting: isDeleting,
        onDelete: onDelete,
      );
    }

    return FutureBuilder<Product?>(
      future: _loadProductPreview(
        productId,
        sku: baseSku,
        productName: baseName,
      ),
      builder: (context, snapshot) {
        final product = snapshot.data;
        return _buildQuoteProductTileContent(
          accentColor: accentColor,
          productId: productId,
          productName: baseName.isNotEmpty ? baseName : (product?.name.trim() ?? 'Producto'),
          quantity: quantity,
          unitPrice: unitPrice,
          total: total,
          taxTotal: taxTotal,
          imageUrl: baseImageUrl.isNotEmpty ? baseImageUrl : (product?.imageUrl.trim() ?? ''),
          sku: baseSku.isNotEmpty ? baseSku : (product?.sku.trim() ?? ''),
          isDeleting: isDeleting,
          onDelete: onDelete,
        );
      },
    );
  }

  Widget _buildQuoteProductTileContent({
    required Color accentColor,
    required int productId,
    required String productName,
    required int quantity,
    required double unitPrice,
    required double total,
    double taxTotal = 0,
    required String imageUrl,
    required String sku,
    required bool isDeleting,
    required VoidCallback onDelete,
  }) {
    final effectiveName = productName.trim().isNotEmpty ? productName.trim() : 'Producto';
    final effectiveSku = sku.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECEFF3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openProductDetail(
            productId,
            effectiveName,
            sku: effectiveSku,
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildQuoteProductImage(
                  imageUrl: imageUrl.trim(),
                  accentColor: accentColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        effectiveName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          height: 1.18,
                          color: Color(0xFF171717),
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      if (effectiveSku.isNotEmpty) ...[
                        Text(
                          'SKU: $effectiveSku',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 5),
                      ],
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(color: accentColor, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '$quantity ud × ${_formatMoney(unitPrice)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatMoney(total),
                        style: const TextStyle(
                          fontSize: 15,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (taxTotal > 0.004) ...[
                        const SizedBox(height: 3),
                        Text(
                          'IVA: ${_formatMoney(taxTotal)}',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _buildDeleteProductButton(
                  isDeleting: isDeleting,
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  Widget _buildQuoteProductImage({
    required String imageUrl,
    required Color accentColor,
  }) {
    return Container(
      width: 74,
      height: 74,
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFECEFF3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl.isEmpty
          ? Icon(Icons.image_outlined, color: accentColor, size: 30)
          : CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.contain,
              fadeInDuration: const Duration(milliseconds: 120),
              placeholder: (_, __) => Icon(Icons.image_outlined, color: accentColor.withOpacity(0.45), size: 28),
              errorWidget: (_, __, ___) => Icon(Icons.image_not_supported_outlined, color: accentColor, size: 28),
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
            Expanded(child: _buildOutlinedButton('Guardar', Icons.save_outlined, const Color(0xFF1565C0), onSave)),
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
        gradient: const LinearGradient(colors: [Color(0xFFA60909), Color(0xFFD60808)], begin: Alignment.centerLeft, end: Alignment.centerRight),
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
  final String name, sku, imageUrl;
  final double total, taxTotal;

  const _QuoteLineItem({
    required this.lineItemId,
    required this.productId,
    required this.name,
    required this.quantity,
    required this.total,
    this.taxTotal = 0,
    this.sku = '',
    this.imageUrl = '',
  });

  double get unitPrice => quantity <= 0 ? total : total / quantity;

  factory _QuoteLineItem.fromWooLineItem(dynamic raw) {
    final map = raw is Map ? raw : const <dynamic, dynamic>{};
    final subtotal = _parseDouble(map['subtotal']);
    final total = _parseDouble(map['total']);
    final tax = _parseDouble(map['tax_total'] ?? map['tax'] ?? map['line_tax'] ?? map['total_tax']);
    return _QuoteLineItem(
      lineItemId: _parseInt(map['id'] ?? map['line_item_id'] ?? map['item_id']),
      productId: _parseInt(map['product_id'] ?? map['productId'] ?? map['id_product']),
      name: (map['name']?.toString() ?? map['product_name']?.toString() ?? 'Producto').replaceAll(RegExp(r'<[^>]*>'), '').trim(),
      quantity: _parseInt(map['quantity'] ?? map['qty'], fallback: 1),
      total: total > 0 ? total : subtotal,
      taxTotal: tax,
      sku: _parseString(map['sku'] ?? map['product_sku'] ?? map['ref'] ?? map['reference']),
      imageUrl: _extractImageUrl(map),
    );
  }

  static int _parseInt(dynamic v, {int fallback = 0}) => v is int ? v : v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? fallback;

  static String _parseString(dynamic v) {
    if (v == null) return '';
    final raw = v.toString().trim();
    if (raw.isEmpty || raw.toLowerCase() == 'null') return '';
    return raw;
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
      if (first is Map) return _parseString(first['src'] ?? first['url'] ?? first['thumbnail']);
      return _parseString(first);
    }

    return '';
  }

  static double _parseDouble(dynamic v) {
    if (v == null) return 0;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    final raw = v.toString().trim().replaceAll('€', '').replaceAll(RegExp(r'\s+'), '');
    if (raw.contains(',') && raw.contains('.')) return double.tryParse(raw.replaceAll('.', '').replaceAll(',', '.')) ?? 0;
    return double.tryParse(raw.replaceAll(',', '.')) ?? 0;
  }
}
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
import '../providers/quote_provider.dart';

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
  String? _activeQuoteId;

  final Set<String> _hiddenQuoteIds = <String>{};
  final Set<String> _expandedQuoteIds = <String>{};
  final Set<String> _deletingLineItemKeys = <String>{};

  final Map<String, List<_QuoteLineItem>> _quoteItemsCache =
  <String, List<_QuoteLineItem>>{};

  final Map<String, Future<List<_QuoteLineItem>>> _quoteItemsFutures =
  <String, Future<List<_QuoteLineItem>>>{};

  @override
  void initState() {
    super.initState();
    _hiddenQuoteIds.addAll(widget.confirmedQuoteIds);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _loadConfirmedQuoteIds();
      ref.invalidate(quotesProvider);
      ref.invalidate(quoteBadgeProvider);
    });
  }

  Future<void> _refreshQuotes() async {
    if (!mounted) return;

    setState(() {
      _quoteItemsCache.clear();
      _quoteItemsFutures.clear();
      _expandedQuoteIds.clear();
      _activeQuoteId = null;
      _hiddenQuoteIds.addAll(widget.confirmedQuoteIds);
    });

    await _loadConfirmedQuoteIds();
    ref.invalidate(quotesProvider);
    ref.invalidate(quoteBadgeProvider);
    ref.invalidate(cartBadgeProvider);
  }

  Future<void> _loadConfirmedQuoteIds() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIds = prefs.getStringList(_confirmedQuoteIdsKey) ?? <String>[];

    if (!mounted) return;

    setState(() {
      _hiddenQuoteIds.addAll(savedIds);
    });
  }

  Future<void> _saveConfirmedQuoteIds(Set<String> quoteIds) async {
    if (quoteIds.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final savedIds = prefs.getStringList(_confirmedQuoteIdsKey) ?? <String>[];

    final updatedIds = <String>{
      ...savedIds,
      ...quoteIds,
    };

    await prefs.setStringList(_confirmedQuoteIdsKey, updatedIds.toList());
    await widget.onQuotesConfirmed?.call(quoteIds);

    if (mounted) {
      setState(() {
        _hiddenQuoteIds.addAll(quoteIds);
        for (final quoteId in quoteIds) {
          _quoteItemsCache[quoteId] = <_QuoteLineItem>[];
          _quoteItemsFutures.remove(quoteId);
          _expandedQuoteIds.remove(quoteId);
        }
        _activeQuoteId = null;
      });
    }

    ref.invalidate(quotesProvider);
    ref.invalidate(quoteBadgeProvider);
    ref.invalidate(cartBadgeProvider);
  }

  List<QuoteMundicam> _getVisibleQuotes(List<QuoteMundicam> allQuotes) {
    return allQuotes.where((quote) {
      if (_hiddenQuoteIds.contains(quote.id)) return false;

      final cachedItems = _quoteItemsCache[quote.id];
      if (cachedItems != null && cachedItems.isEmpty) return false;
      if (quote.total <= 0 && cachedItems == null) return false;

      return true;
    }).toList();
  }

  String _extractOrderId(QuoteMundicam quote) {
    final orderId = quote.id.replaceAll(RegExp(r'[^0-9]'), '');
    if (orderId.isEmpty) {
      throw Exception('No se pudo identificar el ID del presupuesto.');
    }
    return orderId;
  }

  Future<List<_QuoteLineItem>> _loadQuoteItems(
      QuoteMundicam quote, {
        bool forceRefresh = false,
      }) {
    if (!forceRefresh && _quoteItemsCache.containsKey(quote.id)) {
      return Future.value(_quoteItemsCache[quote.id]!);
    }

    if (!forceRefresh && _quoteItemsFutures.containsKey(quote.id)) {
      return _quoteItemsFutures[quote.id]!;
    }

    final future = _fetchQuoteItems(quote);
    _quoteItemsFutures[quote.id] = future;

    return future;
  }

  Future<List<_QuoteLineItem>> _fetchQuoteItems(QuoteMundicam quote) async {
    try {
      final api = ApiService();
      final orderId = _extractOrderId(quote);
      final orden = await api.getOrdenCompleta(orderId);

      if (orden == null || orden['line_items'] == null) {
        throw Exception('No se pudieron cargar los productos.');
      }

      final rawItems = orden['line_items'];
      final lineItems = rawItems is List ? rawItems : <dynamic>[];

      final items = lineItems
          .map((item) => _QuoteLineItem.fromWooLineItem(item))
          .where((item) => item.name.trim().isNotEmpty)
          .toList();

      _quoteItemsCache[quote.id] = items;
      return items;
    } finally {
      _quoteItemsFutures.remove(quote.id);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // CONFIRMAR PRESUPUESTOS Y ENVIAR PRODUCTOS AL CARRITO
  // ═══════════════════════════════════════════════════════════════

  Future<void> _confirmarPresupuestoYEnviarAlCarrito(
      List<QuoteMundicam> quotes,
      ) async {
    if (_isLoadingAction) return;

    final visibleQuotes = _getVisibleQuotes(quotes);
    if (visibleQuotes.isEmpty) return;

    final confirmar = await _confirmarMoverAlCarritoDialog(
      totalPresupuestos: visibleQuotes.length,
      total: _combinedVisibleTotal(visibleQuotes),
    );

    if (!confirmar || !mounted) return;

    setState(() {
      _isLoadingAction = true;
      _processingQuoteId = 'all';
      _activeQuoteId = null;
    });

    try {
      final api = ApiService();

      final List<_QuoteMoveItem> productosParaMover = <_QuoteMoveItem>[];
      final Set<String> quoteIdsConfirmados = <String>{};
      final Map<String, Set<int>> productosPorPedido = <String, Set<int>>{};

      for (final quote in visibleQuotes) {
        if (!mounted) return;

        final orderId = _extractOrderId(quote);

        setState(() {
          _activeQuoteId = quote.id;
        });

        final items = await _loadQuoteItems(quote, forceRefresh: true);

        for (final item in items) {
          if (item.productId <= 0) continue;

          final producto = await api.getProductoById(item.productId);
          if (producto == null) continue;

          productosParaMover.add(
            _QuoteMoveItem(
              quoteId: quote.id,
              orderId: orderId,
              item: item,
              product: producto,
            ),
          );

          quoteIdsConfirmados.add(quote.id);
          productosPorPedido
              .putIfAbsent(orderId, () => <int>{})
              .add(item.productId);
        }
      }

      if (productosParaMover.isEmpty) {
        throw Exception('No se pudo añadir ningún producto al carrito.');
      }

      for (final entry in productosPorPedido.entries) {
        final orderId = entry.key;
        final productIds = entry.value;

        for (final productId in productIds) {
          final eliminado = await api.eliminarProductoPresupuesto(
            orderId: orderId,
            productId: productId,
          );

          if (!eliminado) {
            throw Exception(
              'No se pudo quitar el producto $productId del presupuesto.',
            );
          }
        }
      }

      int productosAnadidos = 0;
      int unidadesAnadidas = 0;

      for (final moveItem in productosParaMover) {
        ref.read(cartProvider.notifier).addProduct(
          moveItem.product,
          moveItem.item.quantity,
        );

        productosAnadidos++;
        unidadesAnadidas += moveItem.item.quantity;
      }

      await _saveConfirmedQuoteIds(quoteIdsConfirmados);

      if (!mounted) return;

      ref.invalidate(quotesProvider);
      ref.invalidate(quoteBadgeProvider);
      ref.invalidate(cartBadgeProvider);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$productosAnadidos producto${productosAnadidos != 1 ? 's' : ''} '
                'movido${productosAnadidos != 1 ? 's' : ''} al carrito '
                '($unidadesAnadidas unidad${unidadesAnadidas != 1 ? 'es' : ''}).',
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 180));

      if (!mounted) return;
      _goToCart();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al confirmar presupuesto: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAction = false;
          _processingQuoteId = null;
          _activeQuoteId = null;
        });
      }
    }
  }

  Future<bool> _confirmarMoverAlCarritoDialog({
    required int totalPresupuestos,
    required double total,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Confirmar presupuesto',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          content: Text(
            'Se moverán los productos de tus presupuestos al carrito '
                'y se quitarán de presupuestos pendientes.\n\n'
                'Presupuestos: $totalPresupuestos\n'
                'Total: ${_formatMoney(total)}\n\n'
                '¿Quieres continuar?',
            style: const TextStyle(
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Confirmar',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  void _goToCart() {
    if (widget.onGoCart != null) {
      widget.onGoCart!();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // GUARDAR PRESUPUESTO POR EMAIL Y OCULTARLO
  // ═══════════════════════════════════════════════════════════════

  Future<bool> _confirmarGuardarPresupuestoDialog({
    required int totalPresupuestos,
    required double total,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Guardar presupuesto',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          content: Text(
            'Se abrirá tu aplicación de correo con el presupuesto listo '
                'para enviar a pedidos@mundicam.com.\n\n'
                'Presupuestos: $totalPresupuestos\n'
                'Total: ${_formatMoney(total)}\n\n'
                '¿Quieres continuar?',
            style: const TextStyle(
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Guardar',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  Future<void> _guardarPresupuestoPorEmail(List<QuoteMundicam> quotes) async {
    if (_isLoadingAction) return;

    final visibleQuotes = _getVisibleQuotes(quotes);
    if (visibleQuotes.isEmpty) return;

    final confirmar = await _confirmarGuardarPresupuestoDialog(
      totalPresupuestos: visibleQuotes.length,
      total: _combinedVisibleTotal(visibleQuotes),
    );

    if (!confirmar || !mounted) return;

    setState(() {
      _isLoadingAction = true;
      _processingQuoteId = 'save';
      _activeQuoteId = null;
    });

    try {
      final StringBuffer cuerpoEmail = StringBuffer();
      double totalGeneral = 0;
      int totalProductos = 0;
      int totalUnidades = 0;
      final Set<String> quoteIdsGuardados = <String>{};

      for (final quote in visibleQuotes) {
        if (!mounted) return;

        setState(() {
          _activeQuoteId = quote.id;
        });

        final items = await _loadQuoteItems(quote, forceRefresh: true);
        if (items.isEmpty) continue;

        quoteIdsGuardados.add(quote.id);

        cuerpoEmail.writeln('═══════════════════════════════════');
        cuerpoEmail.writeln('  PRESUPUESTO #${quote.id}');
        cuerpoEmail.writeln('═══════════════════════════════════');
        cuerpoEmail.writeln('');

        for (final item in items) {
          final precioUnidad =
          item.quantity > 0 ? item.total / item.quantity : item.total;

          cuerpoEmail.writeln('  • ${item.name}');
          cuerpoEmail.writeln('    Cantidad: ${item.quantity}');
          cuerpoEmail.writeln('    Precio: ${_formatMoney(precioUnidad)}');
          cuerpoEmail.writeln('    Subtotal: ${_formatMoney(item.total)}');
          cuerpoEmail.writeln('');

          totalGeneral += item.total;
          totalProductos++;
          totalUnidades += item.quantity;
        }
      }

      if (totalProductos == 0 || quoteIdsGuardados.isEmpty) {
        throw Exception('No se encontraron productos en los presupuestos.');
      }

      cuerpoEmail.writeln('═══════════════════════════════════');
      cuerpoEmail.writeln('  TOTAL: ${_formatMoney(totalGeneral)}');
      cuerpoEmail.writeln('  Productos: $totalProductos');
      cuerpoEmail.writeln('  Unidades: $totalUnidades');
      cuerpoEmail.writeln('═══════════════════════════════════');
      cuerpoEmail.writeln('');
      cuerpoEmail.writeln('Enviado desde la app Mundicam');

      final asunto = 'Presupuesto Mundicam - ${_formatMoney(totalGeneral)}';

      final mailtoUri = Uri(
        scheme: 'mailto',
        path: 'pedidos@mundicam.com',
        queryParameters: {
          'subject': asunto,
          'body': cuerpoEmail.toString(),
        },
      );

      if (!await canLaunchUrl(mailtoUri)) {
        throw Exception('No se pudo abrir el cliente de correo.');
      }

      await launchUrl(mailtoUri, mode: LaunchMode.externalApplication);

      await _saveConfirmedQuoteIds(quoteIdsGuardados);

      if (!mounted) return;

      ref.invalidate(quotesProvider);
      ref.invalidate(quoteBadgeProvider);
      ref.invalidate(cartBadgeProvider);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Presupuesto guardado. '
                '$totalProductos producto${totalProductos != 1 ? 's' : ''} '
                'preparado${totalProductos != 1 ? 's' : ''} por email.',
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      debugPrint('❌ Error guardando presupuesto: $e');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar presupuesto: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAction = false;
          _processingQuoteId = null;
          _activeQuoteId = null;
        });
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ELIMINAR PRODUCTO DE PRESUPUESTO
  // ═══════════════════════════════════════════════════════════════

  Future<void> _deleteQuoteItem(
      QuoteMundicam quote,
      _QuoteLineItem item,
      ) async {
    if (_isLoadingAction) return;

    final deleteKey = '${quote.id}_${item.productId}_${item.lineItemId}';
    if (_deletingLineItemKeys.contains(deleteKey)) return;

    setState(() {
      _deletingLineItemKeys.add(deleteKey);
      _activeQuoteId = quote.id;
    });

    try {
      final orderId = _extractOrderId(quote);

      final deleted = await ApiService().eliminarProductoPresupuesto(
        orderId: orderId,
        productId: item.productId,
      );

      if (!deleted) {
        throw Exception('No se pudo eliminar el producto del presupuesto.');
      }

      final updatedItems = List<_QuoteLineItem>.from(
        _quoteItemsCache[quote.id] ?? <_QuoteLineItem>[],
      );

      updatedItems.removeWhere(
            (quoteItem) => quoteItem.productId == item.productId,
      );

      final bool presupuestoVacio = updatedItems.isEmpty;

      if (presupuestoVacio) {
        await _saveConfirmedQuoteIds(<String>{quote.id});
      }

      if (!mounted) return;

      setState(() {
        if (presupuestoVacio) {
          _hiddenQuoteIds.add(quote.id);
          _quoteItemsCache[quote.id] = <_QuoteLineItem>[];
          _quoteItemsFutures.remove(quote.id);
          _expandedQuoteIds.remove(quote.id);

          if (_activeQuoteId == quote.id) {
            _activeQuoteId = null;
          }
        } else {
          _quoteItemsCache[quote.id] = updatedItems;
        }
      });

      ref.invalidate(quotesProvider);
      ref.invalidate(quoteBadgeProvider);
      ref.invalidate(cartBadgeProvider);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            presupuestoVacio
                ? 'Presupuesto eliminado.'
                : '${item.name} eliminado del presupuesto.',
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al eliminar producto: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _deletingLineItemKeys.remove(deleteKey);
        });
      }
    }
  }

  void _handleBack() {
    if (_isLoadingAction) return;

    if (_expandedQuoteIds.isNotEmpty || _activeQuoteId != null) {
      setState(() {
        _expandedQuoteIds.clear();
        _activeQuoteId = null;
      });
      return;
    }

    if (widget.onGoHome != null) {
      widget.onGoHome!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final quotesAsync = ref.watch(quotesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: ProfessionalPageAppBar(
        title: 'MIS PRESUPUESTOS',
        subtitle: 'Gestiona y confirma tus presupuestos',
        icon: Icons.description_outlined,
        onBack: _handleBack,
        onRefresh: _refreshQuotes,
      ),
      bottomNavigationBar: quotesAsync.maybeWhen(
        data: (allQuotes) {
          final quotes = _getVisibleQuotes(allQuotes);
          if (quotes.isEmpty) return null;
          return _buildBottomQuoteBar(quotes);
        },
        orElse: () => null,
      ),
      body: quotesAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (err, stack) => _buildErrorState(),
        data: (allQuotes) {
          final quotes = _getVisibleQuotes(allQuotes);

          if (quotes.isEmpty) {
            return _buildEmptyState(context);
          }

          return Column(
            children: [
              _buildSummaryBar(quotes),
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _refreshQuotes,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 104),
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: quotes.length,
                    itemBuilder: (context, index) =>
                        _buildQuoteCard(quotes[index]),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryBar(List<QuoteMundicam> quotes) {
    final total = _combinedVisibleTotal(quotes);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: Colors.white,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.request_quote_outlined,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${quotes.length} presupuesto${quotes.length != 1 ? 's' : ''} pendiente${quotes.length != 1 ? 's' : ''}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Text(
            'Total: ${_formatMoney(total)}',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: AppColors.primary,
              fontFamily: 'Oswald',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomQuoteBar(List<QuoteMundicam> quotes) {
    final total = _combinedVisibleTotal(quotes);
    final bool isProcessing = _isLoadingAction;
    final bool isSaving = _processingQuoteId == 'save';
    final bool isConfirming = _processingQuoteId == 'all';

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Colors.grey.shade200),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 18,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TOTAL PRESUPUESTOS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _formatMoney(total),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                      fontFamily: 'Oswald',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 180,
                  height: 36,
                  child: OutlinedButton.icon(
                    onPressed: isProcessing
                        ? null
                        : () => _guardarPresupuestoPorEmail(quotes),
                    icon: isSaving
                        ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.blue,
                      ),
                    )
                        : const Icon(Icons.save_alt_rounded, size: 16),
                    label: const Text(
                      'GUARDAR PRESUP.',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue.shade700,
                      side: BorderSide(color: Colors.blue.shade300),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: 180,
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: isProcessing
                        ? null
                        : () =>
                        _confirmarPresupuestoYEnviarAlCarrito(quotes),
                    icon: isConfirming
                        ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'CONFIRMAR',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      disabledBackgroundColor: Colors.grey.shade300,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double _combinedVisibleTotal(List<QuoteMundicam> quotes) {
    return quotes.fold<double>(
      0,
          (sum, quote) => sum + _quoteDisplayTotal(quote),
    );
  }

  double _quoteDisplayTotal(QuoteMundicam quote) {
    final cachedItems = _quoteItemsCache[quote.id];
    if (cachedItems == null) return quote.total;

    return cachedItems.fold<double>(
      0,
          (sum, item) => sum + item.total,
    );
  }

  Widget _buildQuoteCard(QuoteMundicam quote) {
    final bool isExpanded = _expandedQuoteIds.contains(quote.id);
    final bool isActive = _activeQuoteId == quote.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isActive
              ? AppColors.primary.withOpacity(0.45)
              : Colors.grey.shade200,
          width: isActive ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ExpansionTile(
        key: ValueKey<String>('quote_${quote.id}_$isExpanded'),
        initiallyExpanded: isExpanded,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        onExpansionChanged: (expanded) {
          setState(() {
            if (expanded) {
              _expandedQuoteIds.add(quote.id);
              _activeQuoteId = quote.id;
            } else {
              _expandedQuoteIds.remove(quote.id);
              if (_activeQuoteId == quote.id) {
                _activeQuoteId = null;
              }
            }
          });

          if (expanded) {
            _loadQuoteItems(quote);
          }
        },
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.description_outlined,
            color: AppColors.primary,
            size: 21,
          ),
        ),
        title: Text(
          'Presupuesto #${quote.id}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: Color(0xFF1A1A1A),
          ),
        ),
        subtitle: Text(
          'Total: ${_formatMoney(_quoteDisplayTotal(quote))}',
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: AnimatedRotation(
          turns: isExpanded ? 0.5 : 0,
          duration: const Duration(milliseconds: 180),
          child: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.textPrimary,
            size: 26,
          ),
        ),
        children: [
          _buildExpandedQuoteContent(quote),
        ],
      ),
    );
  }

  Widget _buildExpandedQuoteContent(QuoteMundicam quote) {
    return FutureBuilder<List<_QuoteLineItem>>(
      future: _loadQuoteItems(quote),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }

        if (snapshot.hasError) {
          return _buildQuoteItemsError(quote);
        }

        final items = snapshot.data ?? <_QuoteLineItem>[];

        if (items.isEmpty) {
          return _buildNoItemsState();
        }

        return Column(
          children: [
            const Divider(height: 1),
            const SizedBox(height: 8),
            ...items.map(
                  (item) => _buildQuoteLineItem(
                quote: quote,
                item: item,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildQuoteLineItem({
    required QuoteMundicam quote,
    required _QuoteLineItem item,
  }) {
    final deleteKey = '${quote.id}_${item.productId}_${item.lineItemId}';
    final isDeleting = _deletingLineItemKeys.contains(deleteKey);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade100),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.quantity} x ${_formatMoney(item.total / item.quantity)} = ${_formatMoney(item.total)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isDeleting)
            const SizedBox(
              width: 34,
              height: 34,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Eliminar producto',
              visualDensity: VisualDensity.compact,
              onPressed: item.productId <= 0
                  ? null
                  : () => _deleteQuoteItem(quote, item),
              icon: Icon(
                Icons.delete_outline_rounded,
                color: item.productId <= 0
                    ? Colors.grey.shade400
                    : Colors.red.shade600,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuoteItemsError(QuoteMundicam quote) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 28),
          const SizedBox(height: 8),
          const Text(
            'No se pudieron cargar los productos.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _quoteItemsCache.remove(quote.id);
                _quoteItemsFutures.remove(quote.id);
              });
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _buildNoItemsState() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        'Este presupuesto no tiene productos.',
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.description_outlined,
                size: 64,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No tienes presupuestos pendientes',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Cuando solicites un presupuesto desde el catálogo\naparecerá aquí.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 20),
            const Text(
              'Error al cargar presupuestos',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _refreshQuotes,
              icon: const Icon(Icons.refresh),
              label: const Text('REINTENTAR'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatMoney(double value) {
    final absoluteValue = value.abs();
    final fixed = absoluteValue.toStringAsFixed(2);
    final parts = fixed.split('.');
    final intPart = parts.first;
    final decimalPart = parts.length > 1 ? parts[1] : '00';

    final groups = <String>[];

    for (int i = intPart.length; i > 0; i -= 3) {
      final start = i - 3 < 0 ? 0 : i - 3;
      groups.insert(0, intPart.substring(start, i));
    }

    final sign = value < 0 ? '-' : '';

    return '$sign${groups.join('.')},$decimalPart €';
  }
}

// ────────────────────────────────────────────────────────────
// MODELOS
// ────────────────────────────────────────────────────────────

class _QuoteMoveItem {
  final String quoteId;
  final String orderId;
  final _QuoteLineItem item;
  final dynamic product;

  const _QuoteMoveItem({
    required this.quoteId,
    required this.orderId,
    required this.item,
    required this.product,
  });
}

class _QuoteLineItem {
  final int lineItemId;
  final int productId;
  final String name;
  final int quantity;
  final double total;

  const _QuoteLineItem({
    required this.lineItemId,
    required this.productId,
    required this.name,
    required this.quantity,
    required this.total,
  });

  factory _QuoteLineItem.fromWooLineItem(dynamic raw) {
    final map = raw is Map ? raw : const <dynamic, dynamic>{};

    final subtotal = _parseDouble(map['subtotal']);
    final total = _parseDouble(map['total']);

    return _QuoteLineItem(
      lineItemId: _parseInt(map['id']),
      productId: _parseInt(map['product_id']),
      name: _cleanText(map['name']?.toString() ?? 'Producto'),
      quantity: _parseInt(map['quantity'], fallback: 1),
      total: total > 0 ? total : subtotal,
    );
  }

  static int _parseInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
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

  static String _cleanText(String value) {
    return value.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }
}
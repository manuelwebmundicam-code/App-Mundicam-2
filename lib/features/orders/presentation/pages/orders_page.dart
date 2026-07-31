import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/features/cart/presentation/providers/cart_provider.dart';
import 'package:mundicam/features/catalog/data/models/producto.dart';
import 'package:mundicam/features/catalog/presentation/pages/producto_detalles_page.dart';
import 'package:mundicam/features/home/presentation/pages/home_page.dart';
import 'package:mundicam/features/orders/data/models/order_model.dart';
import 'package:mundicam/features/orders/presentation/providers/order_provider.dart';
import 'package:mundicam/features/rma/presentation/pages/rma_from_page.dart';
import 'package:mundicam/shared/providers/badge_provider.dart';
import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/shared/widgets/professional_page_app_bar.dart';

const Color _pageBg = Color(0xFFF4F7FB);
const Color _dark = Color(0xFF111827);
const Color _muted = Color(0xFF6B7280);
const Color _border = Color(0xFFE5E7EB);
const Color _softCard = Color(0xFFFBFCFE);

class OrdersPage extends ConsumerStatefulWidget {
  final VoidCallback? onGoHome;

  const OrdersPage({
    super.key,
    this.onGoHome,
  });

  @override
  ConsumerState<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends ConsumerState<OrdersPage> {
  void _goToHome(BuildContext context) {
    if (widget.onGoHome != null) {
      widget.onGoHome!();
      return;
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomePage()),
      (route) => false,
    );
  }

  Future<void> _refreshOrders() async {
    ref.invalidate(ordersProvider);
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  void _openOrderDetail(BuildContext context, OrderMundicam order) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderDetailPage(order: order),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(ordersProvider);

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: ProfessionalPageAppBar(
        title: 'MIS PEDIDOS',
        subtitle: '',
        icon: Icons.local_shipping_outlined,
        onBack: () => _goToHome(context),
        onRefresh: _refreshOrders,
      ),
      body: ordersAsync.when(
        loading: () => const _OrdersLoadingState(),
        error: (err, stack) => _buildErrorState(),
        data: (orders) {
          if (orders.isEmpty) return _buildEmptyState(context);

          return Column(
            children: [
              _OrdersSummaryHeader(count: orders.length),
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _refreshOrders,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: orders.length,
                    itemBuilder: (context, index) =>
                        _buildOrderCard(context, orders[index]),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOrderCard(BuildContext context, OrderMundicam order) {
    final int totalUnidades = order.items.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => _openOrderDetail(context, order),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildStatusBadge(order.status, labelOverride: order.displayStatusLabel),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pedido #${order.id}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Oswald',
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          height: 1.05,
                          color: _dark,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        DateFormat('dd/MM/yyyy · HH:mm')
                            .format(order.dateCreated),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 11.8,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (order.items.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          '${order.items.length} producto${order.items.length != 1 ? 's' : ''} · '
                          '$totalUnidades ud${totalUnidades != 1 ? 's' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 10.8,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTotalString(order.total),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15.5,
                        color: AppColors.primary,
                        fontFamily: 'Oswald',
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'VER DETALLE',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.035),
                blurRadius: 14,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.local_shipping_outlined,
                  size: 42,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'No tienes pedidos realizados todavía',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Oswald',
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: _dark,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tus pedidos aparecerán aquí cuando realices una compra.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: _muted,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.035),
                blurRadius: 14,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.cloud_off_rounded,
                  size: 38,
                  color: Colors.redAccent,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'No pudimos cargar tus pedidos',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Oswald',
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: _dark,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Comprueba tu conexión y vuelve a intentarlo.',
                style: TextStyle(
                  color: _muted,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: () => ref.invalidate(ordersProvider),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text(
                    'REINTENTAR',
                    style: TextStyle(
                      fontFamily: 'Oswald',
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OrderDetailPage extends ConsumerStatefulWidget {
  final OrderMundicam order;

  const OrderDetailPage({
    super.key,
    required this.order,
  });

  @override
  ConsumerState<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends ConsumerState<OrderDetailPage> {
  late Future<List<_PedidoProducto>> _itemsFuture;
  OrderMundicam? _loadedOrder;
  bool _isRepeating = false;

  final Map<int, Product?> _productPreviewCache = <int, Product?>{};
  final Map<int, Future<Product?>> _productPreviewFutures =
      <int, Future<Product?>>{};

  @override
  void initState() {
    super.initState();
    _itemsFuture = _fetchFullOrderItems();
  }

  Future<void> _refresh() async {
    setState(() {
      _loadedOrder = null;
      _productPreviewCache.clear();
      _productPreviewFutures.clear();
      _itemsFuture = _fetchFullOrderItems();
    });

    await _itemsFuture;
  }

  Future<List<_PedidoProducto>> _fetchFullOrderItems() async {
    final fallbackItems = widget.order.items
        .map(_PedidoProducto.fromOrderItem)
        .where((item) => item.name.trim().isNotEmpty)
        .toList();

    try {
      final api = ApiService();
      final fullOrder = await api.getOrderDetail(
        orderId: widget.order.id,
        orderKey: widget.order.orderKey,
      );

      if (fullOrder != null) {
        if (mounted) {
          setState(() {
            _loadedOrder = fullOrder;
          });
        }

        final fullItems = fullOrder.items
            .map(_PedidoProducto.fromOrderItem)
            .where((item) => item.name.trim().isNotEmpty)
            .toList();

        if (fullItems.isNotEmpty) return fullItems;
      }

      final orderData = await api.getOrdenCompleta(widget.order.id.toString());
      if (orderData != null) {
        final parsedOrder = OrderMundicam.fromJson(orderData);
        if (mounted) {
          setState(() {
            _loadedOrder = parsedOrder;
          });
        }

        final fullItems = parsedOrder.items
            .map(_PedidoProducto.fromOrderItem)
            .where((item) => item.name.trim().isNotEmpty)
            .toList();

        if (fullItems.isNotEmpty) return fullItems;

        final rawItems = orderData['line_items'] ?? orderData['items'];
        final lineItems = rawItems is List ? rawItems : <dynamic>[];

        final legacyItems = lineItems
            .whereType<Map>()
            .map(
              (item) => _PedidoProducto.fromWooLineItem(
                Map<String, dynamic>.from(item),
              ),
            )
            .where((item) => item.name.trim().isNotEmpty)
            .toList();

        if (legacyItems.isNotEmpty) return legacyItems;
      }

      return fallbackItems;
    } catch (_) {
      return fallbackItems;
    }
  }

  Future<Product?> _loadProductPreview(
    _PedidoProducto item, {
    bool forceRetry = false,
  }) {
    final cleanSku = item.sku.trim().toLowerCase();
    final cleanName = item.name.trim().toLowerCase();
    final cacheKey = item.productId > 0
        ? item.productId
        : (cleanSku.isNotEmpty ? cleanSku.hashCode : cleanName.hashCode);

    if (cacheKey == 0) return Future.value(null);

    if (!forceRetry && _productPreviewCache.containsKey(cacheKey)) {
      return Future.value(_productPreviewCache[cacheKey]);
    }

    if (!forceRetry && _productPreviewFutures.containsKey(cacheKey)) {
      return _productPreviewFutures[cacheKey]!;
    }

    final future = _fetchProductPreview(item, cacheKey: cacheKey);
    _productPreviewFutures[cacheKey] = future;
    return future;
  }

  Future<Product?> _fetchProductPreview(
    _PedidoProducto item, {
    required int cacheKey,
  }) async {
    final api = ApiService();
    Product? product;

    if (item.productId > 0) {
      for (var attempt = 0; attempt < 2; attempt++) {
        product = await api.getProductoById(item.productId);
        if (product != null) break;
        await Future.delayed(Duration(milliseconds: 180 + (attempt * 220)));
      }
    }

    product ??= await _findProductFallback(api, item);

    _productPreviewCache[cacheKey] = product;
    _productPreviewFutures.remove(cacheKey);
    return product;
  }

  Future<Product?> _findProductFallback(
    ApiService api,
    _PedidoProducto item,
  ) async {
    final queries = <String>[
      if (item.sku.trim().isNotEmpty) item.sku.trim(),
      if (item.name.trim().isNotEmpty) item.name.trim(),
    ];

    for (final query in queries) {
      try {
        final result = await api.getProductosCatalogoFiltrado(
          search: query,
          page: 1,
          perPage: 8,
        );

        if (result.products.isEmpty) continue;

        if (item.productId > 0) {
          final byId = result.products.where((p) => p.id == item.productId);
          if (byId.isNotEmpty) return byId.first;
        }

        if (item.sku.trim().isNotEmpty) {
          final normalizedSku = item.sku.trim().toLowerCase();
          final bySku = result.products.where(
            (p) => p.sku.trim().toLowerCase() == normalizedSku,
          );
          if (bySku.isNotEmpty) return bySku.first;
        }

        return result.products.first;
      } catch (_) {
        // Si un producto no se puede resolver, dejamos placeholder y seguimos.
      }
    }

    return null;
  }

  Future<void> _openProductDetail(_PedidoProducto item) async {
    if (_isRepeating) return;

    try {
      final product = await _loadProductPreview(item, forceRetry: true);
      if (!mounted) return;

      if (product == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo abrir el producto "${item.name}".'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductDetailScreen(product: product),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error abriendo producto: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _repetirPedido(List<_PedidoProducto> items) async {
    if (_isRepeating) return;

    setState(() {
      _isRepeating = true;
    });

    var dialogOpen = false;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
      dialogOpen = true;

      if (items.isEmpty) {
        throw Exception('Este pedido no tiene productos para repetir.');
      }

      int productosAnadidos = 0;
      int unidadesAnadidas = 0;
      int productosSinStock = 0;
      int productosNoEncontrados = 0;

      for (final item in items) {
        final producto = await _loadProductPreview(item, forceRetry: true);

        if (producto == null) {
          productosNoEncontrados++;
          continue;
        }

        if (!producto.hasStock) {
          productosSinStock++;
          continue;
        }

        ref.read(cartProvider.notifier).addProduct(
          producto,
          item.quantity,
        );

        productosAnadidos++;
        unidadesAnadidas += item.quantity;
      }

      ref.invalidate(cartBadgeProvider);

      if (mounted && dialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogOpen = false;
      }

      if (!mounted) return;

      if (productosAnadidos == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'No se pudo repetir el pedido. Los productos pueden estar sin stock o descatalogados.',
            ),
            backgroundColor: Colors.orange.shade700,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }

      final skipped = productosSinStock + productosNoEncontrados;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            skipped > 0
                ? '✅ $productosAnadidos producto${productosAnadidos != 1 ? 's' : ''} añadido${productosAnadidos != 1 ? 's' : ''} al carrito ($unidadesAnadidas ud). $skipped producto${skipped != 1 ? 's' : ''} no disponible${skipped != 1 ? 's' : ''}.'
                : '✅ $productosAnadidos producto${productosAnadidos != 1 ? 's' : ''} añadido${productosAnadidos != 1 ? 's' : ''} al carrito ($unidadesAnadidas ud).',
          ),
          backgroundColor:
              skipped > 0 ? Colors.orange.shade700 : Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (mounted && dialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogOpen = false;
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al repetir pedido: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRepeating = false;
        });
      }

      if (mounted && dialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseOrder = _loadedOrder ?? widget.order;

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: ProfessionalPageAppBar(
        title: 'PEDIDO #${baseOrder.id}',
        subtitle: '',
        icon: Icons.receipt_long_outlined,
        onBack: () => Navigator.pop(context),
        onRefresh: _refresh,
      ),
      body: FutureBuilder<List<_PedidoProducto>>(
        future: _itemsFuture,
        builder: (context, snapshot) {
          final order = _loadedOrder ?? baseOrder;
          final items = snapshot.data ??
              order.items.map(_PedidoProducto.fromOrderItem).toList();
          final loading = snapshot.connectionState == ConnectionState.waiting;
          final totalUnidades = items.fold<int>(
            0,
            (sum, item) => sum + item.quantity,
          );

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
              children: [
                _buildOrderHeader(order, items.length, totalUnidades),
                const SizedBox(height: 14),
                _buildSectionHeader(items.length, totalUnidades),
                const SizedBox(height: 10),
                if (loading && items.isEmpty)
                  const _ProductsLoadingCard()
                else if (items.isEmpty)
                  const _EmptyProductsCard()
                else
                  ...items.map(_buildProductCard),
                const SizedBox(height: 16),
                _buildTotalsSection(order),
                const SizedBox(height: 12),
                _buildPaymentShippingSection(order),
                if (order.hasCustomerInfo) ...[
                  const SizedBox(height: 12),
                  _buildCustomerSections(order),
                ],
                if (order.customerNote.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildInfoCard(
                    icon: Icons.sticky_note_2_outlined,
                    title: 'NOTAS DEL PEDIDO',
                    children: [
                      _buildTextLine(order.customerNote.trim()),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                if (order.actions.canRepeat || !order.actions.hasExplicitValues)
                  SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: _isRepeating ? null : () => _repetirPedido(items),
                    icon: _isRepeating
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          )
                        : const Icon(Icons.replay_rounded, size: 18),
                    label: Text(
                      _isRepeating ? 'CARGANDO...' : 'REPETIR PEDIDO',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(
                        color: AppColors.primary.withOpacity(0.6),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildOrderHeader(
    OrderMundicam order,
    int productCount,
    int totalUnidades,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.receipt_long_outlined,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pedido #${order.id}',
                      style: const TextStyle(
                        fontFamily: 'Oswald',
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        height: 1.05,
                        color: _dark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      DateFormat('dd/MM/yyyy · HH:mm')
                          .format(order.dateCreated),
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _formatTotalString(order.total),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: AppColors.primary,
                  fontFamily: 'Oswald',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildStatusBadge(order.status, labelOverride: order.displayStatusLabel),
              _buildSmallInfoChip(
                Icons.inventory_2_outlined,
                '$productCount producto${productCount != 1 ? 's' : ''}',
              ),
              _buildSmallInfoChip(
                Icons.numbers_rounded,
                '$totalUnidades ud${totalUnidades != 1 ? 's' : ''}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTotalsSection(OrderMundicam order) {
    final rows = <_TotalRowData>[
      _TotalRowData('Subtotal productos', order.subtotal),
      if (_moneyValue(order.discountTotal) > 0)
        _TotalRowData('Descuentos', order.discountTotal, negative: true),
      if (_moneyValue(order.shippingTotal) > 0)
        _TotalRowData('Envío', order.shippingTotal),
      if (_moneyValue(order.feesTotal) > 0)
        _TotalRowData('Cargos adicionales', order.feesTotal),
      if (_moneyValue(order.taxTotal) > 0)
        _TotalRowData('IVA', order.taxTotal),
    ];

    return _buildInfoCard(
      icon: Icons.payments_outlined,
      title: 'RESUMEN ECONÓMICO',
      children: [
        if (rows.isEmpty)
          const _MutedLine(text: 'Desglose no disponible todavía.')
        else
          ...rows.map(
            (row) => _buildTotalRow(
              row.label,
              row.amount,
              negative: row.negative,
            ),
          ),
        const Divider(height: 18, color: _border),
        _buildTotalRow(
          'Total final',
          order.total,
          strong: true,
        ),
      ],
    );
  }

  Widget _buildPaymentShippingSection(OrderMundicam order) {
    final payment = order.paymentMethodTitle.trim().isNotEmpty
        ? order.paymentMethodTitle.trim()
        : order.paymentMethod.trim();
    final shipping = order.shippingMethodTitle.trim();

    return _buildInfoCard(
      icon: Icons.credit_card_outlined,
      title: 'DATOS DEL PEDIDO',
      children: [
        _buildDetailLine(
          Icons.account_balance_wallet_outlined,
          'Método de pago',
          payment.isNotEmpty ? payment : 'No especificado todavía',
        ),
        _buildDetailLine(
          Icons.local_shipping_outlined,
          'Método de envío',
          shipping.isNotEmpty ? shipping : 'No especificado todavía',
        ),
        _buildDetailLine(
          Icons.tag_outlined,
          'Referencia',
          '#${order.number.trim().isNotEmpty ? order.number.trim() : order.id.toString()}',
        ),
      ],
    );
  }

  Widget _buildCustomerSections(OrderMundicam order) {
    final hasBilling = order.billing.hasAnyVisibleValue;
    final hasShipping = order.shipping.hasAnyVisibleValue;

    if (!hasBilling && !hasShipping) {
      return _buildInfoCard(
        icon: Icons.person_outline,
        title: 'DATOS DEL CLIENTE Y ENVÍO',
        children: const [
          _MutedLine(text: 'Datos de cliente no disponibles todavía.'),
        ],
      );
    }

    if (hasBilling && hasShipping && _addressesLookSame(order.billing, order.shipping)) {
      return _buildAddressCard(
        icon: Icons.assignment_ind_outlined,
        title: 'DATOS DEL CLIENTE Y ENVÍO',
        address: order.billing,
        notice: 'Facturación y envío coinciden',
      );
    }

    if (hasBilling && !hasShipping) {
      return _buildAddressCard(
        icon: Icons.assignment_ind_outlined,
        title: 'DATOS DEL CLIENTE',
        address: order.billing,
      );
    }

    if (!hasBilling && hasShipping) {
      return _buildAddressCard(
        icon: Icons.home_work_outlined,
        title: 'DIRECCIÓN DE ENVÍO',
        address: order.shipping,
      );
    }

    return Column(
      children: [
        _buildAddressCard(
          icon: Icons.receipt_outlined,
          title: 'FACTURACIÓN',
          address: order.billing,
        ),
        const SizedBox(height: 12),
        _buildAddressCard(
          icon: Icons.home_work_outlined,
          title: 'DIRECCIÓN DE ENVÍO',
          address: order.shipping,
        ),
      ],
    );
  }

  bool _addressesLookSame(OrderAddress billing, OrderAddress shipping) {
    String normalize(String value) => value
        .toLowerCase()
        .replaceAll('españa', 'es')
        .replaceAll(RegExp(r'[^a-z0-9áéíóúüñ]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final billingCore = normalize([
      billing.firstName,
      billing.lastName,
      billing.company,
      billing.address1,
      billing.address2,
      billing.postcode,
      billing.city,
      billing.state,
      billing.country,
    ].where((part) => part.trim().isNotEmpty).join('|'));

    final shippingCore = normalize([
      shipping.firstName,
      shipping.lastName,
      shipping.company,
      shipping.address1,
      shipping.address2,
      shipping.postcode,
      shipping.city,
      shipping.state,
      shipping.country,
    ].where((part) => part.trim().isNotEmpty).join('|'));

    return billingCore.isNotEmpty && billingCore == shippingCore;
  }

  Widget _buildAddressCard({
    required IconData icon,
    required String title,
    required OrderAddress address,
    String? notice,
  }) {
    return _buildInfoCard(
      icon: icon,
      title: title,
      children: [
        if (notice != null && notice.trim().isNotEmpty)
          _buildAddressNotice(notice.trim()),
        if (address.fullName.isNotEmpty)
          _buildTextLine(address.fullName, strong: true),
        if (address.company.trim().isNotEmpty)
          _buildTextLine(address.company.trim()),
        if (address.addressLine.isNotEmpty)
          _buildTextLine(address.addressLine),
        if (address.cityLine.isNotEmpty)
          _buildTextLine(address.cityLine),
        if (address.phone.trim().isNotEmpty)
          _buildDetailLine(Icons.phone_outlined, 'Teléfono', address.phone.trim()),
        if (address.email.trim().isNotEmpty)
          _buildDetailLine(Icons.email_outlined, 'Email', address.email.trim()),
      ],
    );
  }

  Widget _buildAddressNotice(String text) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.14)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline,
            size: 16,
            color: AppColors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: _dark,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.025),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 18, color: AppColors.primary),
              ),
              const SizedBox(width: 9),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Oswald',
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: _dark,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTotalRow(
    String label,
    String amount, {
    bool negative = false,
    bool strong = false,
  }) {
    final value = _formatTotalString(amount);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: strong ? 13.5 : 12.2,
                fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
                color: strong ? _dark : _muted,
              ),
            ),
          ),
          Text(
            negative ? '-$value' : value,
            style: TextStyle(
              fontSize: strong ? 17 : 12.8,
              fontWeight: FontWeight.w900,
              color: strong ? AppColors.primary : _dark,
              fontFamily: strong ? 'Oswald' : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailLine(IconData icon, String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: _muted),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: _muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value.trim(),
                  style: const TextStyle(
                    fontSize: 12.2,
                    color: _dark,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextLine(String value, {bool strong = false}) {
    if (value.trim().isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        value.trim(),
        style: TextStyle(
          fontSize: 12.2,
          color: _dark,
          fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
          height: 1.3,
        ),
      ),
    );
  }

  Widget _buildSectionHeader(int productCount, int totalUnidades) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'PRODUCTOS DEL PEDIDO',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w900,
            color: _dark,
            letterSpacing: 0.6,
            fontFamily: 'Oswald',
          ),
        ),
        const Spacer(),
        Text(
          '$productCount producto${productCount != 1 ? 's' : ''} · '
          '$totalUnidades ud${totalUnidades != 1 ? 's' : ''}',
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[500],
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildProductCard(_PedidoProducto item) {
    final needsPreview = item.imageUrl.trim().isEmpty || item.sku.trim().isEmpty;

    if (!needsPreview) {
      return _buildProductCardContent(
        item: item,
        imageUrl: item.imageUrl,
        sku: item.sku,
      );
    }

    return FutureBuilder<Product?>(
      future: _loadProductPreview(item),
      builder: (context, snapshot) {
        final product = snapshot.data;
        return _buildProductCardContent(
          item: item,
          imageUrl: item.imageUrl.trim().isNotEmpty
              ? item.imageUrl.trim()
              : (product?.imageUrl.trim() ?? ''),
          sku: item.sku.trim().isNotEmpty
              ? item.sku.trim()
              : (product?.sku.trim() ?? ''),
        );
      },
    );
  }

  Widget _buildProductCardContent({
    required _PedidoProducto item,
    required String imageUrl,
    required String sku,
  }) {
    final currentOrder = _loadedOrder ?? widget.order;
    final status = currentOrder.normalizedStatus;
    final isCompleted = status == 'completed' || status == 'processing';
    final canRequestRma = isCompleted &&
        currentOrder.canRequestRma &&
        item.productId > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
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
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          borderRadius: BorderRadius.circular(17),
          onTap: () => _openProductDetail(
            item.copyWith(
              sku: sku.trim().isNotEmpty ? sku.trim() : item.sku,
              imageUrl: imageUrl.trim().isNotEmpty ? imageUrl.trim() : item.imageUrl,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildProductImage(imageUrl),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
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
                          if (sku.trim().isNotEmpty) ...[
                            Text(
                              'SKU: ${sku.trim()}',
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
                                decoration: const BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${item.quantity} ud × ${_formatMoney(item.unitPrice)}',
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
                            _formatMoney(item.total),
                            style: const TextStyle(
                              fontSize: 15,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (item.taxTotal > 0) ...[
                            const SizedBox(height: 3),
                            Text(
                              'IVA línea: ${_formatMoney(item.taxTotal)}',
                              style: TextStyle(
                                fontSize: 10.2,
                                color: Colors.grey[500],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      constraints: const BoxConstraints(minWidth: 36),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary.withOpacity(0.08),
                        ),
                      ),
                      child: Text(
                        '${item.quantity}x',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                if (canRequestRma) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 38,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RmaFormPage(
                              orderId: widget.order.id,
                              productId: item.productId,
                              productName: item.name,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.build_outlined, size: 16),
                      label: const Text(
                        'SOLICITAR RMA',
                        style: TextStyle(
                          fontSize: 10.8,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(
                          color: AppColors.primary.withOpacity(0.55),
                          width: 1.1,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProductImage(String imageUrl) {
    final cleanImage = imageUrl.trim();

    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFECEFF3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: cleanImage.isEmpty
          ? const Icon(
              Icons.image_outlined,
              color: AppColors.primary,
              size: 30,
            )
          : CachedNetworkImage(
              imageUrl: cleanImage,
              fit: BoxFit.contain,
              fadeInDuration: const Duration(milliseconds: 120),
              placeholder: (_, __) => Icon(
                Icons.image_outlined,
                color: AppColors.primary.withOpacity(0.45),
                size: 28,
              ),
              errorWidget: (_, __, ___) => const Icon(
                Icons.image_not_supported_outlined,
                color: AppColors.primary,
                size: 28,
              ),
            ),
    );
  }
}

class _PedidoProducto {
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

  const _PedidoProducto({
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

  _PedidoProducto copyWith({
    int? productId,
    int? variationId,
    String? name,
    int? quantity,
    double? price,
    double? subtotal,
    double? total,
    double? taxTotal,
    String? sku,
    String? imageUrl,
    String? permalink,
  }) {
    return _PedidoProducto(
      productId: productId ?? this.productId,
      variationId: variationId ?? this.variationId,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      subtotal: subtotal ?? this.subtotal,
      total: total ?? this.total,
      taxTotal: taxTotal ?? this.taxTotal,
      sku: sku ?? this.sku,
      imageUrl: imageUrl ?? this.imageUrl,
      permalink: permalink ?? this.permalink,
    );
  }

  factory _PedidoProducto.fromOrderItem(OrderItem item) {
    return _PedidoProducto(
      productId: item.productId,
      variationId: item.variationId,
      name: item.name,
      quantity: item.quantity,
      price: item.price,
      subtotal: item.subtotal,
      total: item.total,
      taxTotal: item.taxTotal,
      sku: item.sku,
      imageUrl: item.imageUrl,
      permalink: item.permalink,
    );
  }

  factory _PedidoProducto.fromWooLineItem(Map<String, dynamic> json) {
    final subtotal = _parseDouble(json['subtotal']);
    final total = _parseDouble(json['total']);
    final price = _parseDouble(json['price'] ?? json['unit_price']);
    final taxTotal = _parseDouble(json['tax_total'] ?? json['tax'] ?? json['line_tax']);

    return _PedidoProducto(
      productId: _parseInt(json['product_id'] ?? json['productId'] ?? json['id_product']),
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

  static int _parseInt(dynamic value, {int fallback = 0}) {
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

class _TotalRowData {
  final String label;
  final String amount;
  final bool negative;

  const _TotalRowData(
    this.label,
    this.amount, {
    this.negative = false,
  });
}

class _MutedLine extends StatelessWidget {
  const _MutedLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: _muted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

Widget _buildSmallInfoChip(IconData icon, String label) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F8FA),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13.5, color: _muted),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10.8,
            color: _muted,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

Widget _buildStatusBadge(String status, {String? labelOverride}) {
  Color bgColor;
  Color textColor;
  String label;
  IconData icon;

  final normalized = status.toLowerCase().trim().replaceFirst(
        RegExp(r'^wc-'),
        '',
      );

  switch (normalized) {
    case 'completed':
      bgColor = const Color(0xFFEAF8EF);
      textColor = const Color(0xFF15803D);
      label = 'Completado';
      icon = Icons.check_circle_outline_rounded;
      break;
    case 'processing':
      bgColor = const Color(0xFFEAF2FF);
      textColor = const Color(0xFF1D4ED8);
      label = 'En proceso';
      icon = Icons.sync_rounded;
      break;
    case 'pending':
      bgColor = const Color(0xFFFFF4E5);
      textColor = const Color(0xFFD97706);
      label = 'Pendiente';
      icon = Icons.schedule_rounded;
      break;
    case 'ywraq-pending':
      bgColor = const Color(0xFFEAF2FF);
      textColor = const Color(0xFF1D4ED8);
      label = 'Presupuesto pendiente';
      icon = Icons.request_quote_outlined;
      break;
    case 'ywraq-accepted':
      bgColor = const Color(0xFFEAF8EF);
      textColor = const Color(0xFF15803D);
      label = 'Presupuesto aceptado';
      icon = Icons.check_circle_outline_rounded;
      break;
    case 'ywraq-rejected':
      bgColor = const Color(0xFFFFE8E8);
      textColor = const Color(0xFFB91C1C);
      label = 'Presupuesto rechazado';
      icon = Icons.cancel_outlined;
      break;
    case 'on-hold':
      bgColor = const Color(0xFFFFF7D6);
      textColor = const Color(0xFFB45309);
      label = 'En espera';
      icon = Icons.pause_circle_outline_rounded;
      break;
    case 'cancelled':
      bgColor = const Color(0xFFFFE8E8);
      textColor = const Color(0xFFDC2626);
      label = 'Cancelado';
      icon = Icons.cancel_outlined;
      break;
    case 'refunded':
      bgColor = const Color(0xFFF3E8FF);
      textColor = const Color(0xFF7E22CE);
      label = 'Reembolsado';
      icon = Icons.replay_circle_filled_outlined;
      break;
    case 'failed':
      bgColor = const Color(0xFFFFE8E8);
      textColor = const Color(0xFFB91C1C);
      label = 'Fallido';
      icon = Icons.error_outline_rounded;
      break;
    default:
      bgColor = const Color(0xFFF3F4F6);
      textColor = const Color(0xFF4B5563);
      label = _formatUnknownStatus(status);
      icon = Icons.info_outline_rounded;
  }

  final forcedLabel = labelOverride?.trim();
  if (forcedLabel != null && forcedLabel.isNotEmpty) {
    label = forcedLabel;
  }

  return Container(
    constraints: const BoxConstraints(maxWidth: 160),
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: textColor.withOpacity(0.08)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13.5, color: textColor),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 10.7,
              color: textColor,
            ),
          ),
        ),
      ],
    ),
  );
}

String _formatUnknownStatus(String status) {
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

String _formatMoney(double value) {
  return '${value.toStringAsFixed(2).replaceAll('.', ',')} €';
}

String _formatTotalString(String value) {
  final raw = value.trim();
  if (raw.isEmpty) return '0,00 €';
  if (raw.contains('€')) return raw;
  return '${raw.replaceAll('.', ',')} €';
}

double _moneyValue(String value) {
  final raw = value
      .trim()
      .replaceAll('€', '')
      .replaceAll(RegExp(r'\s+'), '');

  if (raw.isEmpty) return 0;

  if (raw.contains(',') && raw.contains('.')) {
    return double.tryParse(raw.replaceAll('.', '').replaceAll(',', '.')) ?? 0;
  }

  return double.tryParse(raw.replaceAll(',', '.')) ?? 0;
}

class _OrdersSummaryHeader extends StatelessWidget {
  const _OrdersSummaryHeader({
    required this.count,
  });

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _pageBg,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.025),
              blurRadius: 10,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(
                Icons.local_shipping_outlined,
                color: AppColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$count pedido${count != 1 ? 's' : ''}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: _dark,
                  fontFamily: 'Oswald',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrdersLoadingState extends StatelessWidget {
  const _OrdersLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          SizedBox(height: 16),
          Text(
            'Cargando pedidos...',
            style: TextStyle(
              color: _muted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductsLoadingCard extends StatelessWidget {
  const _ProductsLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: _softCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 2,
        ),
      ),
    );
  }
}

class _EmptyProductsCard extends StatelessWidget {
  const _EmptyProductsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _softCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: const Text(
        'Este pedido no tiene productos cargados.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _muted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

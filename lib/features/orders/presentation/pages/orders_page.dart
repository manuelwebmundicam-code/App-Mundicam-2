import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:mundicam/features/orders/data/models/order_model.dart';
import 'package:mundicam/features/cart/presentation/providers/cart_provider.dart';
import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/shared/widgets/professional_page_app_bar.dart';
import 'package:mundicam/shared/providers/badge_provider.dart';
import 'package:mundicam/features/orders/presentation/providers/order_provider.dart';
import 'package:mundicam/features/home/presentation/pages/home_page.dart';
import 'package:mundicam/features/rma/presentation/pages/rma_from_page.dart';

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
  final Set<int> _expandedOrderIds = <int>{};
  final Set<int> _repeatingOrderIds = <int>{};

  final Map<int, List<_PedidoProducto>> _itemsCache =
  <int, List<_PedidoProducto>>{};

  final Map<int, Future<List<_PedidoProducto>>> _itemsFutures =
  <int, Future<List<_PedidoProducto>>>{};

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
    setState(() {
      _expandedOrderIds.clear();
      _itemsCache.clear();
      _itemsFutures.clear();
    });

    ref.invalidate(ordersProvider);

    await Future<void>.delayed(const Duration(milliseconds: 250));
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
          if (orders.isEmpty) {
            return _buildEmptyState(context);
          }

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
    final bool isCompleted = order.status.toLowerCase() == 'completed';
    final bool isExpanded = _expandedOrderIds.contains(order.id);
    final bool isRepeating = _repeatingOrderIds.contains(order.id);

    final cachedItems = _itemsCache[order.id];
    final previewItems =
        cachedItems ?? order.items.map(_PedidoProducto.fromOrderItem).toList();

    final int totalUnidades = previewItems.fold<int>(
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
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: AppColors.primary.withOpacity(0.05),
          highlightColor: AppColors.primary.withOpacity(0.04),
        ),
        child: ExpansionTile(
          initiallyExpanded: isExpanded,
          tilePadding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: const RoundedRectangleBorder(side: BorderSide.none),
          collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
          iconColor: AppColors.primary,
          collapsedIconColor: const Color(0xFF9CA3AF),
          onExpansionChanged: (expanded) {
            setState(() {
              if (expanded) {
                _expandedOrderIds.add(order.id);
              } else {
                _expandedOrderIds.remove(order.id);
              }
            });

            if (expanded) {
              _loadFullOrderItems(order, forceRefresh: true);
            }
          },
          leading: _buildStatusBadge(order.status),
          title: Text(
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
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              DateFormat('dd/MM/yyyy · HH:mm').format(order.dateCreated),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _muted,
                fontSize: 11.8,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${order.total} €',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15.5,
                  color: AppColors.primary,
                  fontFamily: 'Oswald',
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedRotation(
                turns: isExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                child: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: Color(0xFF9CA3AF),
                ),
              ),
            ],
          ),
          children: [
            const Divider(height: 1, color: _border),
            const SizedBox(height: 14),
            Row(
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
                  'PRODUCTOS',
                  style: TextStyle(
                    fontSize: 11.2,
                    fontWeight: FontWeight.w900,
                    color: _dark,
                    letterSpacing: 0.6,
                    fontFamily: 'Oswald',
                  ),
                ),
                const Spacer(),
                Text(
                  '${previewItems.length} producto${previewItems.length != 1 ? 's' : ''} · '
                      '$totalUnidades ud${totalUnidades != 1 ? 's' : ''}',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildProductsContainer(order, isCompleted),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: isRepeating
                          ? null
                          : () => _repetirPedido(context, order),
                      icon: isRepeating
                          ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      )
                          : const Icon(Icons.replay_rounded, size: 17),
                      label: Text(
                        isRepeating ? 'CARGANDO...' : 'REPETIR PEDIDO',
                        style: const TextStyle(
                          fontSize: 11,
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
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductsContainer(OrderMundicam order, bool isCompleted) {
    return FutureBuilder<List<_PedidoProducto>>(
      future: _loadFullOrderItems(order),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !_itemsCache.containsKey(order.id)) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28),
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

        final items = snapshot.data ??
            _itemsCache[order.id] ??
            order.items.map(_PedidoProducto.fromOrderItem).toList();

        if (items.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
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

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: _softCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _border),
          ),
          child: Column(
            children: items.map((item) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          constraints: const BoxConstraints(minWidth: 34),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
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
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: const TextStyle(
                                  fontSize: 12.8,
                                  color: _dark,
                                  height: 1.25,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  item.total > 0
                                      ? '${_formatMoney(item.unitPrice)} / ud · ${_formatMoney(item.total)} total'
                                      : 'Producto del pedido',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: Colors.grey[500],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (isCompleted && item.productId > 0) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 36,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => RmaFormPage(
                                  orderId: order.id,
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
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Future<List<_PedidoProducto>> _loadFullOrderItems(
      OrderMundicam order, {
        bool forceRefresh = false,
      }) {
    if (!forceRefresh && _itemsCache.containsKey(order.id)) {
      return Future.value(_itemsCache[order.id]!);
    }

    if (!forceRefresh && _itemsFutures.containsKey(order.id)) {
      return _itemsFutures[order.id]!;
    }

    final future = _fetchFullOrderItems(order);
    _itemsFutures[order.id] = future;

    return future;
  }

  Future<List<_PedidoProducto>> _fetchFullOrderItems(
      OrderMundicam order,
      ) async {
    final fallbackItems = order.items
        .map(_PedidoProducto.fromOrderItem)
        .where((item) => item.name.trim().isNotEmpty)
        .toList();

    try {
      final api = ApiService();
      final orderData = await api.getOrdenCompleta(order.id.toString());

      final rawItems = orderData?['line_items'];
      final lineItems = rawItems is List ? rawItems : <dynamic>[];

      final fullItems = lineItems
          .whereType<Map>()
          .map(
            (item) => _PedidoProducto.fromWooLineItem(
          Map<String, dynamic>.from(item),
        ),
      )
          .where((item) => item.name.trim().isNotEmpty)
          .toList();

      final result = fullItems.isNotEmpty ? fullItems : fallbackItems;

      _itemsCache[order.id] = result;

      return result;
    } catch (_) {
      _itemsCache[order.id] = fallbackItems;
      return fallbackItems;
    } finally {
      _itemsFutures.remove(order.id);
    }
  }

  Future<void> _repetirPedido(
      BuildContext context,
      OrderMundicam order,
      ) async {
    if (_repeatingOrderIds.contains(order.id)) return;

    setState(() {
      _repeatingOrderIds.add(order.id);
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

      final api = ApiService();
      final items = await _loadFullOrderItems(order, forceRefresh: true);

      if (items.isEmpty) {
        throw Exception('Este pedido no tiene productos para repetir.');
      }

      int productosAnadidos = 0;
      int unidadesAnadidas = 0;
      int productosSinStock = 0;
      int productosNoEncontrados = 0;

      for (final item in items) {
        if (item.productId <= 0) {
          productosNoEncontrados++;
          continue;
        }

        final producto = await api.getProductoById(item.productId);

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

      if (context.mounted && dialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogOpen = false;
      }

      if (!context.mounted) return;

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
                ? '✅ $productosAnadidos producto${productosAnadidos != 1 ? 's' : ''} '
                'añadido${productosAnadidos != 1 ? 's' : ''} al carrito '
                '($unidadesAnadidas ud). '
                '$skipped producto${skipped != 1 ? 's' : ''} no disponible${skipped != 1 ? 's' : ''}.'
                : '✅ $productosAnadidos producto${productosAnadidos != 1 ? 's' : ''} '
                'añadido${productosAnadidos != 1 ? 's' : ''} al carrito '
                '($unidadesAnadidas ud).',
          ),
          backgroundColor:
          skipped > 0 ? Colors.orange.shade700 : Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (context.mounted && dialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogOpen = false;
      }

      if (!context.mounted) return;

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
          _repeatingOrderIds.remove(order.id);
        });
      }

      if (context.mounted && dialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  Widget _buildStatusBadge(String status) {
    Color bgColor;
    Color textColor;
    String label;
    IconData icon;

    switch (status.toLowerCase()) {
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

    return Container(
      constraints: const BoxConstraints(maxWidth: 104),
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

  String _formatMoney(double value) {
    return '${value.toStringAsFixed(2).replaceAll('.', ',')} €';
  }
}

class _PedidoProducto {
  final int productId;
  final String name;
  final int quantity;
  final double total;

  const _PedidoProducto({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.total,
  });

  double get unitPrice {
    if (quantity <= 0) return total;
    return total / quantity;
  }

  factory _PedidoProducto.fromOrderItem(OrderItem item) {
    return _PedidoProducto(
      productId: item.productId,
      name: item.name,
      quantity: item.quantity,
      total: item.total,
    );
  }

  factory _PedidoProducto.fromWooLineItem(Map<String, dynamic> json) {
    final subtotal = _parseDouble(json['subtotal']);
    final total = _parseDouble(json['total']);

    return _PedidoProducto(
      productId: _parseInt(json['product_id'] ?? json['productId']),
      name: _cleanText(json['name']?.toString() ?? 'Producto'),
      quantity: _parseInt(
        json['quantity'] ?? json['qty'],
        fallback: 1,
      ),
      total: total > 0 ? total : subtotal,
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

  static String _cleanText(String value) {
    return value.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }
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

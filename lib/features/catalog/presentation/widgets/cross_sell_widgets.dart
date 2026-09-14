import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/features/cart/presentation/providers/cart_provider.dart';
import 'package:mundicam/features/catalog/data/models/producto.dart';
import 'package:mundicam/shared/theme/app_theme.dart';

Future<void> showMundicamCrossSellSheet({
  required BuildContext context,
  required WidgetRef ref,
  required Product sourceProduct,
  VoidCallback? onGoCart,
}) async {
  if (sourceProduct.id <= 0) return;

  final cartNotifier = ref.read(cartProvider.notifier);

  // Un carrito preparado desde presupuesto mantiene un flujo cerrado.
  // No añadimos complementos que alteren lo aceptado en el presupuesto.
  if (cartNotifier.hasQuoteSource) return;

  final products = await ApiService().getCrossSells(
    productId: sourceProduct.id,
    limit: 4,
  );

  if (!context.mounted || products.isEmpty) return;

  final cartIds = ref.read(cartProvider).map((item) => item.product.id).toSet();
  final available = products
      .where((product) =>
          product.id > 0 &&
          product.id != sourceProduct.id &&
          product.canAddToCart &&
          !cartIds.contains(product.id))
      .take(4)
      .toList();

  if (available.isEmpty) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.45),
    builder: (sheetContext) => _CrossSellBottomSheet(
      products: available,
      onGoCart: onGoCart,
    ),
  );
}

class _CrossSellBottomSheet extends ConsumerStatefulWidget {
  final List<Product> products;
  final VoidCallback? onGoCart;

  const _CrossSellBottomSheet({
    required this.products,
    this.onGoCart,
  });

  @override
  ConsumerState<_CrossSellBottomSheet> createState() =>
      _CrossSellBottomSheetState();
}

class _CrossSellBottomSheetState
    extends ConsumerState<_CrossSellBottomSheet> {
  final Set<int> _addedIds = <int>{};

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F9FB),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD1D5DB),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF7EE),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Color(0xFF218047),
                    size: 25,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Producto añadido',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF218047),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Completa tu instalación',
                        style: TextStyle(
                          fontFamily: 'Oswald',
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Complementos configurados para este producto',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Cerrar',
                ),
              ],
            ),
          ),
          Flexible(
            child: SizedBox(
              height: 276,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: widget.products.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final product = widget.products[index];
                  final added = _addedIds.contains(product.id);
                  return _CrossSellCard(
                    product: product,
                    added: added,
                    onAdd: added
                        ? null
                        : () {
                            ref
                                .read(cartProvider.notifier)
                                .addProduct(product, 1);
                            HapticFeedback.mediumImpact();
                            setState(() => _addedIds.add(product.id));
                          },
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: Color(0xFFD9DEE7)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: const Text(
                        'SEGUIR COMPRANDO',
                        style: TextStyle(
                          fontFamily: 'Oswald',
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        final goCart = widget.onGoCart;
                        if (goCart != null) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            goCart();
                          });
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      icon: const Icon(Icons.shopping_cart_outlined, size: 18),
                      label: Text(
                        widget.onGoCart != null ? 'IR AL CARRITO' : 'CERRAR',
                        style: const TextStyle(
                          fontFamily: 'Oswald',
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CrossSellCard extends StatelessWidget {
  final Product product;
  final bool added;
  final VoidCallback? onAdd;

  const _CrossSellCard({
    required this.product,
    required this.added,
    required this.onAdd,
  });

  String _formatPrice(double value) {
    if (value <= 0) return 'Bajo consulta';
    return '${value.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 172,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D111827),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 98,
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.all(9),
            child: CachedNetworkImage(
              imageUrl: product.imageUrl,
              fit: BoxFit.contain,
              placeholder: (_, __) => const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              errorWidget: (_, __, ___) => const Icon(
                Icons.image_not_supported_outlined,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.15,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (product.sku.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'REF: ${product.sku.trim()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 8.8,
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    _formatPrice(product.priceValue),
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: 'Oswald',
                      fontSize: product.priceValue > 0 ? 19 : 13,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 7),
                  SizedBox(
                    width: double.infinity,
                    height: 34,
                    child: ElevatedButton.icon(
                      onPressed: onAdd,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            added ? const Color(0xFFEAF7EE) : AppColors.primary,
                        foregroundColor:
                            added ? const Color(0xFF218047) : Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                      ),
                      icon: Icon(
                        added ? Icons.check_rounded : Icons.add_shopping_cart,
                        size: 15,
                      ),
                      label: Text(
                        added ? 'AÑADIDO' : 'AÑADIR',
                        style: const TextStyle(
                          fontFamily: 'Oswald',
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CartCrossSellSection extends ConsumerStatefulWidget {
  final List<CartItem> cartItems;
  final bool disabled;

  const CartCrossSellSection({
    super.key,
    required this.cartItems,
    this.disabled = false,
  });

  @override
  ConsumerState<CartCrossSellSection> createState() =>
      _CartCrossSellSectionState();
}

class _CartCrossSellSectionState extends ConsumerState<CartCrossSellSection> {
  Future<List<Product>>? _future;
  String _signature = '';

  @override
  void initState() {
    super.initState();
    _refreshFuture();
  }

  @override
  void didUpdateWidget(covariant CartCrossSellSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newSignature = _buildSignature(widget.cartItems, widget.disabled);
    if (newSignature != _signature) {
      _refreshFuture();
    }
  }

  String _buildSignature(List<CartItem> items, bool disabled) {
    if (disabled) return 'disabled';
    final ids = items.map((item) => item.product.id).where((id) => id > 0).toList()
      ..sort();
    return ids.join(',');
  }

  void _refreshFuture() {
    _signature = _buildSignature(widget.cartItems, widget.disabled);
    _future = widget.disabled || widget.cartItems.isEmpty
        ? Future<List<Product>>.value(const <Product>[])
        : _loadCrossSells(widget.cartItems);
  }

  Future<List<Product>> _loadCrossSells(List<CartItem> cartItems) async {
    final existingIds = cartItems.map((item) => item.product.id).toSet();
    final sourceIds = existingIds.where((id) => id > 0).take(6).toList();
    if (sourceIds.isEmpty) return const <Product>[];

    final api = ApiService();
    final groups = await Future.wait(
      sourceIds.map(
        (productId) => api.getCrossSells(productId: productId, limit: 4),
      ),
    );

    final unique = <int, Product>{};
    for (final group in groups) {
      for (final product in group) {
        if (product.id <= 0 ||
            existingIds.contains(product.id) ||
            !product.canAddToCart) {
          continue;
        }
        unique.putIfAbsent(product.id, () => product);
        if (unique.length >= 6) break;
      }
      if (unique.length >= 6) break;
    }

    return unique.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.disabled || widget.cartItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<List<Product>>(
      future: _future,
      builder: (context, snapshot) {
        final products = snapshot.data ?? const <Product>[];
        if (snapshot.connectionState == ConnectionState.waiting || products.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.only(top: 2, bottom: 8),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE8E8E8)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.add_circle_outline_rounded,
                    size: 19,
                    color: AppColors.primary,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'También puedes necesitar',
                      style: TextStyle(
                        fontFamily: 'Oswald',
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Complementos configurados para los productos de tu cesta',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 224,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: products.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final product = products[index];
                    return _CartCrossSellCard(
                      product: product,
                      onAdd: () {
                        ref.read(cartProvider.notifier).addProduct(product, 1);
                        HapticFeedback.mediumImpact();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CartCrossSellCard extends StatelessWidget {
  final Product product;
  final VoidCallback onAdd;

  const _CartCrossSellCard({
    required this.product,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 158,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 74,
            width: double.infinity,
            child: CachedNetworkImage(
              imageUrl: product.imageUrl,
              fit: BoxFit.contain,
              errorWidget: (_, __, ___) => const Icon(
                Icons.image_not_supported_outlined,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            product.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.8,
              height: 1.15,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          Text(
            '${product.priceValue.toStringAsFixed(2).replaceAll('.', ',')} €',
            maxLines: 1,
            style: const TextStyle(
              fontFamily: 'Oswald',
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: 32,
            child: ElevatedButton.icon(
              onPressed: onAdd,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.add_shopping_cart, size: 14),
              label: const Text(
                'AÑADIR',
                style: TextStyle(
                  fontFamily: 'Oswald',
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

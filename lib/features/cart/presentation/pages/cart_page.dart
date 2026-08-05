import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mundicam/shared/widgets/professional_page_app_bar.dart';
import 'package:mundicam/core/analytics/mundicam_analytics_service.dart';
import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/features/cart/presentation/providers/cart_provider.dart';
import 'package:mundicam/features/checkout/presentation/pages/checkout_page.dart';
import 'package:mundicam/features/quotes/data/models/local_quote_model.dart';
import 'package:mundicam/features/quotes/presentation/providers/local_quote_provider.dart';

class CartPage extends ConsumerWidget {
  final VoidCallback? onGoHome;
  final VoidCallback? onGoBack;
  final VoidCallback? onGoQuotes;

  const CartPage({
    super.key,
    this.onGoHome,
    this.onGoBack,
    this.onGoQuotes,
  });

  void _handleBack(BuildContext context) {
    if (onGoBack != null) {
      onGoBack!();
      return;
    }
    if (onGoHome != null) {
      onGoHome!();
      return;
    }
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  void _goToHome(BuildContext context) {
    if (onGoHome != null) {
      onGoHome!();
      return;
    }
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  Future<void> _cancelarPedidoYVolverAPresupuesto(
    BuildContext context,
    WidgetRef ref,
    List<CartItem> cartItems,
  ) async {
    if (cartItems.isEmpty) return;

    final cartNotifier = ref.read(cartProvider.notifier);
    final hasOriginalQuote = cartNotifier.hasQuoteSource;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          'Cancelar tramitación',
          style: TextStyle(
            fontFamily: 'Oswald',
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          hasOriginalQuote
              ? 'Se vaciará la cesta. El presupuesto original seguirá guardado '
                  'en Presupuestos y podrás retomarlo más tarde.'
              : 'Se sacarán estos productos de la cesta y se guardarán como un '
                  'presupuesto local para retomarlo más tarde.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('NO'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('SÍ, VOLVER A PRESUPUESTOS'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    String message;
    if (hasOriginalQuote) {
      await cartNotifier.clearCart();
      message = 'El presupuesto original sigue guardado.';
    } else {
      final orderId = DateTime.now().millisecondsSinceEpoch.toString();
      final nombre = 'Presupuesto #$orderId';
      final quoteNotifier = ref.read(localQuotesProvider.notifier);

      await quoteNotifier.crearPresupuesto(
        orderId: orderId,
        nombre: nombre,
      );

      for (final item in cartItems) {
        final price = double.tryParse(
              item.product.price.replaceAll(',', '.'),
            ) ??
            0;
        await quoteNotifier.anadirItem(
          orderId: orderId,
          item: LocalQuoteItem(
            productId: item.product.id,
            productName: item.product.name,
            quantity: item.quantity,
            price: price,
          ),
        );
      }

      await cartNotifier.clearCart();
      message = 'Presupuesto guardado: $nombre';
    }

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF1565C0),
      ),
    );

    if (onGoQuotes != null) {
      onGoQuotes!();
    } else {
      _handleBack(context);
    }
  }


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    MundicamAnalyticsService.instance
        .trackScreenViewForRoute(context, 'cart');
    final cartItems = ref.watch(cartProvider);
    final totalUnits = cartItems.fold<int>(
      0,
          (sum, item) => sum + item.quantity,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: ProfessionalPageAppBar(
        title: 'MI CESTA',
        subtitle: '',
        icon: Icons.shopping_cart_outlined,
        onBack: () => _handleBack(context),
      ),
      body: cartItems.isEmpty
          ? _buildEmptyCart(context)
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
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
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9EEEE),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.shopping_cart_outlined,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      cartItems.length == 1
                          ? '1 producto'
                          : '${cartItems.length} productos',
                      style: const TextStyle(
                        fontFamily: 'Oswald',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F3F6),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$totalUnits uds.',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6C778A),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              physics: const BouncingScrollPhysics(),
              itemCount: cartItems.length,
              itemBuilder: (context, index) {
                final item = cartItems[index];
                final price = double.tryParse(
                  item.product.price.replaceAll(',', '.'),
                ) ??
                    0;
                return _buildProductItem(ref, item, price);
              },
            ),
          ),
          _buildCheckoutSection(ref, context),
        ],
      ),
    );
  }

  Widget _buildProductItem(WidgetRef ref, CartItem item, double price) {
    final total = price * item.quantity;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: const Color(0xFFF8F8F8),
                border: Border.all(color: const Color(0xFFEEEEEE)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: CachedNetworkImage(
                  imageUrl: item.product.imageUrl,
                  fit: BoxFit.contain,
                  placeholder: (context, url) => Container(
                    color: const Color(0xFFF4F4F4),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: const Color(0xFFF4F4F4),
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: SizedBox(
                height: 108,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item.product.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              height: 1.15,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            ref
                                .read(cartProvider.notifier)
                                .removeProduct(item.product.id);
                            HapticFeedback.lightImpact();
                          },
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFBECEC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFF2DADA),
                              ),
                            ),
                            child: const Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${price.toStringAsFixed(2)} €/ud.',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            '${total.toStringAsFixed(2)} €',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                              fontFamily: 'Oswald',
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            _qtyBtn(
                              icon: Icons.remove,
                              onTap: () {
                                if (item.quantity > 1) {
                                  ref
                                      .read(cartProvider.notifier)
                                      .updateQuantity(
                                    item.product.id,
                                    item.quantity - 1,
                                  );
                                } else {
                                  ref
                                      .read(cartProvider.notifier)
                                      .removeProduct(item.product.id);
                                }
                                HapticFeedback.selectionClick();
                              },
                            ),
                            SizedBox(
                              width: 34,
                              child: Text(
                                '${item.quantity}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            _qtyBtn(
                              icon: Icons.add,
                              onTap: () {
                                ref
                                    .read(cartProvider.notifier)
                                    .updateQuantity(
                                  item.product.id,
                                  item.quantity + 1,
                                );
                                HapticFeedback.selectionClick();
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _qtyBtn({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: const Color(0xFFF9EEEE),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFF0D9D9)),
        ),
        child: Icon(
          icon,
          size: 18,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildCheckoutSection(WidgetRef ref, BuildContext context) {
    final cartItems = ref.watch(cartProvider);

    final subtotal = cartItems.fold<double>(
      0,
          (sum, item) {
        final price = double.tryParse(
          item.product.price.replaceAll(',', '.'),
        ) ??
            0;
        return sum + (price * item.quantity);
      },
    );

    final iva = subtotal * 0.21;
    final total = subtotal + iva;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _summaryRow(
              'Base imponible',
              '${subtotal.toStringAsFixed(2)} €',
            ),
            const SizedBox(height: 10),
            _summaryRow(
              'IVA (21%) incluido',
              '${iva.toStringAsFixed(2)} €',
            ),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 16),
              height: 1,
              color: const Color(0xFFE8E8E8),
            ),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'TOTAL',
                    style: TextStyle(
                      fontFamily: 'Oswald',
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '${total.toStringAsFixed(2)} €',
                  style: const TextStyle(
                    fontFamily: 'Oswald',
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: cartItems.isEmpty
                    ? null
                    : () async {
                  final result = await Navigator.of(context).push<CheckoutExitAction>(
                    MaterialPageRoute<CheckoutExitAction>(
                      builder: (_) => const CheckoutPage(),
                    ),
                  );

                  if (result == CheckoutExitAction.returnToQuotes && context.mounted) {
                    if (onGoQuotes != null) {
                      onGoQuotes!();
                    } else if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.inventory_2_outlined, size: 20),
                label: const Text(
                  'TRAMITAR PEDIDO',
                  style: TextStyle(
                    fontFamily: 'Oswald',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: cartItems.isEmpty
                    ? null
                    : () => _cancelarPedidoYVolverAPresupuesto(
                          context,
                          ref,
                          cartItems,
                        ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary, width: 1.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.undo_rounded, size: 20),
                label: const Text(
                  'CANCELAR Y VOLVER A PRESUPUESTOS',
                  style: TextStyle(
                    fontFamily: 'Oswald',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyCart(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shopping_cart_outlined,
              size: 76,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 18),
            const Text(
              'Tu cesta está vacía',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Oswald',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Añade productos desde el catálogo para preparar tu pedido.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 26),
            SizedBox(
              width: 210,
              height: 52,
              child: ElevatedButton(
                onPressed: () => _goToHome(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'VOLVER A LA TIENDA',
                  style: TextStyle(
                    fontFamily: 'Oswald',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
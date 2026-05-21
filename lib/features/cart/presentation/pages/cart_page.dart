import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/features/cart/presentation/providers/cart_provider.dart';
import 'package:mundicam/features/checkout/presentation/pages/checkout_page.dart';

class CartPage extends ConsumerWidget {
  final VoidCallback? onGoHome;
  final VoidCallback? onGoBack;

  const CartPage({
    super.key,
    this.onGoHome,
    this.onGoBack,
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartItems = ref.watch(cartProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 64,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => _handleBack(context),
        ),
        title: const Text(
          'MI CESTA',
          style: TextStyle(
            color: Colors.white,
            fontFamily: 'Oswald',
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        ),
      ),
      body: cartItems.isEmpty
          ? _buildEmptyCart(context)
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: _buildCartSummaryCard(cartItems),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
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

  Widget _buildCartSummaryCard(List<CartItem> cartItems) {
    final totalUnits = cartItems.fold<int>(
      0,
          (sum, item) => sum + item.quantity,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE7E7E7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFF8EAEA),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.shopping_cart_outlined,
              color: AppColors.primary,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${cartItems.length} producto${cartItems.length == 1 ? '' : 's'}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                fontFamily: 'Oswald',
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F2F5),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$totalUnits uds.',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF697386),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductItem(WidgetRef ref, CartItem item, double price) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE7E7E7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Stack(
            children: [
              Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F5F7),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE7E7E7)),
                ),
                clipBehavior: Clip.antiAlias,
                child: CachedNetworkImage(
                  imageUrl: item.product.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.grey,
                    size: 30,
                  ),
                ),
              ),
              Positioned(
                top: 6,
                left: 6,
                child: GestureDetector(
                  onTap: () {
                    ref
                        .read(cartProvider.notifier)
                        .removeProduct(item.product.id);
                    HapticFeedback.lightImpact();
                  },
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(9),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      size: 17,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.product.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                      color: AppColors.textPrimary,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '${price.toStringAsFixed(2)} €/ud.',
                    style: const TextStyle(
                      color: Color(0xFF7A7A7A),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '${(price * item.quantity).toStringAsFixed(2)} €',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      fontFamily: 'Oswald',
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 38,
            padding: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FB),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE7E7E7)),
            ),
            child: Column(
              children: [
                _qtyBtn(
                  icon: Icons.add_rounded,
                  onTap: () => ref
                      .read(cartProvider.notifier)
                      .updateQuantity(item.product.id, item.quantity + 1),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '${item.quantity}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: AppColors.textPrimary,
                      fontFamily: 'Oswald',
                    ),
                  ),
                ),
                _qtyBtn(
                  icon: Icons.remove_rounded,
                  onTap: () {
                    if (item.quantity <= 1) {
                      ref
                          .read(cartProvider.notifier)
                          .removeProduct(item.product.id);
                    } else {
                      ref
                          .read(cartProvider.notifier)
                          .updateQuantity(item.product.id, item.quantity - 1);
                    }
                    HapticFeedback.lightImpact();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _qtyBtn({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: const Color(0xFFF8EAEA),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 18,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildEmptyCart(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.shopping_cart_outlined,
                size: 66,
                color: Colors.grey.shade300,
              ),
            ),
            const SizedBox(height: 26),
            const Text(
              'Tu cesta está vacía',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                fontFamily: 'Oswald',
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Añade productos desde el catálogo para preparar tu pedido.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF8A8A8A),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 26),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () => _goToHome(context),
                icon: const Icon(
                  Icons.storefront_outlined,
                  size: 18,
                  color: Colors.white,
                ),
                label: const Text(
                  'VOLVER A LA TIENDA',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: Colors.white,
                    fontFamily: 'Oswald',
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 26),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckoutSection(WidgetRef ref, BuildContext context) {
    final notifier = ref.watch(cartProvider.notifier);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(26),
            topRight: Radius.circular(26),
          ),
          border: const Border(
            top: BorderSide(color: Color(0xFFE7E7E7)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _priceRow(
              'Base imponible',
              '${notifier.subtotal.toStringAsFixed(2)} €',
            ),
            const SizedBox(height: 6),
            _priceRow(
              'IVA (21%) incluido',
              '${notifier.iva.toStringAsFixed(2)} €',
            ),
            const SizedBox(height: 12),
            Container(
              height: 1,
              color: const Color(0xFFEDEDED),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'TOTAL',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: AppColors.textPrimary,
                    fontFamily: 'Oswald',
                  ),
                ),
                Text(
                  '${notifier.total.toStringAsFixed(2)} €',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 24,
                    color: AppColors.primary,
                    fontFamily: 'Oswald',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const CheckoutPage(),
                    ),
                  );
                },
                icon: const Icon(
                  Icons.assignment_turned_in_outlined,
                  size: 18,
                  color: Colors.white,
                ),
                label: const Text(
                  'TRAMITAR PEDIDO',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: Colors.white,
                    fontFamily: 'Oswald',
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _priceRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
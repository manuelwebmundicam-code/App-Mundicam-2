import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mundicam/features/cart/presentation/providers/cart_provider.dart';
import 'package:mundicam/features/quotes/presentation/providers/quote_provider.dart';

/// Provider que calcula el número total de items en el carrito
final cartBadgeProvider = Provider<int>((ref) {
  final cartItems = ref.watch(cartProvider);
  // cartProvider es StateNotifierProvider, devuelve List<CartItem> directamente
  return cartItems.fold(0, (sum, item) => sum + item.quantity);
});

/// Provider que calcula el número de presupuestos pendientes
final quoteBadgeProvider = Provider<int>((ref) {
  final quotesAsync = ref.watch(quotesProvider);
  // quotesProvider es FutureProvider, devuelve AsyncValue
  return quotesAsync.when(
    data: (quotes) => quotes.length,
    loading: () => 0,
    error: (error, stackTrace) => 0,
  );
});

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mundicam/features/cart/presentation/providers/cart_provider.dart';
import 'package:mundicam/features/quotes/presentation/providers/quote_provider.dart';
import 'package:mundicam/features/quotes/presentation/providers/local_quote_provider.dart';

/// Provider que calcula el número total de items en el carrito
final cartBadgeProvider = Provider<int>((ref) {
  final cartItems = ref.watch(cartProvider);
  // cartProvider es StateNotifierProvider, devuelve List<CartItem> directamente
  return cartItems.fold(0, (sum, item) => sum + item.quantity);
});

/// Provider que calcula el número de presupuestos pendientes.
/// Suma presupuestos web y presupuestos locales activos para que el usuario
/// vea el contador igual que en el carrito.
final quoteBadgeProvider = Provider<int>((ref) {
  final localQuotes = ref.watch(localQuotesProvider);
  final localCount = localQuotes.where((quote) => !quote.isExpired).length;
  final quotesAsync = ref.watch(quotesProvider);
  final webCount = quotesAsync.maybeWhen(
    data: (quotes) => quotes.length,
    orElse: () => 0,
  );

  return localCount + webCount;
});

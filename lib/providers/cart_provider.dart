import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../features/catalog/data/models/producto.dart';

class CartItem {
  final Product product;
  int quantity;

  CartItem({required this.product, this.quantity = 1});

  Map<String, dynamic> toJson() => {
    'product': product.toJson(),
    'quantity': quantity,
  };

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      product: Product.fromJson(json['product']),
      quantity: json['quantity'],
    );
  }
}

class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super([]) {
    _loadCart();
  }

  Future<void> _saveCart() async {
    final prefs = await SharedPreferences.getInstance();
    final String encodedData = jsonEncode(
      state.map((item) => item.toJson()).toList(),
    );
    await prefs.setString('cart_mundicam_data', encodedData);
  }

  Future<void> _loadCart() async {
    final prefs = await SharedPreferences.getInstance();
    final String? savedData = prefs.getString('cart_mundicam_data');
    if (savedData != null) {
      try {
        final List<dynamic> decodedData = jsonDecode(savedData);
        state = decodedData.map((item) => CartItem.fromJson(item)).toList();
      } catch (e) {
        state = [];
      }
    }
  }

  void addProduct(Product product, int qty) {
    final index = state.indexWhere((item) => item.product.id == product.id);
    if (index != -1) {
      state = [
        for (final item in state)
          if (item.product.id == product.id)
            CartItem(product: item.product, quantity: item.quantity + qty)
          else
            item,
      ];
    } else {
      state = [...state, CartItem(product: product, quantity: qty)];
    }
    _saveCart();
  }

  void removeProduct(int productId) {
    state = state.where((item) => item.product.id != productId).toList();
    _saveCart();
  }

  void updateQuantity(int productId, int newQty) {
    if (newQty <= 0) {
      removeProduct(productId);
      return;
    }
    state = [
      for (final item in state)
        if (item.product.id == productId)
          CartItem(product: item.product, quantity: newQty)
        else
          item,
    ];
    _saveCart();
  }

  void clearCart() {
    state = [];
    _saveCart();
  }

  // --- CÁLCULOS CORREGIDOS (IVA INCLUIDO) ---

  /// El TOTAL es la suma directa de los precios de los productos multiplicados por su cantidad.
  double get total => state.fold(0, (sum, item) {
    double price =
        double.tryParse(item.product.price.replaceAll(',', '.')) ?? 0;
    return sum + (price * item.quantity);
  });

  /// El SUBTOTAL es la base imponible (Total dividido por 1.21).
  double get subtotal => total / 1.21;

  /// El IVA es la parte del impuesto ya incluida en el total.
  double get iva => total - subtotal;
}

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>((ref) {
  return CartNotifier();
});

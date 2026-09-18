import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/core/analytics/mundicam_analytics_service.dart';
import 'package:mundicam/features/catalog/data/models/producto.dart';

class CartItem {
  final Product product;
  final int quantity;

  const CartItem({
    required this.product,
    this.quantity = 1,
  });

  Map<String, dynamic> toJson() => {
    'product': product.toJson(),
    'quantity': quantity,
  };

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      product: Product.fromJson(
        Map<String, dynamic>.from(json['product'] as Map),
      ),
      quantity: _parseInt(json['quantity'], fallback: 1),
    );
  }

  static int _parseInt(dynamic value, {int fallback = 1}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();

    final raw = value.toString().trim();
    if (raw.isEmpty) return fallback;

    return int.tryParse(raw) ?? double.tryParse(raw)?.toInt() ?? fallback;
  }
}

class CartCouponState {
  final CouponValidationResult? result;
  final String cartSignature;

  const CartCouponState({
    this.result,
    this.cartSignature = '',
  });

  bool matches(List<CartItem> items) {
    return result?.success == true &&
        cartSignature.isNotEmpty &&
        cartSignature == cartItemsSignature(items);
  }
}

String cartItemsSignature(Iterable<CartItem> items) {
  final rows = items
      .map((item) => '${item.product.id}:${item.quantity}')
      .toList()
    ..sort();
  return rows.join('|');
}

final cartCouponProvider = StateProvider<CartCouponState>(
  (ref) => const CartCouponState(),
);

class CartNotifier extends StateNotifier<List<CartItem>> {
  static const String _sourceTypeKey = 'mundicam_cart_source_type';
  static const String _sourceQuoteIdKey = 'mundicam_cart_source_quote_id';
  static const String _sourceLocalUuidKey = 'mundicam_cart_source_local_uuid';

  String _sourceType = '';
  int _sourceQuoteId = 0;
  String _sourceLocalQuoteUuid = '';

  bool _remoteSyncInProgress = false;
  bool _localStateLoaded = false;

  CartNotifier() : super([]) {
    unawaited(_initializeCart());
  }

  Future<void> _initializeCart() async {
    await _loadCart();
    _localStateLoaded = true;
    if (!hasQuoteSource) {
      await syncFromRemoteCart();
    }
  }

  Future<void> _saveCart() async {
    final prefs = await SharedPreferences.getInstance();

    final validItems = state.where((item) {
      return item.product.id > 0 &&
          item.quantity > 0 &&
          item.product.canAddToCart;
    }).toList();

    final encodedData = jsonEncode(
      validItems.map((item) => item.toJson()).toList(),
    );

    await prefs.setString('cart_mundicam_data', encodedData);

    _debugCart('GUARDADO');
  }

  Future<void> _loadCart() async {
    final prefs = await SharedPreferences.getInstance();
    _sourceType = prefs.getString(_sourceTypeKey) ?? '';
    _sourceQuoteId = prefs.getInt(_sourceQuoteIdKey) ?? 0;
    _sourceLocalQuoteUuid = prefs.getString(_sourceLocalUuidKey) ?? '';
    final savedData = prefs.getString('cart_mundicam_data');

    if (savedData == null || savedData.trim().isEmpty) {
      state = [];
      return;
    }

    try {
      final decodedData = jsonDecode(savedData);

      if (decodedData is! List) {
        state = [];
        return;
      }

      state = decodedData
          .whereType<Map>()
          .map(
            (item) => CartItem.fromJson(
          Map<String, dynamic>.from(item),
        ),
      )
          .where((item) => item.product.id > 0)
          .where((item) => item.quantity > 0)
          .where((item) => item.product.canAddToCart)
          .toList();

      _debugCart('CARGADO');
    } catch (e) {
      debugPrint('❌ Error cargando carrito: $e');
      state = [];
    }
  }

  /// Sincroniza el carrito persistente del usuario autenticado con Flutter.
  ///
  /// No se ejecuta sobre un carrito procedente de presupuesto para no perder
  /// su origen ni los precios aprobados. Si el endpoint falla, se conserva el
  /// carrito local actual y no se bloquea la compra.
  Future<bool> syncFromRemoteCart() async {
    if (!_localStateLoaded || _remoteSyncInProgress || hasQuoteSource) {
      return false;
    }

    _remoteSyncInProgress = true;
    try {
      final rawItems = await ApiService().getRemoteCartItems();
      if (rawItems == null) return false;

      final remoteItems = <CartItem>[];
      for (final raw in rawItems) {
        final productId = _parseRemoteInt(
          raw['product_id'] ?? raw['id'],
        );
        final quantity = _parseRemoteInt(raw['quantity'], fallback: 1);
        if (productId <= 0 || quantity <= 0) continue;

        final productJson = <String, dynamic>{
          ...raw,
          'id': productId,
        };
        final product = Product.fromJson(productJson);
        if (product.id <= 0 || !product.canAddToCart) continue;

        remoteItems.add(CartItem(product: product, quantity: quantity));
      }

      state = remoteItems;
      await _saveCart();

      if (kDebugMode) {
        debugPrint('✅ Carrito Web ↔ App sincronizado: ${remoteItems.length} líneas');
      }
      return true;
    } finally {
      _remoteSyncInProgress = false;
    }
  }

  static int _parseRemoteInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    final raw = value?.toString().trim() ?? '';
    return int.tryParse(raw) ?? double.tryParse(raw)?.toInt() ?? fallback;
  }

  int get sourceQuoteId => _sourceType == 'web_quote' ? _sourceQuoteId : 0;

  String get sourceLocalQuoteUuid =>
      _sourceType == 'local_quote' ? _sourceLocalQuoteUuid : '';

  bool get hasQuoteSource =>
      sourceQuoteId > 0 || sourceLocalQuoteUuid.trim().isNotEmpty;

  Future<void> replaceCartFromQuote({
    required List<CartItem> items,
    int sourceQuoteId = 0,
    String sourceLocalQuoteUuid = '',
  }) async {
    final cleanItems = items
        .where((item) =>
            item.product.id > 0 &&
            item.quantity > 0 &&
            item.product.canAddToCart)
        .toList();

    _sourceType = sourceQuoteId > 0
        ? 'web_quote'
        : (sourceLocalQuoteUuid.trim().isNotEmpty ? 'local_quote' : '');
    _sourceQuoteId = sourceQuoteId > 0 ? sourceQuoteId : 0;
    _sourceLocalQuoteUuid =
        sourceLocalQuoteUuid.trim().isNotEmpty ? sourceLocalQuoteUuid.trim() : '';

    state = cleanItems;
    await _saveCart();

    final prefs = await SharedPreferences.getInstance();
    if (_sourceType.isEmpty) {
      await prefs.remove(_sourceTypeKey);
      await prefs.remove(_sourceQuoteIdKey);
      await prefs.remove(_sourceLocalUuidKey);
    } else {
      await prefs.setString(_sourceTypeKey, _sourceType);
      await prefs.setInt(_sourceQuoteIdKey, _sourceQuoteId);
      await prefs.setString(_sourceLocalUuidKey, _sourceLocalQuoteUuid);
    }
  }

  Future<void> clearQuoteSource() async {
    _sourceType = '';
    _sourceQuoteId = 0;
    _sourceLocalQuoteUuid = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sourceTypeKey);
    await prefs.remove(_sourceQuoteIdKey);
    await prefs.remove(_sourceLocalUuidKey);
  }

  void addProduct(Product product, int qty) {
    final safeQty = qty <= 0 ? 1 : qty;

    debugPrint('🛒 AÑADIENDO PRODUCTO AL CARRITO');
    debugPrint('➡️ ID: ${product.id}');
    debugPrint('➡️ Nombre: ${product.name}');
    debugPrint('➡️ Cantidad: $safeQty');

    if (product.id <= 0) {
      debugPrint('❌ Producto sin ID válido. No se añade al carrito.');
      return;
    }

    if (!product.canAddToCart) {
      debugPrint(
        '⛔ Producto bloqueado para carrito: ${product.name} · '
            'estado=${product.commercialStatusLabel}',
      );
      return;
    }

    final index = state.indexWhere(
          (item) => item.product.id == product.id,
    );

    if (index != -1) {
      debugPrint(
        '🔁 Producto ya existe en carrito. Se suma cantidad al ID ${product.id}',
      );

      state = [
        for (final item in state)
          if (item.product.id == product.id)
            CartItem(
              product: item.product,
              quantity: item.quantity + safeQty,
            )
          else
            item,
      ];
    } else {
      debugPrint('✅ Producto nuevo añadido al carrito');

      state = [
        ...state,
        CartItem(
          product: product,
          quantity: safeQty,
        ),
      ];
    }

    _saveCart();
    unawaited(
      MundicamAnalyticsService.instance.track(
        eventName: 'add_to_cart',
        objectType: 'product',
        objectId: product.id,
        value: safeQty,
        metadata: <String, dynamic>{
          'quantity': safeQty,
          if (product.sku.trim().isNotEmpty) 'sku': product.sku.trim(),
        },
      ),
    );

    // Un carrito recuperado desde presupuesto mantiene su flujo separado.
    // No debe escribir en el carrito comercial normal compartido Web ↔ App.
    if (!hasQuoteSource) {
      ApiService()
          .addProductToRemoteCart(productId: product.id, quantity: safeQty)
          .then((ok) {
        if (kDebugMode) {
          debugPrint(ok
              ? '✅ Carrito remoto App API sincronizado'
              : '⚠️ Carrito remoto App API no sincronizado');
        }
      });
    }
  }

  void removeProduct(int productId) {
    CartItem? removedItem;
    for (final item in state) {
      if (item.product.id == productId) {
        removedItem = item;
        break;
      }
    }

    state = state.where((item) => item.product.id != productId).toList();
    _saveCart();

    if (removedItem != null) {
      if (!hasQuoteSource) {
        unawaited(
          ApiService().removeRemoteCartProduct(productId: productId),
        );
      }

      unawaited(
        MundicamAnalyticsService.instance.track(
          eventName: 'remove_from_cart',
          objectType: 'product',
          objectId: productId,
          value: removedItem.quantity,
          metadata: <String, dynamic>{
            'quantity': removedItem.quantity,
            if (removedItem.product.sku.trim().isNotEmpty)
              'sku': removedItem.product.sku.trim(),
          },
        ),
      );
    }
  }

  void updateQuantity(int productId, int newQty) {
    CartItem? previousItem;
    for (final item in state) {
      if (item.product.id == productId) {
        previousItem = item;
        break;
      }
    }

    if (newQty <= 0) {
      removeProduct(productId);
      return;
    }

    state = [
      for (final item in state)
        if (item.product.id == productId)
          item.product.canAddToCart
              ? CartItem(
            product: item.product,
            quantity: newQty,
          )
              : item
        else
          item,
    ].where((item) => item.product.canAddToCart).toList();

    _saveCart();

    if (!hasQuoteSource) {
      unawaited(
        ApiService().updateRemoteCartProduct(
          productId: productId,
          quantity: newQty,
        ),
      );
    }

    if (previousItem != null && previousItem.product.canAddToCart) {
      final delta = newQty - previousItem.quantity;
      if (delta != 0) {
        unawaited(
          MundicamAnalyticsService.instance.track(
            eventName: delta > 0 ? 'add_to_cart' : 'remove_from_cart',
            objectType: 'product',
            objectId: productId,
            value: delta.abs(),
            metadata: <String, dynamic>{
              'quantity': delta.abs(),
              'new_quantity': newQty,
              if (previousItem.product.sku.trim().isNotEmpty)
                'sku': previousItem.product.sku.trim(),
            },
          ),
        );
      }
    }
  }

  Future<void> clearCart() async {
    // Capturamos el origen antes de borrarlo: vaciar un carrito de presupuesto
    // no puede borrar el carrito comercial normal compartido con la web.
    final shouldClearRemoteCart = !hasQuoteSource;

    state = [];
    await _saveCart();
    await clearQuoteSource();

    if (shouldClearRemoteCart) {
      ApiService().clearRemoteCart().then((ok) {
        if (kDebugMode) {
          debugPrint(ok
              ? '✅ Carrito remoto App API vaciado'
              : '⚠️ Carrito remoto App API no vaciado');
        }
      });
    }
  }

  /// Base imponible del carrito.
  ///
  /// El endpoint devuelve el precio profesional B2B por rol sin IVA.
  /// La app solo lo usa para mostrar una estimación y para enviar
  /// `expected_total` al backend como control antifallo. El backend siempre
  /// recalcula el precio oficial antes de crear el pedido.
  double get subtotal => state.fold(0, (sum, item) {
    if (!item.product.canAddToCart) return sum;

    final price = double.tryParse(
      item.product.price.replaceAll(',', '.'),
    ) ??
        0;

    return sum + (price * item.quantity);
  });

  double get iva => subtotal * 0.21;

  double get total => subtotal + iva;

  void _debugCart(String origen) {
    debugPrint('════════ CARRITO $origen ════════');
    debugPrint('🧾 Líneas en carrito: ${state.length}');

    for (final item in state) {
      debugPrint(
        '➡️ ID: ${item.product.id} | Qty: ${item.quantity} | ${item.product.name}',
      );
    }

    debugPrint('══════════════════════════════════');
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>((ref) {
  return CartNotifier();
});

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_service.dart';
import '../../data/models/local_quote_model.dart';
import 'local_quote_provider.dart';
import 'quote_provider.dart';

/// Provider para sincronizar presupuestos locales con WooCommerce
final quoteSyncProvider = Provider<QuoteSyncService>((ref) {
  return QuoteSyncService(ref);
});

class QuoteSyncService {
  final Ref _ref;

  QuoteSyncService(this._ref);

  /// Sincroniza un presupuesto local completo con WooCommerce
  /// Crea un presupuesto en WooCommerce por cada producto del presupuesto local
  Future<bool> syncLocalQuoteToWooCommerce({
    required LocalQuote localQuote,
    required String email,
  }) async {
    try {
      final api = ApiService();
      final ok = await api.crearPresupuestoConProductos(
        items: localQuote.items
            .map((item) => {
                  'product_id': item.productId,
                  if (item.variationId > 0) 'variation_id': item.variationId,
                  'quantity': item.quantity,
                })
            .toList(),
        customerNote: localQuote.nombre,
        sourceLocalQuoteUuid: localQuote.orderId,
      );

      if (!ok) {
        throw Exception('No se pudo guardar el presupuesto en el servidor.');
      }

      return true;
    } catch (e) {
      debugPrint('❌ Error sincronizando presupuesto local: $e');
      rethrow;
    }
  }

  /// Sincroniza y elimina el presupuesto local
  Future<void> syncAndRemoveLocalQuote({
    required String orderId,
    required String email,
  }) async {
    final notifier = _ref.read(localQuotesProvider.notifier);
    final localQuote = notifier.getPresupuesto(orderId);

    if (localQuote == null) {
      throw Exception('Presupuesto local no encontrado.');
    }

    await syncLocalQuoteToWooCommerce(
      localQuote: localQuote,
      email: email,
    );

    // Eliminar presupuesto local después de sincronizar exitosamente
    await notifier.eliminarPresupuesto(orderId);

    // Refrescar presupuestos de WooCommerce
    _ref.invalidate(quotesProvider);
  }

  /// Sincroniza todos los presupuestos locales con WooCommerce
  Future<Map<String, dynamic>> syncAllLocalQuotes({
    required String email,
  }) async {
    final localQuotes = _ref.read(localQuotesProvider);
    final quotesActivos = localQuotes.where((q) => !q.isExpired).toList();

    int totalSync = 0;
    int totalFallos = 0;
    final List<String> errores = [];

    for (final quote in quotesActivos) {
      try {
        await syncLocalQuoteToWooCommerce(
          localQuote: quote,
          email: email,
        );

        // Eliminar presupuesto local después de sincronizar
        await _ref
            .read(localQuotesProvider.notifier)
            .eliminarPresupuesto(quote.orderId);

        totalSync++;
      } catch (e) {
        totalFallos++;
        errores.add('${quote.nombre}: $e');
      }
    }

    // Refrescar presupuestos de WooCommerce
    _ref.invalidate(quotesProvider);

    return {
      'sincronizados': totalSync,
      'fallos': totalFallos,
      'errores': errores,
    };
  }
}
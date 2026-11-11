import 'package:mundicam/core/network/fast_sku_discovery_service.dart';
import 'package:mundicam/features/catalog/data/models/producto.dart';

/// Solo considera válida una ficha obtenida de la API comercial autenticada.
/// El índice público del VPS no puede suministrar precios, stock ni permisos.
Future<Product?> hydrateVerifiedFastSku({
  required FastSkuSuggestion preview,
  required Future<Product?> Function(int productId) loadAuthenticated,
  Duration timeout = const Duration(seconds: 7),
}) async {
  try {
    final product = await loadAuthenticated(preview.id).timeout(timeout);
    if (product == null ||
        product.id != preview.id ||
        product.sku.trim().toLowerCase() != preview.sku.trim().toLowerCase()) {
      return null;
    }
    // Devolver el producto íntegro comercial; jamás copiar precio ni stock
    // del resultado de descubrimiento público.
    return product;
  } catch (_) {
    // En la interfaz esto dispara la búsqueda normal WooCommerce.
    return null;
  }
}

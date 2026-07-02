import 'mundicam_app_endpoint_service.dart';

/// Adaptador simple para conectar el endpoint nuevo con el ApiService actual.
///
/// Uso recomendado:
/// - Mantener tus pantallas actuales.
/// - Sustituir la carga de precio/productos por este endpoint.
/// - Pintar siempre `product.price` como precio final.
/// - No aplicar porcentajes ni reglas de admin/comercial/cliente en Flutter.
class ApiServicePricePatch {
  final MundicamAppEndpointService endpoint;

  const ApiServicePricePatch(this.endpoint);

  Future<double?> getFinalProductPrice({
    required int wordpressUserId,
    required int productId,
  }) async {
    final product = await endpoint.getProductById(
      wpUserId: wordpressUserId,
      productId: productId,
    );
    return product.price;
  }

  Future<bool> userCanViewStock({required int wordpressUserId}) async {
    final context = await endpoint.getUserContext(wpUserId: wordpressUserId);
    return context.canViewStock;
  }

  Future<String?> getEffectivePriceGroup({required int wordpressUserId}) async {
    final context = await endpoint.getUserContext(wpUserId: wordpressUserId);
    return context.effectivePriceGroup;
  }

  Future<bool> checkAdminUses52({
    required int adminWpUserId,
    required int productId,
  }) async {
    final debug = await endpoint.debugPrice(
      wpUserId: adminWpUserId,
      productId: productId,
    );
    return debug.context.isAdmin && debug.context.effectivePriceGroup == '52';
  }
}

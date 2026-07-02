import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/mundicam_endpoint_config.dart';
import '../models/mundicam_price_debug.dart';
import '../models/mundicam_product.dart';
import '../models/mundicam_user_context.dart';
import '../services/mundicam_app_endpoint_service.dart';

/// Guarda aquí el ID de usuario WordPress después del login.
///
/// Importante: Firebase UID no es lo mismo que WordPress user ID.
/// Este endpoint necesita el ID numérico de WordPress/WooCommerce.
final mundicamWordpressUserIdProvider = StateProvider<int?>((ref) => null);

final mundicamEndpointBaseUrlProvider = Provider<String>((ref) {
  return MundicamEndpointConfig.defaultBaseUrl;
});

final mundicamEndpointApiKeyProvider = Provider<String?>((ref) {
  final key = MundicamEndpointConfig.defaultApiKey.trim();
  return key.isEmpty ? null : key;
});

final mundicamEndpointServiceProvider = Provider<MundicamAppEndpointService>((ref) {
  return MundicamAppEndpointService(
    baseUrl: ref.watch(mundicamEndpointBaseUrlProvider),
    apiKey: ref.watch(mundicamEndpointApiKeyProvider),
  );
});

final mundicamEndpointStatusProvider = FutureProvider<Map<String, dynamic>>((ref) {
  return ref.watch(mundicamEndpointServiceProvider).status();
});

final mundicamUserContextProvider = FutureProvider.family<MundicamUserContext, int>((ref, wpUserId) {
  return ref.watch(mundicamEndpointServiceProvider).getUserContext(wpUserId: wpUserId);
});

class MundicamProductsQuery {
  final int wpUserId;
  final int page;
  final int perPage;
  final String? search;
  final String? category;
  final String? brand;
  final String? orderBy;
  final String? order;

  const MundicamProductsQuery({
    required this.wpUserId,
    this.page = 1,
    this.perPage = MundicamEndpointConfig.defaultPerPage,
    this.search,
    this.category,
    this.brand,
    this.orderBy,
    this.order,
  });

  MundicamProductsQuery copyWith({
    int? wpUserId,
    int? page,
    int? perPage,
    String? search,
    String? category,
    String? brand,
    String? orderBy,
    String? order,
  }) {
    return MundicamProductsQuery(
      wpUserId: wpUserId ?? this.wpUserId,
      page: page ?? this.page,
      perPage: perPage ?? this.perPage,
      search: search ?? this.search,
      category: category ?? this.category,
      brand: brand ?? this.brand,
      orderBy: orderBy ?? this.orderBy,
      order: order ?? this.order,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MundicamProductsQuery &&
        other.wpUserId == wpUserId &&
        other.page == page &&
        other.perPage == perPage &&
        other.search == search &&
        other.category == category &&
        other.brand == brand &&
        other.orderBy == orderBy &&
        other.order == order;
  }

  @override
  int get hashCode => Object.hash(
        wpUserId,
        page,
        perPage,
        search,
        category,
        brand,
        orderBy,
        order,
      );
}

final mundicamProductsPageProvider = FutureProvider.family<MundicamProductsPage, MundicamProductsQuery>((ref, query) {
  return ref.watch(mundicamEndpointServiceProvider).getProducts(
        wpUserId: query.wpUserId,
        page: query.page,
        perPage: query.perPage,
        search: query.search,
        category: query.category,
        brand: query.brand,
        orderBy: query.orderBy,
        order: query.order,
      );
});

class MundicamProductQuery {
  final int wpUserId;
  final int productId;

  const MundicamProductQuery({
    required this.wpUserId,
    required this.productId,
  });

  @override
  bool operator ==(Object other) {
    return other is MundicamProductQuery &&
        other.wpUserId == wpUserId &&
        other.productId == productId;
  }

  @override
  int get hashCode => Object.hash(wpUserId, productId);
}

final mundicamProductProvider = FutureProvider.family<MundicamProduct, MundicamProductQuery>((ref, query) {
  return ref.watch(mundicamEndpointServiceProvider).getProductById(
        wpUserId: query.wpUserId,
        productId: query.productId,
      );
});

final mundicamPriceDebugProvider = FutureProvider.family<MundicamPriceDebug, MundicamProductQuery>((ref, query) {
  return ref.watch(mundicamEndpointServiceProvider).debugPrice(
        wpUserId: query.wpUserId,
        productId: query.productId,
      );
});

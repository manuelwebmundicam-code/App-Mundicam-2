import 'package:dio/dio.dart';

import '../core/config/mundicam_endpoint_config.dart';
import '../core/network/mundicam_endpoint_exception.dart';
import '../models/mundicam_price_debug.dart';
import '../models/mundicam_product.dart';
import '../models/mundicam_user_context.dart';

/// Servicio principal para consumir el endpoint PHP nuevo:
/// /wp-json/mundicam-app/v1
///
/// Regla importante:
/// Flutter NO calcula descuentos.
/// El precio final que debe pintar la app es siempre `MundicamProduct.price`.
class MundicamAppEndpointService {
  final Dio _dio;
  final String baseUrl;
  final String? apiKey;

  MundicamAppEndpointService({
    this.baseUrl = MundicamEndpointConfig.defaultBaseUrl,
    this.apiKey = MundicamEndpointConfig.defaultApiKey,
    Dio? dio,
  }) : _dio = dio ?? Dio() {
    _dio.options.baseUrl = _normalizeBaseUrl(baseUrl);
    _dio.options.connectTimeout = const Duration(seconds: 20);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    _dio.options.sendTimeout = const Duration(seconds: 20);
    _dio.options.headers.addAll({
      'Accept': 'application/json',
      if (apiKey != null && apiKey!.trim().isNotEmpty)
        'X-Mundicam-App-Key': apiKey!.trim(),
    });
    _dio.options.validateStatus = (status) => status != null && status < 500;
  }

  static String _normalizeBaseUrl(String value) {
    final clean = value.trim().replaceAll(RegExp(r'/+$'), '');
    if (clean.endsWith('/wp-json/mundicam-app/v1')) {
      return clean;
    }
    return '$clean/wp-json/mundicam-app/v1';
  }

  Future<Map<String, dynamic>> status() async {
    final response = await _dio.get<Map<String, dynamic>>('/status');
    return _readMap(response);
  }

  Future<MundicamUserContext> getUserContext({required int wpUserId}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/user-context',
      queryParameters: {'wp_user_id': wpUserId},
    );
    return MundicamUserContext.fromJson(_readMap(response));
  }

  Future<MundicamProductsPage> getProducts({
    required int wpUserId,
    int page = 1,
    int perPage = MundicamEndpointConfig.defaultPerPage,
    String? search,
    String? category,
    String? brand,
    String? orderBy,
    String? order,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/products',
      queryParameters: {
        'wp_user_id': wpUserId,
        'page': page,
        'per_page': perPage,
        if (_hasText(search)) 'search': search!.trim(),
        if (_hasText(category)) 'category': category!.trim(),
        if (_hasText(brand)) 'brand': brand!.trim(),
        if (_hasText(orderBy)) 'orderby': orderBy!.trim(),
        if (_hasText(order)) 'order': order!.trim(),
      },
    );
    return MundicamProductsPage.fromJson(_readMap(response));
  }

  Future<MundicamProduct> getProductById({
    required int wpUserId,
    required int productId,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/product/$productId',
      queryParameters: {'wp_user_id': wpUserId},
    );
    final data = _readMap(response);
    final product = data['product'];
    if (product is! Map) {
      throw const MundicamEndpointException(
        code: 'invalid_product_response',
        message: 'Respuesta de producto no válida.',
      );
    }
    return MundicamProduct.fromJson(
      product.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  Future<MundicamPriceDebug> debugPrice({
    required int wpUserId,
    required int productId,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/debug-price',
      queryParameters: {
        'wp_user_id': wpUserId,
        'product_id': productId,
      },
    );
    return MundicamPriceDebug.fromJson(_readMap(response));
  }

  static bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

  static Map<String, dynamic> _readMap(Response<Map<String, dynamic>> response) {
    final statusCode = response.statusCode ?? 0;
    final data = response.data ?? const <String, dynamic>{};

    if (statusCode >= 200 && statusCode < 300) {
      return data;
    }

    final code = data['code']?.toString() ?? 'mundicam_endpoint_error';
    final message = data['message']?.toString() ?? 'Error de endpoint MundiCam';

    throw MundicamEndpointException(
      statusCode: statusCode,
      code: code,
      message: message,
    );
  }
}

class MundicamProductsPage {
  final MundicamUserContext context;
  final int page;
  final int perPage;
  final int total;
  final int totalPages;
  final List<MundicamProduct> products;

  const MundicamProductsPage({
    required this.context,
    required this.page,
    required this.perPage,
    required this.total,
    required this.totalPages,
    required this.products,
  });

  factory MundicamProductsPage.fromJson(Map<String, dynamic> json) {
    final productsRaw = json['products'];
    return MundicamProductsPage(
      context: MundicamUserContext.fromJson(
        (json['context'] as Map?)?.map(
              (key, value) => MapEntry(key.toString(), value),
            ) ??
            const <String, dynamic>{},
      ),
      page: _asInt(json['page']),
      perPage: _asInt(json['per_page']),
      total: _asInt(json['total']),
      totalPages: _asInt(json['total_pages']),
      products: productsRaw is List
          ? productsRaw
              .whereType<Map>()
              .map(
                (item) => MundicamProduct.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .toList()
          : const <MundicamProduct>[],
    );
  }

  bool get hasNextPage => page < totalPages;

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

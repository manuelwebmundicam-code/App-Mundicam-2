import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Únicamente WordPress QA (127.0.0.1:8770 vía adb reverse + SSH tunnel).
/// No importa ApiService, no lee tokens reales, ni permite configurar otros hosts.
class MundicamQaClient {
  MundicamQaClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 35),
              followRedirects: false,
              headers: const {'Accept': 'application/json'},
            ),
          );

  static const baseUrl = 'http://127.0.0.1:8770';
  final Dio _dio;
  String? _token;
  bool get authenticated => _token?.isNotEmpty == true;
  void clearSession() => _token = null;

  void _guard() {
    if (!kDebugMode) throw StateError('QA solo está disponible en DEBUG.');
  }

  Options get _auth => Options(
    followRedirects: false,
    headers: {
      if (authenticated) 'Authorization': 'Bearer $_token',
      if (authenticated) 'X-MundiCam-App-Token': _token!,
    },
  );

  static Map<String, dynamic> _map(dynamic raw) =>
      raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

  static Map<String, dynamic> _filters(dynamic response) {
    final root = _map(response);
    final nested = _map(root['data']);
    final data = nested['filters'] is List ? nested : root;
    if (root['success'] == false || data['filters'] is! List) {
      throw const FormatException(
        'Contrato del endpoint de filtros no válido.',
      );
    }
    return data;
  }

  Future<String> status() async {
    _guard();
    final response = await _dio.get(
      '/wp-json/mundicam-app/v1/status',
      options: Options(followRedirects: false),
    );
    final version = _map(response.data)['version']?.toString() ?? '';
    if (!version.startsWith('1.9.64-r19-')) {
      throw const FormatException('El PHP R19 no está activo en QA.');
    }
    return version;
  }

  Future<void> login(String email, String password) async {
    _guard();
    clearSession();
    if (email.trim().isEmpty || password.isEmpty) {
      throw const FormatException('Introduce una cuenta exclusivamente QA.');
    }
    final response = await _dio.post(
      '/wp-json/mundicam-app/v1/login',
      data: {'email': email.trim(), 'password': password},
      options: Options(followRedirects: false),
    );
    final body = _map(response.data);
    final candidate =
        (body['app_token'] ?? _map(body['session'])['app_token'])
            ?.toString()
            .trim() ??
        '';
    if (body['success'] == false || candidate.isEmpty) {
      throw const FormatException('No se recibió token QA válido.');
    }
    _token = candidate;
    try {
      await _dio.get('/wp-json/mundicam-app/v1/me', options: _auth);
    } catch (_) {
      clearSession();
      rethrow;
    }
  }

  Future<QaBenchmark> benchmark(int categoryId) async {
    _guard();
    if (!authenticated || categoryId <= 0) {
      throw StateError('Inicia sesión de pruebas y selecciona categoría.');
    }
    final filtersPath = '/wp-json/mundicam/v1/catalog-filters';
    final base = {'category_id': categoryId, 'include_subcategories': 1};
    final fullWatch = Stopwatch()..start();
    final fullResponse = await _dio.get(
      filtersPath,
      queryParameters: base,
      options: _auth,
    );
    final fullMs = fullWatch.elapsedMilliseconds;
    final full = _filters(fullResponse.data);

    final fastWatch = Stopwatch()..start();
    final fastResponse = await _dio.get(
      filtersPath,
      queryParameters: {...base, 'facets_only': 1},
      options: _auth,
    );
    final fastMs = fastWatch.elapsedMilliseconds;
    final fast = _filters(fastResponse.data);

    final productsWatch = Stopwatch()..start();
    final prodResponse = await _dio.get(
      '/wp-json/mundicam-app/v1/products',
      queryParameters: {
        'category': categoryId,
        'category_id': categoryId,
        'page': 1,
        'per_page': 10,
        'orderby': 'price_asc',
        'orderBy': 'price_asc',
      },
      options: _auth,
    );
    final prodMs = productsWatch.elapsedMilliseconds;
    final prod = _map(prodResponse.data);
    if (prod['success'] == false || prod['products'] is! List) {
      throw const FormatException('Contrato de productos QA no válido.');
    }
    final count = fast['total_products'];
    return QaBenchmark(
      categoryId: categoryId,
      fullFiltersMs: fullMs,
      fastFiltersMs: fastMs,
      productsMs: prodMs,
      sameFacets:
          QaBenchmark.fingerprint(full) == QaBenchmark.fingerprint(fast),
      sameTotal: full['total_products'] == fast['total_products'],
      skipsAggregates:
          fast['price_range'] == null && fast['stock_filter'] == null,
      totalProducts: count is num ? count.toInt() : 0,
      firstPageCount: (prod['products'] as List).length,
    );
  }
}

@immutable
class QaBenchmark {
  const QaBenchmark({
    required this.categoryId,
    required this.fullFiltersMs,
    required this.fastFiltersMs,
    required this.productsMs,
    required this.sameFacets,
    required this.sameTotal,
    required this.skipsAggregates,
    required this.totalProducts,
    required this.firstPageCount,
  });
  final int categoryId, fullFiltersMs, fastFiltersMs, productsMs;
  final int totalProducts, firstPageCount;
  final bool sameFacets, sameTotal, skipsAggregates;
  bool get validated =>
      sameFacets && sameTotal && skipsAggregates && totalProducts > 0;

  static String fingerprint(Map<String, dynamic> response) {
    final groups = response['filters'];
    if (groups is! List) return '';
    final parts = <String>[];
    for (final group in groups.whereType<Map>()) {
      final opts = <String>[];
      if (group['options'] is List) {
        for (final option in (group['options'] as List).whereType<Map>()) {
          opts.add('${option['id']}:${option['slug']}:${option['count']}');
        }
      }
      opts.sort();
      parts.add('${group['taxonomy']}:${opts.join("|")}');
    }
    parts.sort();
    return parts.join(';');
  }
}

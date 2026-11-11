import 'package:dio/dio.dart';

/// Catálogo público indexado del VPS. Metadatos, nunca precios ni stock.
/// No sustituye el API comercial autenticado de WooCommerce.
class VpsCatalogService {
  VpsCatalogService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: endpoint,
              connectTimeout: const Duration(milliseconds: 1500),
              receiveTimeout: const Duration(milliseconds: 2000),
              headers: const {'Accept': 'application/json'},
            ),
          );

  static const String endpoint = String.fromEnvironment(
    'MUNDICAM_FAST_SKU_URL',
    defaultValue: 'https://app.mundicam.com/app-fast/v1',
  );

  final Dio _dio;
  List<Map<String, dynamic>>? _completeCategoryTreeCached;
  DateTime? _completeCategoryTreeCachedAt;
  Future<List<Map<String, dynamic>>?>? _completeTreeRequest;

  /// Solo para pruebas: términos de la taxonomía PÚBLICA de WordPress.
  /// Debe contener exactamente los 490 IDs, padres y el orden oficial.
  /// Nunca sustituye precios/stock ni comprueba visibilidad de clientes.
  Future<List<Map<String, dynamic>>?> completeCategoryTree() {
    final cached = _completeCategoryTreeCached;
    final updated = _completeCategoryTreeCachedAt;
    if (cached != null &&
        updated != null &&
        DateTime.now().difference(updated) < const Duration(minutes: 10)) {
      return Future.value(cached);
    }
    final pending = _completeTreeRequest;
    if (pending != null) return pending;
    final future = _fetchCompleteCategoryTree();
    _completeTreeRequest = future;
    return future.whenComplete(() {
      if (identical(_completeTreeRequest, future)) {
        _completeTreeRequest = null;
      }
    });
  }

  Future<List<Map<String, dynamic>>?> _fetchCompleteCategoryTree() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/catalog/categories',
        queryParameters: const {'source': 'wp-complete-qa'},
      );
      final body = response.data;
      if (response.statusCode != 200 ||
          body?['scope'] != 'public_metadata_only' ||
          body?['source'] != 'public_wordpress_complete_category_tree' ||
          body?['commercial_parity_confirmed'] != false ||
          body?['requires_authenticated_products'] != true ||
          body?['count'] != 490 ||
          body?['results'] is! List ||
          body?['synced_at'] is! int)
        return null;
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final age = nowSeconds - (body!['synced_at'] as int);
      if (age < 0 || age > 36 * 3600) return null;
      final values = body['results'] as List;
      if (values.length != 490) return null;
      final ids = <int>{};
      final tree = <Map<String, dynamic>>[];
      for (final value in values) {
        if (value is! Map ||
            value['id'] is! int ||
            (value['id'] as int) <= 0 ||
            !ids.add(value['id'] as int) ||
            value['name'] is! String ||
            (value['name'] as String).trim().isEmpty ||
            value['slug'] is! String ||
            value['parent'] is! int ||
            (value['parent'] as int) < 0 ||
            value['menu_order'] is! int ||
            (value['menu_order'] as int) < 0 ||
            value['count'] is! int ||
            (value['count'] as int) < 0 ||
            value['image_url'] is! String ||
            value['description'] is! String)
          return null;
        tree.add(Map<String, dynamic>.from(value));
      }
      if (tree.any(
        (row) => row['parent'] != 0 && !ids.contains(row['parent']),
      )) {
        return null;
      }
      final parents = <int, int>{
        for (final category in tree)
          category['id'] as int: category['parent'] as int,
      };
      for (final id in ids) {
        final seen = <int>{};
        var current = id;
        while (current != 0) {
          if (!seen.add(current)) return null;
          current = parents[current] ?? -1;
          if (current < 0) return null;
        }
      }
      // La API publica devuelve el arbol completo, pero no has_children.
      // Calculamos hijos directos sobre la jerarquia ya validada, sin
      // solicitar otra vez las categorias a WordPress.
      // Solo navegacion QA: no infiere visibilidad ni precios B2B.
      final directChildren = <int, int>{};
      for (final category in tree) {
        final parentId = category['parent'] as int;
        if (parentId > 0) {
          directChildren[parentId] = (directChildren[parentId] ?? 0) + 1;
        }
      }
      for (final category in tree) {
        final count = directChildren[category['id'] as int] ?? 0;
        category['has_children'] = count > 0;
        category['children_count'] = count;
      }
      _completeCategoryTreeCached = tree;
      _completeCategoryTreeCachedAt = DateTime.now();
      return tree;
    } on DioException {
      return null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> brands() => _terms('/catalog/brands');

  /// Solo términos XStore con relaciones publicadas verificadas por ID.
  /// No sustituye /brands de la API comercial, que puede usar más taxonomías.
  Future<List<Map<String, dynamic>>> verifiedWordPressBrands() async {
    final terms = await _terms(
      '/catalog/brands',
      queryParameters: const {'source': 'wp'},
    );
    // Nunca confundir IDs XStore con otra taxonomía por coincidencia de nombre.
    if (terms.any(
      (term) =>
          term['source'] != 'wp_rest_verified' ||
          term['taxonomy'] != 'brand' ||
          term['vps_filter'] != 'xstore_brand',
    )) {
      return const [];
    }
    return terms;
  }

  /// Los 50 fabricantes reales verificados en el escaparate, con IDs XStore.
  /// No sustituye los filtros de la API autenticada, que pueden ser distintos.
  Future<List<Map<String, dynamic>>> verifiedCompleteBrands() async {
    final terms = await _terms(
      '/catalog/brands',
      queryParameters: const {'source': 'complete'},
    );
    final ids = <int>{};
    if (terms.any(
      (term) =>
          term['source'] != 'verified_storefront' ||
          term['taxonomy'] != 'brand' ||
          term['vps_filter'] != 'xstore_brand' ||
          !ids.add(term['id'] as int),
    )) {
      return const [];
    }
    return terms;
  }

  Future<List<Map<String, dynamic>>> categories() =>
      _terms('/catalog/categories');

  Future<List<Map<String, dynamic>>> _terms(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: queryParameters,
      );
      final data = response.data;
      if (response.statusCode != 200 ||
          data?['scope'] != 'public_metadata_only' ||
          data?['results'] is! List) {
        return const [];
      }
      final result = <Map<String, dynamic>>[];
      for (final value in data!['results'] as List) {
        if (value is! Map ||
            value['id'] is! int ||
            value['id'] <= 0 ||
            value['name'] is! String ||
            value['slug'] is! String ||
            value['indexed_product_count'] is! int) {
          return const [];
        }
        result.add(Map<String, dynamic>.from(value));
      }
      return result;
    } on DioException {
      return const [];
    } on FormatException {
      return const [];
    } on TypeError {
      return const [];
    }
  }

  Future<Map<String, dynamic>?> productPage({
    required String taxonomy,
    required int id,
    int page = 1,
    int limit = 12,
    bool includeChildren = false,
  }) async {
    if (includeChildren && taxonomy != 'category') return null;
    if (!const [
          'brand',
          'category',
          'xstore_brand',
          'wp_product_brand',
        ].contains(taxonomy) ||
        id <= 0 ||
        page < 1 ||
        page > 1000 ||
        limit < 1 ||
        limit > 30) {
      return null;
    }
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/catalog/products',
        queryParameters: {
          'taxonomy': taxonomy,
          'id': id,
          'page': page,
          'limit': limit,
          if (includeChildren) 'children': '1',
        },
      );
      final data = response.data;
      if (response.statusCode != 200 ||
          data?['scope'] != 'public_metadata_only' ||
          data?['requires_authenticated_hydration'] != true ||
          data?['results'] is! List ||
          data?['total'] is! int) {
        return null;
      }
      for (final row in data!['results'] as List) {
        if (row is! Map ||
            row['id'] is! int ||
            row['id'] <= 0 ||
            row['sku'] is! String ||
            row['name'] is! String ||
            row['image_url'] is! String) {
          return null;
        }
      }
      return {
        'results': (data!['results'] as List)
            .map(
              (row) => <String, dynamic>{
                'id': row['id'],
                'sku': row['sku'],
                'name': row['name'],
                'image_url': row['image_url'],
              },
            )
            .toList(),
        'total': data['total'],
        'page': page,
        'per_page': limit,
      };
    } on DioException {
      return null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}

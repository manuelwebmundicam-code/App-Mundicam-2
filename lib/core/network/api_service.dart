// services/api_service.dart
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:mundicam/features/home/data/models/banner.dart';
import 'package:mundicam/features/training/data/models/cursos_model.dart';
import 'package:mundicam/features/home/data/models/noticia.dart';
import 'package:mundicam/features/orders/data/models/order_model.dart';
import 'package:mundicam/features/catalog/data/models/producto.dart';
import 'package:mundicam/features/catalog/data/models/category_model.dart';
import 'package:mundicam/features/quotes/data/models/quote_model.dart';

class OrderCreateResult {
  final bool success;
  final int? orderId;
  final String? orderKey;
  final String? orderNumber;
  final String? status;
  final String? errorMessage;
  final Map<String, dynamic>? rawData;

  const OrderCreateResult({
    required this.success,
    this.orderId,
    this.orderKey,
    this.orderNumber,
    this.status,
    this.errorMessage,
    this.rawData,
  });

  factory OrderCreateResult.success(Map<String, dynamic> data) {
    return OrderCreateResult(
      success: true,
      orderId: data['id'] is int ? data['id'] as int : int.tryParse(data['id']?.toString() ?? ''),
      orderKey: data['order_key']?.toString(),
      orderNumber: data['number']?.toString(),
      status: data['status']?.toString(),
      rawData: data,
    );
  }

  factory OrderCreateResult.failure(String message) {
    return OrderCreateResult(success: false, errorMessage: message);
  }
}

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late final Dio _dio;
  final FirebaseRemoteConfig _remoteConfig = FirebaseRemoteConfig.instance;
  String _consumerKey = '';
  String _consumerSecret = '';
  bool _initialized = false;
  List<String>? _cachedBrandNames;

  static const List<String> _fallbackBrandNames = <String>[
    'Dahua',
    'Hikvision',
    'Ajax',
    'Ksenia',
    'TP-Link',
    'TPLINK',
    'Mobotix',
    'Teletek',
    'Wisim',
    'Wisat',
    'Evolve',
    'Secury360',
    'Securiton',
    'Ruijie',
    'Reyee',
    'ZKTeco',
    'Imou',
    'Safire',
    'Uniview',
    'Ubiquiti',
    'Fermax',
    'Golmar',
    'Hikmicro',
    'Akuvox',
    'Milesight',
    'Cambium',
    'Aritech',
    'Paradox',
    'DSC',
    'Honeywell',
  ];

  ApiService._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: 'https://www.mundicam.com',
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {'Accept': 'application/json'},
      ),
    );
    _loadKeys();
  }

  // ================================================================
  // CARGA SEGURA DE KEYS DESDE REMOTE CONFIG
  // ================================================================

  Future<void> _loadKeys() async {
    try {
      await _remoteConfig.fetchAndActivate();
      _consumerKey = _remoteConfig.getString('wc_consumer_key');
      _consumerSecret = _remoteConfig.getString('wc_consumer_secret');
      _initialized = true;
      if (_consumerKey.isNotEmpty && _consumerSecret.isNotEmpty) {
        debugPrint('🔑 Keys cargadas desde Firebase Remote Config');
      } else {
        debugPrint('⚠️ Keys no configuradas en Remote Config');
      }
    } catch (e) {
      debugPrint('⚠️ Error cargando keys desde Remote Config: $e');
      _consumerKey = _remoteConfig.getString('wc_consumer_key');
      _consumerSecret = _remoteConfig.getString('wc_consumer_secret');
      _initialized = true;
    }
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await _loadKeys();
    }
  }

  // ================================================================
  // AUTENTICACIÓN WOOCOMMERCE
  // ================================================================

  String get _basicAuth {
    if (_consumerKey.isEmpty || _consumerSecret.isEmpty) {
      debugPrint('❌ API Keys no configuradas');
      return 'Basic ${base64Encode(utf8.encode('error:error'))}';
    }
    return 'Basic ${base64Encode(utf8.encode('$_consumerKey:$_consumerSecret'))}';
  }

  Options get _wooOptions => Options(headers: {'Authorization': _basicAuth});

  // ================================================================
  // NORMALIZACIÓN / MARCAS
  // ================================================================

  String _normalizeBrandValue(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[\s\-_]+'), '')
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  bool _isBrandAttributeName(String value) {
    final normalized = _normalizeBrandValue(value);
    return normalized.contains('marca') ||
        normalized.contains('brand') ||
        normalized == 'pamarca' ||
        normalized == 'productbrand';
  }

  String? _cleanBrandCandidate(String? value) {
    if (value == null) return null;
    final clean = value
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .trim();
    if (clean.isEmpty) return null;
    final normalized = clean.toLowerCase();
    if (normalized == '0' ||
        normalized == 'null' ||
        normalized == 'false' ||
        normalized == 'sin marca') {
      return null;
    }
    return clean;
  }

  String? _brandCandidateFromValue(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      return _cleanBrandCandidate(value);
    }
    if (value is Map) {
      final map = Map<dynamic, dynamic>.from(value);
      final possibleKeys = <String>[
        'name',
        'label',
        'value',
        'slug',
        'title',
      ];
      for (final key in possibleKeys) {
        final candidate = _brandCandidateFromValue(map[key]);
        if (candidate != null) return candidate;
      }
    }
    if (value is List && value.isNotEmpty) {
      for (final item in value) {
        final candidate = _brandCandidateFromValue(item);
        if (candidate != null) return candidate;
      }
    }
    return null;
  }

  String? _extractBrandFromAttributes(dynamic attributes) {
    if (attributes is! List) return null;
    for (final rawAttr in attributes) {
      if (rawAttr is! Map) continue;
      final attr = Map<dynamic, dynamic>.from(rawAttr);
      final attrName = attr['name']?.toString() ?? '';
      final attrSlug = attr['slug']?.toString() ?? '';
      if (!_isBrandAttributeName(attrName) && !_isBrandAttributeName(attrSlug)) {
        continue;
      }
      final options = attr['options'];
      final option = attr['option'];
      final candidateFromOptions = _brandCandidateFromValue(options);
      if (candidateFromOptions != null) return candidateFromOptions;
      final candidateFromOption = _brandCandidateFromValue(option);
      if (candidateFromOption != null) return candidateFromOption;
    }
    return null;
  }

  String? _findKnownBrandInText(String text, List<String> knownBrands) {
    final normalizedText = _normalizeBrandValue(text);
    if (normalizedText.isEmpty) return null;
    final orderedBrands = List<String>.from(knownBrands)
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final brand in orderedBrands) {
      final cleanBrand = _cleanBrandCandidate(brand);
      if (cleanBrand == null) continue;
      final normalizedBrand = _normalizeBrandValue(cleanBrand);
      if (normalizedBrand.length < 3) continue;
      if (normalizedText.contains(normalizedBrand)) {
        return cleanBrand;
      }
    }
    return null;
  }

  Future<List<String>> _getKnownBrandNames() async {
    await _ensureInitialized();
    if (_cachedBrandNames != null && _cachedBrandNames!.isNotEmpty) {
      return _cachedBrandNames!;
    }

    final brands = <String>{..._fallbackBrandNames};
    try {
      final response = await _dio.get(
        '/wp-json/wc/v3/products/attributes/pa_marca/terms',
        queryParameters: {'per_page': 100, 'hide_empty': false},
        options: _wooOptions,
      );
      if (response.statusCode == 200 && response.data is List) {
        for (final term in response.data as List) {
          if (term is Map) {
            final name = term['name']?.toString().trim();
            if (name != null && name.isNotEmpty) {
              brands.add(name);
            }
            final slug = term['slug']?.toString().trim();
            if (slug != null && slug.isNotEmpty) {
              brands.add(slug);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ No se pudieron cargar marcas para enriquecer productos: $e');
    }

    _cachedBrandNames = brands
        .map((brand) => brand.trim())
        .where((brand) => brand.isNotEmpty)
        .toList();
    return _cachedBrandNames!;
  }

  String? _extractBrandFromRawProduct(
      Map<String, dynamic> json,
      List<String> knownBrands,
      ) {
    final fromAttributes = _extractBrandFromAttributes(json['attributes']);
    if (fromAttributes != null) return fromAttributes;

    final fromDirectBrand = _brandCandidateFromValue(json['brand']);
    if (fromDirectBrand != null) return fromDirectBrand;

    final fromBrands = _brandCandidateFromValue(json['brands']);
    if (fromBrands != null) return fromBrands;

    final metaData = json['meta_data'];
    if (metaData is List) {
      for (final rawMeta in metaData) {
        if (rawMeta is! Map) continue;
        final meta = Map<dynamic, dynamic>.from(rawMeta);
        final key = meta['key']?.toString() ?? '';
        if (!_isBrandAttributeName(key)) continue;
        final fromMeta = _brandCandidateFromValue(meta['value']);
        if (fromMeta != null) return fromMeta;
      }
    }

    final categories = json['categories'];
    if (categories is List) {
      for (final rawCategory in categories) {
        if (rawCategory is! Map) continue;
        final category = Map<dynamic, dynamic>.from(rawCategory);
        final categoryName = category['name']?.toString() ?? '';
        final categorySlug = category['slug']?.toString() ?? '';
        final fromCategoryName = _findKnownBrandInText(
          categoryName,
          knownBrands,
        );
        if (fromCategoryName != null) return fromCategoryName;
        final fromCategorySlug = _findKnownBrandInText(
          categorySlug,
          knownBrands,
        );
        if (fromCategorySlug != null) return fromCategorySlug;
      }
    }

    final searchableText = <String>[
      json['name']?.toString() ?? '',
      json['short_description']?.toString() ?? '',
      json['description']?.toString() ?? '',
      json['sku']?.toString() ?? '',
    ].join(' ');

    return _findKnownBrandInText(searchableText, knownBrands);
  }

  Map<String, dynamic> _injectBrandAttributeIfNeeded(
      Map<String, dynamic> json,
      List<String> knownBrands,
      ) {
    final existingBrand = _extractBrandFromAttributes(json['attributes']);
    if (existingBrand != null) return json;

    final extractedBrand = _extractBrandFromRawProduct(json, knownBrands);
    if (extractedBrand == null || extractedBrand.trim().isEmpty) {
      return json;
    }

    final attributes = json['attributes'] is List
        ? List<dynamic>.from(json['attributes'] as List)
        : <dynamic>[];

    attributes.add({
      'name': 'Marca',
      'options': [extractedBrand.trim()],
    });

    json['attributes'] = attributes;

    if (kDebugMode) {
      debugPrint(
        '🏷️ Marca inyectada en producto ${json['id']}: ${extractedBrand.trim()}',
      );
    }

    return json;
  }

  Future<List<Product>> _mapProductsWithBrand(List data) async {
    final knownBrands = await _getKnownBrandNames();
    final products = <Product>[];
    for (final item in data) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      final enrichedJson = _injectBrandAttributeIfNeeded(json, knownBrands);
      products.add(Product.fromJson(enrichedJson));
    }
    return products;
  }

  Future<Product?> _mapSingleProductWithBrand(dynamic data) async {
    if (data is! Map) return null;
    final knownBrands = await _getKnownBrandNames();
    final json = Map<String, dynamic>.from(data);
    final enrichedJson = _injectBrandAttributeIfNeeded(json, knownBrands);
    return Product.fromJson(enrichedJson);
  }

  bool _productMatchesBrand(Product product, String brand) {
    final queryMarca = _normalizeBrandValue(brand);
    if (queryMarca.isEmpty) return true;
    for (final attr in product.attributes) {
      if (!_isBrandAttributeName(attr.name)) continue;
      for (final option in attr.options) {
        if (_normalizeBrandValue(option) == queryMarca) {
          return true;
        }
      }
    }
    return false;
  }

  // ================================================================
  // CLIENTES
  // ================================================================

  Future<Map<String, dynamic>?> getCustomerByEmail(String email) async {
    await _ensureInitialized();
    try {
      final response = await _dio.get(
        '/wp-json/wc/v3/customers',
        queryParameters: {'email': email, 'role': 'all'},
        options: _wooOptions,
      );
      if (response.statusCode == 200 &&
          response.data is List &&
          response.data.isNotEmpty) {
        return (response.data as List).first as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('Error en getCustomerByEmail: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getCustomerById(int id) async {
    await _ensureInitialized();
    try {
      final response = await _dio.get(
        '/wp-json/wc/v3/customers/$id',
        options: _wooOptions,
      );
      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('Error en getCustomerById: $e');
      return null;
    }
  }

  // ================================================================
  // PRODUCTOS
  // ================================================================

  Future<List<Product>> getProductos({
    int? categoryId,
    int perPage = 100,
    String? brand,
    String? orderBy,
  }) async {
    await _ensureInitialized();
    try {
      final Map<String, dynamic> queryParams = {
        'per_page': perPage,
        'status': 'publish',
      };
      if (categoryId != null && categoryId > 0) {
        queryParams['category'] = categoryId;
      }

      final response = await _dio.get(
        '/wp-json/wc/v3/products',
        queryParameters: queryParams,
        options: _wooOptions,
      );

      final List data = response.data is List ? response.data as List : [];
      List<Product> productos = await _mapProductsWithBrand(data);

      if (brand != null && brand.isNotEmpty) {
        productos = productos.where((p) => _productMatchesBrand(p, brand)).toList();
      }

      if (orderBy != null) {
        if (orderBy == 'price_asc') {
          productos.sort(
                (a, b) => double.parse(a.price).compareTo(double.parse(b.price)),
          );
        } else if (orderBy == 'price_desc') {
          productos.sort(
                (a, b) => double.parse(b.price).compareTo(double.parse(a.price)),
          );
        } else if (orderBy == 'date') {
          productos.sort((a, b) => b.id.compareTo(a.id));
        }
      }

      debugPrint("📊 Productos finales mostrados: ${productos.length}");
      return productos;
    } on DioException catch (e) {
      throw Exception("Error: ${e.message}");
    }
  }

  // ================================================================
  // PEDIDOS
  // ================================================================

  Future<List<OrderMundicam>> getOrders(String customerEmail) async {
    await _ensureInitialized();
    try {
      final response = await _dio.get(
        '/wp-json/wc/v3/orders',
        queryParameters: {'search': customerEmail, 'per_page': 20},
        options: _wooOptions,
      );
      if (response.statusCode == 200) {
        return (response.data as List)
            .map((order) => OrderMundicam.fromJson(order))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint("Error obteniendo pedidos: $e");
      return [];
    }
  }

  // ================================================================
  // CREAR PEDIDO CON RESULTADO COMPLETO
  // ================================================================

  Future<OrderCreateResult> crearPedidoConResultado(
      Map<String, dynamic> orderData, {
        bool forceProcessingIfPending = true,
      }) async {
    await _ensureInitialized();
    try {
      debugPrint('📦 Creando pedido con resultado...');
      final data = Map<String, dynamic>.from(orderData);
      if (forceProcessingIfPending &&
          (!data.containsKey('status') || data['status'] == 'pending')) {
        data['status'] = 'processing';
      }

      debugPrint('📦 Status enviado: ${data['status']}');
      debugPrint('📦 Payment method: ${data['payment_method']}');

      final response = await _dio.post(
        '/wp-json/wc/v3/orders',
        data: data,
        options: _wooOptions,
      );

      debugPrint('📦 Status HTTP: ${response.statusCode}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (response.data is! Map) {
          debugPrint(
            '❌ Respuesta inesperada al crear pedido: ${response.data}',
          );
          return OrderCreateResult.failure(
            'WooCommerce devolvió una respuesta no válida.',
          );
        }

        final responseData = Map<String, dynamic>.from(response.data as Map);
        final orderId = responseData['id'];
        final orderKey = responseData['order_key'];
        final status = responseData['status'];

        debugPrint('✅ Pedido #$orderId creado correctamente');
        debugPrint('🔑 Order key: $orderKey');
        debugPrint('📌 Estado WooCommerce: $status');

        return OrderCreateResult.success(responseData);
      }

      debugPrint('❌ Error al crear pedido: ${response.statusCode}');
      debugPrint(' Respuesta: ${response.data}');
      return OrderCreateResult.failure(
        'WooCommerce respondió con código ${response.statusCode}.',
      );
    } on DioException catch (e) {
      debugPrint('❌ DioException al crear pedido:');
      debugPrint(' Status Code: ${e.response?.statusCode}');
      debugPrint(' Response: ${e.response?.data}');
      debugPrint(' Message: ${e.message}');

      final responseData = e.response?.data;
      if (responseData is Map && responseData['message'] != null) {
        return OrderCreateResult.failure(responseData['message'].toString());
      }
      return OrderCreateResult.failure(_mapDioError(e));
    } catch (e) {
      debugPrint('❌ Error al crear pedido: $e');
      return OrderCreateResult.failure(e.toString());
    }
  }

  Future<bool> crearPedido(Map<String, dynamic> orderData) async {
    final result = await crearPedidoConResultado(
      orderData,
      forceProcessingIfPending: true,
    );
    return result.success;
  }

  // ================================================================
  // CREAR PRESUPUESTO
  // ================================================================

  Future<bool> crearPresupuesto({
    required String email,
    required int productId,
    required String productName,
    required double price,
    required int quantity,
    String? customerNote,
  }) async {
    await _ensureInitialized();
    try {
      final orderData = {
        'status': 'checkout-draft',
        'billing': {'email': email},
        'line_items': [
          {'product_id': productId, 'quantity': quantity},
        ],
        'customer_note': customerNote ?? 'Presupuesto solicitado desde la app Mundicam',
      };

      debugPrint('📝 Creando presupuesto...');
      debugPrint('📝 Email: $email');
      debugPrint('📝 Producto ID: $productId');
      debugPrint('📝 Cantidad: $quantity');

      final response = await _dio.post(
        '/wp-json/wc/v3/orders',
        data: orderData,
        options: _wooOptions,
      );

      debugPrint('✅ Presupuesto creado - Status: ${response.statusCode}');
      return response.statusCode == 201 || response.statusCode == 200;
    } on DioException catch (e) {
      debugPrint('❌ Error al crear presupuesto:');
      debugPrint('❌ Status Code: ${e.response?.statusCode}');
      debugPrint('❌ Response: ${e.response?.data}');
      throw Exception(_mapDioError(e));
    }
  }

  Future<bool> actualizarPresupuesto({
    required String orderId,
    required int productId,
    required int quantity,
  }) async {
    await _ensureInitialized();
    try {
      final orden = await getOrdenCompleta(orderId);
      if (orden == null) return false;

      final lineItems = List<Map<String, dynamic>>.from(orden['line_items'] ?? []);
      final idx = lineItems.indexWhere((item) => item['product_id'] == productId);

      if (idx >= 0) {
        lineItems[idx]['quantity'] = (lineItems[idx]['quantity'] ?? 0) + quantity;
      } else {
        lineItems.add({'product_id': productId, 'quantity': quantity});
      }

      final response = await _dio.put(
        '/wp-json/wc/v3/orders/$orderId',
        data: {'line_items': lineItems},
        options: _wooOptions,
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error actualizando presupuesto: $e');
      return false;
    }
  }

  Future<bool> eliminarProductoPresupuesto({
    required String orderId,
    required int productId,
  }) async {
    await _ensureInitialized();
    try {
      final orden = await getOrdenCompleta(orderId);
      if (orden == null) return false;

      final lineItems = List<Map<String, dynamic>>.from(orden['line_items'] ?? []);
      lineItems.removeWhere((item) => item['product_id'] == productId);

      final response = await _dio.put(
        '/wp-json/wc/v3/orders/$orderId',
        data: {'line_items': lineItems},
        options: _wooOptions,
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error eliminando: $e');
      return false;
    }
  }

  // ================================================================
  // BÚSQUEDA DE PRODUCTOS
  // ================================================================

  Future<List<Product>> buscarProductos(String query) async {
    await _ensureInitialized();
    try {
      final response = await _dio.get(
        '/wp-json/wc/v3/products',
        queryParameters: {'search': query, 'status': 'publish', 'per_page': 50},
        options: _wooOptions,
      );

      final List data = response.data is List ? response.data as List : [];
      final lista = await _mapProductsWithBrand(data);

      lista.sort((a, b) {
        if (a.isInstock && !b.isInstock) return -1;
        if (!a.isInstock && b.isInstock) return 1;
        return 0;
      });

      return lista;
    } catch (e) {
      debugPrint("Error en buscarProductos: $e");
      return [];
    }
  }

  // ================================================================
  // CATEGORÍAS
  // ================================================================

  Future<List<CategoryModel>> getCategorias({
    bool soloConProductos = true,
    bool soloCategoriasPadre = true,
  }) async {
    await _ensureInitialized();
    try {
      int page = 1;
      int totalPages = 1;
      final List<CategoryModel> todas = [];

      do {
        final response = await _dio.get(
          '/wp-json/wc/v3/products/categories',
          queryParameters: {
            'per_page': 100,
            'page': page,
            'orderby': 'name',
            'order': 'asc',
          },
          options: _wooOptions,
        );

        final data = response.data;
        todas.addAll(
          (data as List).map((item) => CategoryModel.fromJson(item)),
        );

        final totalPagesHeader = response.headers.value('x-wp-totalpages');
        totalPages = int.tryParse(totalPagesHeader ?? '1') ?? 1;
        page++;
      } while (page <= totalPages);

      List<CategoryModel> resultado = todas;

      if (soloConProductos) {
        resultado = _filtrarCategoriasVisibles(resultado);
      }

      if (soloCategoriasPadre) {
        resultado = resultado.where((c) => c.parent == 0).toList();
      }

      return resultado;
    } on DioException catch (e) {
      throw Exception(_mapDioError(e));
    }
  }

  Future<List<CategoryModel>> getSubcategoriasDe(int? parentId) async {
    await _ensureInitialized();
    if (parentId == null) return [];
    try {
      final response = await _dio.get(
        '/wp-json/wc/v3/products/categories',
        queryParameters: {
          'parent': parentId,
          'per_page': 100,
          'hide_empty': false,
        },
        options: _wooOptions,
      );
      return (response.data as List)
          .map((json) => CategoryModel.fromJson(json))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<Product>> getProductosPaginado({
    int? categoryId,
    int page = 1,
    int perPage = 30,
    String? brand,
    String? orderBy,
  }) async {
    await _ensureInitialized();
    try {
      final Map<String, dynamic> queryParams = {
        'per_page': perPage,
        'page': page,
        'status': 'publish',
      };
      if (categoryId != null && categoryId > 0) {
        queryParams['category'] = categoryId;
      }

      final response = await _dio.get(
        '/wp-json/wc/v3/products',
        queryParameters: queryParams,
        options: _wooOptions,
      );

      final List data = response.data is List ? response.data as List : [];
      List<Product> productos = await _mapProductsWithBrand(data);

      if (brand != null && brand.isNotEmpty) {
        productos = productos.where((p) => _productMatchesBrand(p, brand)).toList();
      }

      if (orderBy != null) {
        if (orderBy == 'price_asc') {
          productos.sort(
                (a, b) => double.parse(a.price).compareTo(double.parse(b.price)),
          );
        } else if (orderBy == 'price_desc') {
          productos.sort(
                (a, b) => double.parse(b.price).compareTo(double.parse(a.price)),
          );
        }
      }

      return productos;
    } on DioException catch (e) {
      throw Exception("Error: ${e.message}");
    }
  }

  // ================================================================
  // MARCAS
  // ================================================================

  Future<List<Map<String, dynamic>>> getMarcas() async {
    await _ensureInitialized();
    try {
      final response = await _dio.get(
        '/wp-json/wc/v3/products/attributes/pa_marca/terms',
        queryParameters: {'per_page': 100, 'hide_empty': true},
        options: _wooOptions,
      );
      if (response.statusCode == 200) {
        final marcas = (response.data as List).map((term) {
          return {'id': term['id'], 'name': term['name']};
        }).toList();

        _cachedBrandNames = marcas
            .map((brand) => brand['name']?.toString().trim() ?? '')
            .where((brand) => brand.isNotEmpty)
            .toList();

        return marcas;
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // ================================================================
  // FILTRAR CATEGORÍAS
  // ================================================================

  List<CategoryModel> _filtrarCategoriasVisibles(
      List<CategoryModel> categorias,
      ) {
    final Map<int, List<CategoryModel>> hijosPorPadre = {};
    for (final categoria in categorias) {
      hijosPorPadre.putIfAbsent(categoria.parent, () => []).add(categoria);
    }

    bool tieneProductos(CategoryModel cat) {
      if (cat.count > 0) return true;
      final hijos = hijosPorPadre[cat.id] ?? [];
      return hijos.any((h) => tieneProductos(h));
    }

    return categorias.where(tieneProductos).toList();
  }

  // ================================================================
  // ACADEMY / NOTICIAS / BANNERS
  // ================================================================

  Future<List<CourseModel>> getAcademyCourses() async {
    try {
      final response = await _dio.get(
        '/wp-json/wp/v2/posts',
        queryParameters: {'per_page': 10},
      );
      return (response.data as List)
          .map((post) => CourseModel.fromWordPress(post))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<Noticia>> getNoticias() async {
    try {
      final response = await _dio.get(
        '/wp-json/wp/v2/posts',
        queryParameters: {'per_page': 4, '_embed': 'true'},
      );
      return (response.data as List)
          .map((item) => Noticia.fromJson(item))
          .toList();
    } catch (e) {
      throw Exception("Error en noticias");
    }
  }

  Future<List<BannerModel>> getBanners() async {
    try {
      final response = await _dio.get('/wp-json/mundicam/v1/banners');
      return (response.data as List)
          .map((item) => BannerModel.fromJson(item))
          .toList();
    } catch (e) {
      return [];
    }
  }

  // ================================================================
  // ÓRDENES
  // ================================================================

  Future<Map<String, dynamic>?> getOrdenCompleta(String orderId) async {
    await _ensureInitialized();
    try {
      final response = await _dio.get(
        '/wp-json/wc/v3/orders/$orderId',
        options: _wooOptions,
      );
      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('Error al obtener orden $orderId: $e');
      return null;
    }
  }

  Future<List<QuoteMundicam>> getPresupuestosPorEmail(String email) async {
    await _ensureInitialized();
    try {
      final response = await _dio.get(
        '/wp-json/wc/v3/orders',
        queryParameters: {
          'search': email,
          'status': 'checkout-draft',
          'per_page': 50,
        },
        options: _wooOptions,
      );

      debugPrint(
        '📊 Presupuestos encontrados: ${(response.data as List).length}',
      );

      return (response.data as List)
          .map((item) => QuoteMundicam.fromJson(item))
          .toList();
    } catch (e) {
      debugPrint('❌ Error getPresupuestosPorEmail: $e');
      return [];
    }
  }

  // ================================================================
  // PRODUCTO POR ID
  // ================================================================

  Future<Product?> getProductoById(int id) async {
    await _ensureInitialized();
    try {
      final response = await _dio.get(
        '/wp-json/wc/v3/products/$id',
        options: _wooOptions,
      );
      if (response.statusCode == 200) {
        return _mapSingleProductWithBrand(response.data);
      }
      return null;
    } catch (e) {
      debugPrint("Error al obtener producto $id: $e");
      return null;
    }
  }

  // ================================================================
  // RMA
  // ================================================================

  Future<bool> crearRma({
    required String email,
    required int orderId,
    required int productId,
    required String motivo,
    required String descripcion,
  }) async {
    await _ensureInitialized();
    try {
      final data = {
        'email': email,
        'order_id': orderId,
        'product_id': productId,
        'reason': motivo,
        'description': descripcion,
      };

      debugPrint('📝 Creando RMA: ${jsonEncode(data)}');

      final response = await _dio.post(
        '/wp-json/mundicam/v1/rma',
        data: data,
        options: _wooOptions,
      );

      debugPrint('✅ RMA creada - Status: ${response.statusCode}');
      return response.statusCode == 201 || response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ Error al crear RMA: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getRmaRequests(
      String customerEmail,
      ) async {
    await _ensureInitialized();
    try {
      final response = await _dio.get(
        '/wp-json/wc/v3/rma',
        queryParameters: {'email': customerEmail},
        options: _wooOptions,
      );
      return List<Map<String, dynamic>>.from(response.data);
    } catch (e) {
      return [];
    }
  }

  // ================================================================
  // TICKETS
  // ================================================================

  Future<List<Map<String, dynamic>>> getTickets(String customerEmail) async {
    try {
      final response = await _dio.get(
        '/wp-json/wp/v2/posts',
        queryParameters: {
          'search': customerEmail,
          'categories': 'soporte-tecnico',
        },
      );
      return List<Map<String, dynamic>>.from(response.data);
    } catch (e) {
      return [];
    }
  }

  // ================================================================
  // MANEJO DE ERRORES
  // ================================================================

  String _mapDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return 'Tiempo de conexión agotado';
      case DioExceptionType.badResponse:
        if (e.response?.statusCode == 401) {
          return 'Error de autenticación (401). Verifica las credenciales API.';
        }
        if (e.response?.statusCode == 400) {
          final data = e.response?.data;
          if (data is Map && data['message'] != null) {
            return data['message'].toString();
          }
          return 'Solicitud no válida. Revisa los datos del pedido.';
        }
        return 'Error del servidor: ${e.response?.statusCode}';
      default:
        return 'Error de red: ${e.message}';
    }
  }
}
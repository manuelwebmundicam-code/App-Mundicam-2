// services/api_service.dart
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import '../models/banner.dart';
import '../models/cursos_model.dart';
import '../models/noticia.dart';
import '../models/order_model.dart';
import '../models/producto.dart';
import '../models/category_model.dart';
import '../models/quote_model.dart';

class ApiService {
  // Singleton
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late final Dio _dio;
  final FirebaseRemoteConfig _remoteConfig = FirebaseRemoteConfig.instance;

  String _consumerKey = '';
  String _consumerSecret = '';
  bool _initialized = false;

  ApiService._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: 'https://www.mundicam.com',
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {'Accept': 'application/json'},
      ),
    );
    // Cargar keys en segundo plano
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
      if (response.statusCode == 200 && response.data is List && response.data.isNotEmpty) {
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
      if (response.statusCode == 200) return response.data as Map<String, dynamic>;
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

      final List data = response.data;
      List<Product> productos = data.map((item) => Product.fromJson(item)).toList();

      if (brand != null && brand.isNotEmpty) {
        final String queryMarca = brand.toLowerCase().trim();
        productos = productos.where((p) {
          return p.attributes.any((attr) =>
          attr.name.toLowerCase().contains('marca') &&
              attr.options.any((opt) => opt.toLowerCase().trim() == queryMarca));
        }).toList();
      }

      if (orderBy != null) {
        if (orderBy == 'price_asc') {
          productos.sort((a, b) => double.parse(a.price).compareTo(double.parse(b.price)));
        } else if (orderBy == 'price_desc') {
          productos.sort((a, b) => double.parse(b.price).compareTo(double.parse(a.price)));
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
        queryParameters: {
          'search': customerEmail,
          'per_page': 20,
        },
        options: _wooOptions,
      );

      if (response.statusCode == 200) {
        return (response.data as List)
            .map((order) => OrderMundicam.fromJson(order))
            .toList();
      }
      return [];
    } catch (e) {
      print("Error obteniendo pedidos: $e");
      return [];
    }
  }

// ================================================================
// CREAR PEDIDO
// ================================================================
  Future<bool> crearPedido(Map<String, dynamic> orderData) async {
    await _ensureInitialized();
    try {
      debugPrint('📦 Creando pedido...');

      // Forzar status a processing para que envíe emails
      final data = Map<String, dynamic>.from(orderData);
      data['status'] = 'processing';

      final response = await _dio.post(
        '/wp-json/wc/v3/orders',
        data: data,
        options: _wooOptions,
      );

      debugPrint('📦 Status: ${response.statusCode}');

      if (response.statusCode == 201) {
        final orderId = response.data['id'];
        debugPrint('✅ Pedido #$orderId creado correctamente');

        return true;
      }

      debugPrint('❌ Error al crear pedido: ${response.statusCode}');
      debugPrint('   Respuesta: ${response.data}');
      return false;

    } catch (e) {
      debugPrint('❌ Error al crear pedido: $e');
      return false;
    }
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
        'billing': {
          'email': email,
        },
        'line_items': [
          {
            'product_id': productId,
            'quantity': quantity,
          }
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

  // ================================================================
  // BÚSQUEDA DE PRODUCTOS
  // ================================================================
  Future<List<Product>> buscarProductos(String query) async {
    await _ensureInitialized();
    try {
      final response = await _dio.get(
        '/wp-json/wc/v3/products',
        queryParameters: {
          'search': query,
          'status': 'publish',
          'per_page': 50,
        },
        options: _wooOptions,
      );

      final List data = response.data;
      final lista = data.map((item) => Product.fromJson(item)).toList();

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
        todas.addAll((data as List).map((item) => CategoryModel.fromJson(item)));

        final totalPagesHeader = response.headers.value('x-wp-totalpages');
        totalPages = int.tryParse(totalPagesHeader ?? '1') ?? 1;
        page++;
      } while (page <= totalPages);

      List<CategoryModel> resultado = todas;
      if (soloConProductos) resultado = _filtrarCategoriasVisibles(resultado);
      if (soloCategoriasPadre) resultado = resultado.where((c) => c.parent == 0).toList();

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
      return (response.data as List).map((json) => CategoryModel.fromJson(json)).toList();
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

      final List data = response.data;
      List<Product> productos = data.map((item) => Product.fromJson(item)).toList();

      if (brand != null && brand.isNotEmpty) {
        final String queryMarca = brand.toLowerCase().trim();
        productos = productos.where((p) {
          return p.attributes.any((attr) =>
          attr.name.toLowerCase().contains('marca') &&
              attr.options.any((opt) => opt.toLowerCase().trim() == queryMarca));
        }).toList();
      }

      if (orderBy != null) {
        if (orderBy == 'price_asc') {
          productos.sort((a, b) => double.parse(a.price).compareTo(double.parse(b.price)));
        } else if (orderBy == 'price_desc') {
          productos.sort((a, b) => double.parse(b.price).compareTo(double.parse(a.price)));
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
        return (response.data as List).map((term) => {
          'id': term['id'],
          'name': term['name'],
        }).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // ================================================================
  // FILTRAR CATEGORÍAS
  // ================================================================
  List<CategoryModel> _filtrarCategoriasVisibles(List<CategoryModel> categorias) {
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
  // ACADEMY / NOTICIAS / BANNERS (No necesitan WooCommerce)
  // ================================================================
  Future<List<CourseModel>> getAcademyCourses() async {
    try {
      final response = await _dio.get('/wp-json/wp/v2/posts', queryParameters: {'per_page': 10});
      return (response.data as List).map((post) => CourseModel.fromWordPress(post)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<Noticia>> getNoticias() async {
    try {
      final response = await _dio.get('/wp-json/wp/v2/posts', queryParameters: {'per_page': 4, '_embed': 'true'});
      return (response.data as List).map((item) => Noticia.fromJson(item)).toList();
    } catch (e) {
      throw Exception("Error en noticias");
    }
  }

  Future<List<BannerModel>> getBanners() async {
    try {
      final response = await _dio.get('/wp-json/mundicam/v1/banners');
      return (response.data as List).map((item) => BannerModel.fromJson(item)).toList();
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
      if (response.statusCode == 200) return response.data as Map<String, dynamic>;
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
      debugPrint('📊 Presupuestos encontrados: ${(response.data as List).length}');
      return (response.data as List).map((item) => QuoteMundicam.fromJson(item)).toList();
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
      if (response.statusCode == 200) return Product.fromJson(response.data);
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

  Future<List<Map<String, dynamic>>> getRmaRequests(String customerEmail) async {
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
  // TICKETS (No necesita WooCommerce)
  // ================================================================
  Future<List<Map<String, dynamic>>> getTickets(String customerEmail) async {
    try {
      final response = await _dio.get('/wp-json/wp/v2/posts', queryParameters: {
        'search': customerEmail,
        'categories': 'soporte-tecnico'
      });
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
        return 'Error del servidor: ${e.response?.statusCode}';
      default:
        return 'Error de red: ${e.message}';
    }
  }
}
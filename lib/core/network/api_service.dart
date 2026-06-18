import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

class CatalogProductsResult {
  final List<Product> products;
  final int currentPage;
  final int totalPages;
  final int totalItems;

  const CatalogProductsResult({
    required this.products,
    required this.currentPage,
    required this.totalPages,
    required this.totalItems,
  });

  bool get hasNextPage => currentPage < totalPages;
  bool get hasPreviousPage => currentPage > 1;
}




class CatalogFilterDefinition {
  final String key;
  final String title;
  final String taxonomy;
  final int attributeId;

  const CatalogFilterDefinition({
    required this.key,
    required this.title,
    required this.taxonomy,
    required this.attributeId,
  });
}

class CatalogFilterOption {
  final int id;
  final String name;
  final String slug;
  final int count;

  const CatalogFilterOption({
    required this.id,
    required this.name,
    required this.slug,
    required this.count,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'slug': slug,
      'count': count,
      'available_count': count,
    };
  }
}

class CatalogFilterGroup {
  final String key;
  final String title;
  final String taxonomy;
  final int attributeId;
  final List<CatalogFilterOption> options;

  const CatalogFilterGroup({
    required this.key,
    required this.title,
    required this.taxonomy,
    required this.attributeId,
    required this.options,
  });
}

class _CatalogFiltersCacheEntry {
  final List<CatalogFilterGroup> groups;
  final DateTime createdAt;

  const _CatalogFiltersCacheEntry({
    required this.groups,
    required this.createdAt,
  });

  bool get isValid {
    return DateTime.now().difference(createdAt) < const Duration(minutes: 5);
  }
}

class _MarcasDisponiblesCache {
  final List<Map<String, dynamic>> marcas;
  final DateTime timestamp;

  const _MarcasDisponiblesCache({
    required this.marcas,
    required this.timestamp,
  });

  bool get isValid {
    return DateTime.now().difference(timestamp) < const Duration(minutes: 5);
  }
}

class _ContextProductsCacheEntry {
  final List<Product> products;
  final DateTime createdAt;

  const _ContextProductsCacheEntry({
    required this.products,
    required this.createdAt,
  });

  bool get isValid {
    return DateTime.now().difference(createdAt) < const Duration(minutes: 3);
  }
}

class _RequestProductsCacheEntry {
  final CatalogProductsResult result;
  final DateTime createdAt;

  const _RequestProductsCacheEntry({
    required this.result,
    required this.createdAt,
  });

  bool get isValid {
    return DateTime.now().difference(createdAt) < const Duration(minutes: 3);
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
  bool _sessionLoaded = false;
  String _wpSessionCookie = '';
  String _wpNonce = '';
  String _wpCartToken = '';
  String _appToken = '';

  static const String _wpSessionCookiePrefsKey =
      'mundicam_wp_session_cookie';
  static const String _wpNoncePrefsKey = 'mundicam_wp_nonce';
  static const String _wpCartTokenPrefsKey = 'mundicam_wp_cart_token';
  static const String _appTokenPrefsKey = 'mundicam_app_token';
  static const String _appBasePath = '/wp-json/mundicam-app/v1';

  List<String>? _cachedBrandNames;
  List<Map<String, dynamic>>? _cachedBrandTerms;
  final Map<String, _ContextProductsCacheEntry> _contextProductsCache = {};
  final Map<String, _RequestProductsCacheEntry> _requestProductsCache = {};
  static const int _maxRequestProductsCacheEntries = 140;
  final Map<String, _MarcasDisponiblesCache> _marcasDisponiblesCache = {};
  final Map<String, _CatalogFiltersCacheEntry> _catalogFiltersCache = {};
  final Map<int, List<Map<String, dynamic>>> _attributeTermsCache = {};
  final Map<String, Map<int, String>> _localFilterTermLabelsByTaxonomy = {};

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
        headers: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
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

    if (!_sessionLoaded) {
      await _loadWordPressSession();
    }
  }

  // ================================================================
  // SESIÓN WORDPRESS / WOOCOMMERCE DEL CLIENTE
  // ================================================================

  String _normalizeCookieHeader(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return '';

    final cookies = <String>[];
    final parts = raw.split(RegExp(r',\s*(?=[^;,]+=)'));

    for (final part in parts) {
      final firstSegment = part.split(';').first.trim();
      if (firstSegment.isEmpty || !firstSegment.contains('=')) continue;

      final name = firstSegment.split('=').first.trim().toLowerCase();
      if (name == 'path' ||
          name == 'expires' ||
          name == 'max-age' ||
          name == 'domain' ||
          name == 'samesite') {
        continue;
      }

      cookies.add(firstSegment);
    }

    return cookies.isEmpty ? raw : cookies.join('; ');
  }

  Future<void> _loadWordPressSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _wpSessionCookie = prefs.getString(_wpSessionCookiePrefsKey) ?? '';
      _wpNonce = prefs.getString(_wpNoncePrefsKey) ?? '';
      _wpCartToken = prefs.getString(_wpCartTokenPrefsKey) ?? '';
      _appToken = prefs.getString(_appTokenPrefsKey) ?? _wpCartToken;
      _sessionLoaded = true;

      if (kDebugMode && _hasWordPressSession) {
        debugPrint('✅ Sesión MundiCam App API cargada');
      }
    } catch (e) {
      _sessionLoaded = true;
      if (kDebugMode) {
        debugPrint('⚠️ No se pudo cargar la sesión WordPress: $e');
      }
    }
  }

  bool get _hasWordPressSession {
    return _appToken.trim().isNotEmpty ||
        _wpSessionCookie.trim().isNotEmpty ||
        _wpNonce.trim().isNotEmpty ||
        _wpCartToken.trim().isNotEmpty;
  }

  bool get _hasAppToken => _appToken.trim().isNotEmpty;

  /// Permite a LoginPage/AuthWrapper comprobar si Firebase tiene además
  /// una sesión WordPress/WooCommerce válida guardada.
  Future<bool> hasStoredWordPressSession() async {
    await _ensureInitialized();
    return _hasWordPressSession;
  }

  Future<void> saveWordPressSession({
    String? cookie,
    String? nonce,
    String? cartToken,
  }) async {
    final cleanCookie = _normalizeCookieHeader(cookie?.trim() ?? '');
    final cleanNonce = nonce?.trim() ?? '';
    final cleanCartToken = cartToken?.trim() ?? '';

    if (cleanCookie.isEmpty && cleanNonce.isEmpty && cleanCartToken.isEmpty) {
      if (kDebugMode) {
        debugPrint('⚠️ Login sin app_token/cookie/nonce/cart-token. La API privada no podrá autenticarse.');
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    if (cleanCookie.isNotEmpty) {
      _wpSessionCookie = cleanCookie;
      await prefs.setString(_wpSessionCookiePrefsKey, cleanCookie);
    }

    if (cleanNonce.isNotEmpty) {
      _wpNonce = cleanNonce;
      await prefs.setString(_wpNoncePrefsKey, cleanNonce);
    }

    if (cleanCartToken.isNotEmpty) {
      _wpCartToken = cleanCartToken;
      _appToken = cleanCartToken;
      await prefs.setString(_wpCartTokenPrefsKey, cleanCartToken);
      await prefs.setString(_appTokenPrefsKey, cleanCartToken);
    }

    _sessionLoaded = true;

    if (kDebugMode) {
      debugPrint(
        '✅ Sesión MundiCam App API guardada: '
            'cookie=${_wpSessionCookie.isNotEmpty} '
            'nonce=${_wpNonce.isNotEmpty} '
            'appToken=${_appToken.isNotEmpty}',
      );
    }
  }

  Future<void> clearWordPressSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_wpSessionCookiePrefsKey);
    await prefs.remove(_wpNoncePrefsKey);
    await prefs.remove(_wpCartTokenPrefsKey);
    await prefs.remove(_appTokenPrefsKey);

    _wpSessionCookie = '';
    _wpNonce = '';
    _wpCartToken = '';
    _appToken = '';
    _sessionLoaded = true;

    if (kDebugMode) {
      debugPrint('✅ Sesión MundiCam App API limpiada');
    }
  }

  void _captureStoreApiAuthFromResponse(Response response) {
    final setCookieValues = response.headers.map['set-cookie'] ?? const <String>[];
    final setCookie = setCookieValues
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(', ');

    final nonce = response.headers.value('nonce') ??
        response.headers.value('x-wc-store-api-nonce');

    final cartToken = response.headers.value('cart-token') ??
        response.headers.value('x-wc-store-api-cart-token');

    if (setCookie.trim().isEmpty &&
        (nonce == null || nonce.trim().isEmpty) &&
        (cartToken == null || cartToken.trim().isEmpty)) {
      return;
    }

    saveWordPressSession(
      cookie: setCookie.trim().isEmpty ? null : setCookie,
      nonce: nonce,
      cartToken: cartToken,
    );
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

  Options get _storeApiOptions {
    final headers = <String, dynamic>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };

    if (_wpSessionCookie.trim().isNotEmpty) {
      headers['Cookie'] = _wpSessionCookie.trim();
    }

    if (_wpNonce.trim().isNotEmpty) {
      headers['Nonce'] = _wpNonce.trim();
      headers['X-WC-Store-API-Nonce'] = _wpNonce.trim();
    }

    if (_wpCartToken.trim().isNotEmpty) {
      headers['Cart-Token'] = _wpCartToken.trim();
    }

    return Options(headers: headers);
  }


  Options get _appOptions {
    final headers = <String, dynamic>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };

    final token = _appToken.trim().isNotEmpty
        ? _appToken.trim()
        : _wpCartToken.trim();

    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
      headers['X-MundiCam-App-Token'] = token;
    }

    return Options(headers: headers);
  }

  Future<Response<dynamic>> _appGet(
      String path, {
        Map<String, dynamic>? queryParameters,
      }) async {
    await _ensureInitialized();

    if (!_hasAppToken && _wpCartToken.trim().isEmpty) {
      throw DioException(
        requestOptions: RequestOptions(path: '$_appBasePath$path'),
        type: DioExceptionType.badResponse,
        error: 'Falta token de MundiCam App API.',
        message: 'Sesión de app no válida. Vuelve a iniciar sesión.',
      );
    }

    return _dio.get(
      '$_appBasePath$path',
      queryParameters: queryParameters,
      options: _appOptions,
    );
  }

  Future<Response<dynamic>> _appPost(
      String path, {
        Map<String, dynamic>? data,
      }) async {
    await _ensureInitialized();

    if (!_hasAppToken && _wpCartToken.trim().isEmpty) {
      throw DioException(
        requestOptions: RequestOptions(path: '$_appBasePath$path'),
        type: DioExceptionType.badResponse,
        error: 'Falta token de MundiCam App API.',
        message: 'Sesión de app no válida. Vuelve a iniciar sesión.',
      );
    }

    return _dio.post(
      '$_appBasePath$path',
      data: data,
      options: _appOptions,
    );
  }

  List<dynamic> _extractAppList(dynamic data, List<String> keys) {
    if (data is List) return data;
    if (data is Map) {
      for (final key in keys) {
        final value = data[key];
        if (value is List) return value;
      }
    }
    return const <dynamic>[];
  }

  Map<String, dynamic>? _extractAppMap(dynamic data, List<String> keys) {
    if (data is Map) {
      for (final key in keys) {
        final value = data[key];
        if (value is Map) return Map<String, dynamic>.from(value);
      }
      return Map<String, dynamic>.from(data);
    }
    return null;
  }

  int _parseAppTotalPages(dynamic data, {int fallback = 1}) {
    if (data is Map) {
      return _parseIntValue(
        data['total_pages'] ?? data['totalPages'],
        fallback: fallback,
      );
    }
    return fallback;
  }

  int _parseAppTotalItems(dynamic data, {int fallback = 0}) {
    if (data is Map) {
      return _parseIntValue(
        data['total'] ?? data['total_items'] ?? data['totalItems'],
        fallback: fallback,
      );
    }
    return fallback;
  }

  // ================================================================
  // HELPERS GENERALES / LINE ITEMS
  // ================================================================

  int _parseIntValue(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();

    final raw = value.toString().trim();
    if (raw.isEmpty) return fallback;

    return int.tryParse(raw) ?? double.tryParse(raw)?.toInt() ?? fallback;
  }


  List<Map<String, dynamic>> _sanitizeNewOrderLineItems(dynamic rawLineItems) {
    final rawList = rawLineItems is List ? rawLineItems : <dynamic>[];
    final grouped = <String, Map<String, dynamic>>{};

    for (final rawItem in rawList) {
      if (rawItem is! Map) continue;

      final item = Map<String, dynamic>.from(rawItem);
      final productId = _parseIntValue(
        item['product_id'] ?? item['productId'],
      );
      final variationId = _parseIntValue(
        item['variation_id'] ?? item['variationId'],
      );
      final quantity = _parseIntValue(
        item['quantity'] ?? item['qty'],
        fallback: 1,
      );

      if (productId <= 0 || quantity <= 0) continue;

      final key = '$productId-$variationId';

      if (grouped.containsKey(key)) {
        grouped[key]!['quantity'] =
            _parseIntValue(grouped[key]!['quantity']) + quantity;
      } else {
        grouped[key] = {
          'product_id': productId,
          if (variationId > 0) 'variation_id': variationId,
          'quantity': quantity,
        };
      }
    }

    return grouped.values.toList();
  }

  List<Map<String, dynamic>> _buildMinimalWooLineItemsForUpdate(
      dynamic rawLineItems,
      ) {
    final rawList = rawLineItems is List ? rawLineItems : <dynamic>[];
    final result = <Map<String, dynamic>>[];

    for (final rawItem in rawList) {
      if (rawItem is! Map) continue;

      final item = Map<String, dynamic>.from(rawItem);
      final id = _parseIntValue(item['id']);
      final productId = _parseIntValue(item['product_id']);
      final variationId = _parseIntValue(item['variation_id']);
      final quantity = _parseIntValue(item['quantity']);

      if (productId <= 0 || quantity <= 0) continue;

      result.add({
        if (id > 0) 'id': id,
        'product_id': productId,
        if (variationId > 0) 'variation_id': variationId,
        'quantity': quantity,
      });
    }

    return result;
  }

  void _debugLineItems(String title, List<Map<String, dynamic>> lineItems) {
    if (!kDebugMode) return;

    debugPrint('════════ $title ════════');
    debugPrint('🧾 Total líneas: ${lineItems.length}');

    for (final item in lineItems) {
      debugPrint(
        '➡️ product_id: ${item['product_id']} | '
            'variation_id: ${item['variation_id'] ?? '-'} | '
            'qty: ${item['quantity']}',
      );
    }

    debugPrint('════════════════════════════');
  }


  // ================================================================
  // NORMALIZACIÓN / MARCAS
  // ================================================================

  String _normalizeBrandValue(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('ä', 'a')
        .replaceAll('â', 'a')
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ì', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('î', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ò', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ù', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('û', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[\s\-_]+'), '')
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  bool _isBrandAttributeName(String value) {
    final normalized = _normalizeBrandValue(value);
    return normalized.contains('marca') ||
        normalized.contains('brand') ||
        normalized.contains('fabricante') ||
        normalized.contains('manufacturer') ||
        normalized == 'pamarca' ||
        normalized == 'pamarcas' ||
        normalized == 'pafabricante' ||
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
      final terms = await getMarcas(hideEmpty: false);
      for (final term in terms) {
        final name = term['name']?.toString().trim();
        if (name != null && name.isNotEmpty) {
          brands.add(name);
        }
        final slug = term['slug']?.toString().trim();
        if (slug != null && slug.isNotEmpty) {
          brands.add(slug);
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

  // ================================================================
  // BÚSQUEDA TÉCNICA EXPANDIDA / SINÓNIMOS
  // ================================================================

  String _compactSearchText(String value) {
    return _normalizeBrandValue(value);
  }

  List<String> _technicalSearchTokens(String value) {
    final normalized = value
        .toLowerCase()
        .trim()
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('ä', 'a')
        .replaceAll('â', 'a')
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ì', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('î', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ò', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ù', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('û', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ');

    final stopWords = <String>{
      'de',
      'del',
      'la',
      'el',
      'los',
      'las',
      'para',
      'con',
      'en',
      'un',
      'una',
      'y',
      'o',
    };

    return normalized
        .split(RegExp(r'\s+'))
        .map((token) => token.trim())
        .where((token) => token.length >= 2 && !stopWords.contains(token))
        .toList();
  }

  bool _looksLikeTechnicalSkuSearch(String value) {
    final compact = value.replaceAll(' ', '');
    final hasDigit = RegExp(r'\d').hasMatch(compact);
    final hasSkuSeparator = RegExp(r'[-_/()]').hasMatch(compact);
    final hasUpperPrefix = RegExp(r'^[A-Za-z]{2,}[-_]').hasMatch(compact);
    return compact.length >= 4 &&
        (hasDigit && (hasSkuSeparator || hasUpperPrefix || compact.length >= 7));
  }

  bool _isGenericCatalogSearchToken(String token) {
    final compact = _compactSearchText(token);
    return <String>{
      'camara',
      'camaras',
      'camera',
      'cctv',
      'video',
      'ip',
      'hd',
      'producto',
      'productos',
      'ref',
      'referencia',
    }.contains(compact);
  }

  List<String> _technicalVariantsForSearchToken(String token) {
    final compact = _compactSearchText(token);
    final variants = <String>{compact};

    switch (compact) {
      case 'domo':
      case 'dome':
      case 'turret':
      case 'minidomo':
        variants.addAll(['domo', 'dome', 'turret', 'minidomo']);
        break;
      case 'bullet':
      case 'tubular':
      case 'tubo':
        variants.addAll(['bullet', 'tubular', 'tubo']);
        break;
      case 'grabador':
      case 'grabadores':
      case 'nvr':
      case 'xvr':
      case 'dvr':
        variants.addAll(['grabador', 'grabadores', 'nvr', 'xvr', 'dvr']);
        break;
      case 'matricula':
      case 'matriculas':
      case 'anpr':
      case 'lpr':
        variants.addAll(['matricula', 'matriculas', 'anpr', 'lpr']);
        break;
      case 'wifi':
      case 'wireless':
        variants.addAll(['wifi', 'wi-fi', 'wireless']);
        break;
      case '8':
      case '8mp':
      case '8mpx':
        variants.addAll(['8mp', '8mpx', '8megapixel', '8megapixeles', '4k']);
        break;
      case '5':
      case '5mp':
      case '5mpx':
        variants.addAll(['5mp', '5mpx', '5megapixel', '5megapixeles']);
        break;
      case '4':
      case '4mp':
      case '4mpx':
        variants.addAll(['4mp', '4mpx', '4megapixel', '4megapixeles']);
        break;
      case '2':
      case '2mp':
      case '2mpx':
        variants.addAll(['2mp', '2mpx', '2megapixel', '2megapixeles']);
        break;
    }

    if (compact.endsWith('s') && compact.length > 3) {
      variants.add(compact.substring(0, compact.length - 1));
    }

    return variants.where((item) => item.trim().isNotEmpty).toList();
  }

  List<List<String>> _technicalSearchVariantGroups(String search) {
    final groups = <List<String>>[];

    for (final token in _technicalSearchTokens(search)) {
      if (_isGenericCatalogSearchToken(token)) {
        continue;
      }

      final variants = _technicalVariantsForSearchToken(token)
          .map(_compactSearchText)
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList();

      if (variants.isNotEmpty) {
        groups.add(variants);
      }
    }

    return groups;
  }

  String? _effectiveCatalogSearchTerm(String? search) {
    final cleanSearch = search?.trim();
    if (cleanSearch == null || cleanSearch.isEmpty) return null;

    // Si parece una referencia/SKU, no tocamos nada.
    if (_looksLikeTechnicalSkuSearch(cleanSearch)) {
      return cleanSearch;
    }

    final tokens = _technicalSearchTokens(cleanSearch);
    if (tokens.isEmpty) return cleanSearch;

    final meaningfulTokens = tokens
        .where((token) => !_isGenericCatalogSearchToken(token))
        .toList();

    if (meaningfulTokens.isEmpty) {
      return cleanSearch;
    }

    final removedGenericTokens = meaningfulTokens.length < tokens.length;
    final hasTechnicalToken = meaningfulTokens.any((token) {
      final compact = _compactSearchText(token);
      return _technicalVariantsForSearchToken(compact).length > 1 ||
          RegExp(r'^\d+mpx?$').hasMatch(compact) ||
          RegExp(r'^\d+$').hasMatch(compact);
    });

    // Evita búsquedas tipo “cámara bullet IP” → WooCommerce interpreta “IP”
    // demasiado amplio y devuelve toda la categoría. En ese caso buscamos
    // realmente “bullet”, “domo”, “grabador”, etc.
    if (removedGenericTokens && hasTechnicalToken) {
      return meaningfulTokens.join(' ');
    }

    return cleanSearch;
  }

  bool _shouldUseExpandedTechnicalSearch(String? search) {
    final cleanSearch = search?.trim();
    if (cleanSearch == null || cleanSearch.length < 3) return false;
    if (_looksLikeTechnicalSkuSearch(cleanSearch)) return false;

    final groups = _technicalSearchVariantGroups(cleanSearch);
    if (groups.length < 2) return false;

    // Solo expandimos cuando hay una búsqueda compuesta real, por ejemplo
    // “bullet 4mp” o “domo 8mp”. Una búsqueda simple como “domo”, “bullet”
    // o “grabador” debe ir directa a WooCommerce para ser rápida.
    final hasSynonyms = groups.any((group) => group.length > 1);
    return hasSynonyms;
  }

  bool _productMatchesTechnicalSearchGroups(
      Product product,
      List<List<String>> groups,
      ) {
    if (groups.isEmpty) return true;

    final compactText = _compactSearchText([
      product.name,
      product.sku,
      product.shortDescription,
      product.description,
      product.brandName ?? '',
      ...product.attributes.expand((attr) => [attr.name, ...attr.options]),
    ].join(' '));

    for (final group in groups) {
      final matchesGroup = group.any((variant) => compactText.contains(variant));
      if (!matchesGroup) return false;
    }

    return true;
  }


  bool _isAccessorySearch(String? value) {
    final compact = _compactSearchText(value ?? '');
    return RegExp(
      r'(cable|cables|rj45|rj45|latiguillo|latiguillos|conector|conectores|utp|ftp|cat5|cat6|cat7|bnc|coaxial|patch|pila|pilas|bateria|baterias|fuente|fuentes|alimentador|alimentacion|transformador|adaptador|cargador)',
    ).hasMatch(compact);
  }

  bool _isConnectivityAccessorySearch(String? value) {
    final compact = _compactSearchText(value ?? '');
    return RegExp(
      r'(cable|cables|rj45|rj45|latiguillo|latiguillos|conector|conectores|utp|ftp|cat5|cat6|cat7|bnc|coaxial|patch)',
    ).hasMatch(compact);
  }

  bool _isPowerAccessorySearch(String? value) {
    final compact = _compactSearchText(value ?? '');
    return RegExp(
      r'(pila|pilas|bateria|baterias|fuente|fuentes|alimentador|alimentacion|transformador|adaptador|cargador)',
    ).hasMatch(compact);
  }

  List<String> _accessorySearchTerms(String search) {
    final compact = _compactSearchText(search);
    final terms = <String>{search.trim()};

    if (_isConnectivityAccessorySearch(search)) {
      if (compact.contains('rj45') || compact.contains('rj')) {
        terms.addAll(['rj45', 'cable rj45', 'latiguillo rj45', 'conector rj45']);
      }
      if (compact.contains('cat6')) {
        terms.addAll(['cat6', 'cable cat6', 'utp cat6', 'bobina cat6']);
      }
      if (compact.contains('cat5')) {
        terms.addAll(['cat5', 'cable cat5', 'utp cat5']);
      }
      if (compact.contains('cable')) {
        terms.addAll(['cable', 'latiguillo', 'utp', 'ftp']);
      }
      if (compact.contains('latiguillo')) {
        terms.addAll(['latiguillo', 'latiguillo rj45', 'cable red']);
      }
      if (compact.contains('conector')) {
        terms.addAll(['conector', 'conector rj45', 'conector bnc']);
      }
      if (compact.contains('bnc')) {
        terms.addAll(['bnc', 'conector bnc']);
      }
      if (compact.contains('coaxial')) {
        terms.addAll(['coaxial', 'cable coaxial']);
      }
    }

    if (_isPowerAccessorySearch(search)) {
      if (compact.contains('pila')) {
        terms.addAll(['pila', 'pilas', 'pila litio']);
      }
      if (compact.contains('bateria')) {
        terms.addAll(['bateria', 'batería', 'baterias']);
      }
      if (compact.contains('fuente') || compact.contains('aliment')) {
        terms.addAll(['fuente', 'fuente alimentacion', 'alimentador', 'transformador']);
      }
    }

    return terms
        .map((term) => term.trim())
        .where((term) => term.length >= 3)
        .toSet()
        .take(8)
        .toList();
  }

  int _accessoryProductScore(Product product, String search) {
    final compactSearch = _compactSearchText(search);
    final strongText = _compactSearchText([
      product.name,
      product.sku,
      product.brandName ?? '',
    ].join(' '));

    if (strongText.isEmpty) return 0;

    final connectivity = _isConnectivityAccessorySearch(search);
    final power = _isPowerAccessorySearch(search);

    if (connectivity) {
      final hasConnectivityName = RegExp(
        r'(cable|latiguillo|conector|rj45|utp|ftp|cat5|cat6|cat7|bnc|coaxial|patch|bobina)',
      ).hasMatch(strongText);
      if (!hasConnectivityName) return 0;
    }

    if (power) {
      final hasPowerName = RegExp(
        r'(pila|pilas|bateria|baterias|fuente|alimentador|alimentacion|transformador|adaptador|cargador|batt)',
      ).hasMatch(strongText);
      if (!hasPowerName) return 0;
    }

    int score = 0;
    if (strongText.contains(compactSearch)) score += 80;

    final compactTokens = _technicalSearchTokens(search)
        .map(_compactSearchText)
        .where((token) => token.length >= 2)
        .toList();

    for (final token in compactTokens) {
      if (token == 'rj' || token == '45') continue;
      if (strongText.contains(token)) score += 20;
    }

    if (connectivity && RegExp(r'(cable|latiguillo|conector|bobina)').hasMatch(strongText)) score += 30;
    if (connectivity && strongText.contains('rj45')) score += 25;
    if (connectivity && strongText.contains('cat6')) score += 25;
    if (power && RegExp(r'(pila|bateria|fuente|alimentador)').hasMatch(strongText)) score += 35;
    if (product.isInstock) score += 3;

    return score;
  }

  Future<CatalogProductsResult> _getAccessorySearchCatalogResult({
    int? categoryId,
    required String search,
    required int page,
    required int perPage,
    String? orderBy,
  }) async {
    final productsById = <int, Product>{};
    final terms = _accessorySearchTerms(search);

    for (final term in terms.take(5)) {
      try {
        final queryParams = <String, dynamic>{
          'per_page': 100,
          'page': 1,
          'status': 'publish',
          'search': term,
        };

        if (categoryId != null && categoryId > 0) {
          queryParams['category'] = categoryId.toString();
        }

        _applyProductOrderParams(queryParams, orderBy);

        final result = await _requestCatalogProducts(
          queryParams,
          page: 1,
          perPage: 100,
        ).timeout(const Duration(seconds: 4));

        for (final product in result.products) {
          if (_accessoryProductScore(product, search) > 0) {
            productsById[product.id] = product;
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Búsqueda accesorio agotada para "$term": $e');
        }
      }
    }

    final products = productsById.values.toList();
    _sortProductsByRequestedOrder(products, orderBy);

    if (kDebugMode) {
      debugPrint(
        '🔌 Búsqueda accesorio filtrada: category=$categoryId search="$search" terms=$terms total=${products.length}',
      );
    }

    return _paginateLocalProducts(
      products: products,
      page: page,
      perPage: perPage,
    );
  }

  List<String> _technicalSearchApiTerms(String search) {
    final cleanSearch = search.trim();
    final groups = _technicalSearchVariantGroups(search);
    final terms = <String>{cleanSearch};

    if (groups.isEmpty) {
      return terms.toList();
    }

    final groupLabels = groups.map((group) => group.first).toList();

    if (groupLabels.isNotEmpty) {
      terms.add(groupLabels.join(' '));
    }

    for (final group in groups) {
      for (final variant in group.take(4)) {
        terms.add(variant);
      }
    }

    // Evitamos búsquedas demasiado genéricas que en WooCommerce pueden devolver
    // toda la familia por palabras como “ip” o “cámara”.
    return terms
        .where((term) => term.trim().length >= 3)
        .where((term) => !_isGenericCatalogSearchToken(term))
        .take(8)
        .toList();
  }

  Future<List<Product>> _getLimitedProductsForTechnicalSearchTerm({
    int? categoryId,
    required String search,
    String? orderBy,
    int maxPages = 2,
  }) async {
    final queryParams = <String, dynamic>{
      'per_page': 100,
      'page': 1,
      'status': 'publish',
    };

    if (categoryId != null && categoryId > 0) {
      queryParams['category'] = categoryId.toString();
    }

    final effectiveSearch = _effectiveCatalogSearchTerm(search);
    if (effectiveSearch != null && effectiveSearch.trim().isNotEmpty) {
      queryParams['search'] = effectiveSearch.trim();
    }

    _applyProductOrderParams(queryParams, orderBy);

    final products = <Product>[];
    var page = 1;
    var totalPages = 1;

    do {
      final pageParams = Map<String, dynamic>.from(queryParams)..['page'] = page;
      final result = await _requestCatalogProducts(
        pageParams,
        page: page,
        perPage: 100,
      );

      products.addAll(result.products);
      totalPages = result.totalPages;
      page++;
    } while (page <= totalPages && page <= maxPages);

    return products;
  }

  Future<CatalogProductsResult> _getExpandedTechnicalSearchCatalogResult({
    int? categoryId,
    int? brandId,
    required String search,
    required int page,
    required int perPage,
    String? orderBy,
  }) async {
    final groups = _technicalSearchVariantGroups(search);
    final terms = _technicalSearchApiTerms(search);
    final productsById = <int, Product>{};

    for (final term in terms.take(3)) {
      try {
        final contextProducts = await _getLimitedProductsForTechnicalSearchTerm(
          categoryId: categoryId,
          search: term,
          orderBy: orderBy,
        ).timeout(const Duration(seconds: 4));

        for (final product in contextProducts) {
          if (_productMatchesTechnicalSearchGroups(product, groups)) {
            productsById[product.id] = product;
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Búsqueda expandida rápida agotada para "$term": $e');
        }
      }
    }

    List<Product> products = productsById.values.toList();

    if (brandId != null && brandId > 0) {
      final brandName = await getMarcaNombrePorId(brandId);
      if (brandName != null && brandName.trim().isNotEmpty) {
        products = products
            .where((product) => _productMatchesBrand(product, brandName))
            .toList();
      }
    }

    _sortProductsByRequestedOrder(products, orderBy);

    final result = _paginateLocalProducts(
      products: products,
      page: page,
      perPage: perPage,
    );

    if (kDebugMode) {
      debugPrint(
        '🔎 Búsqueda técnica expandida: category=$categoryId '
            'brandId=$brandId search="$search" terms=$terms total=${products.length}',
      );
    }

    return result;
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

  double _productPrice(Product product) {
    return double.tryParse(product.price.replaceAll(',', '.').trim()) ?? 0.0;
  }

  bool _isExplicitCatalogOrder(String? orderBy) {
    final value = orderBy?.trim();
    return value == 'price_asc' || value == 'price_desc' || value == 'date';
  }

  String? _orderByFromProductQueryParams(Map<String, dynamic> queryParams) {
    final orderBy = queryParams['orderby']?.toString().trim();
    final order = queryParams['order']?.toString().trim().toLowerCase();

    if (orderBy == 'price' && order == 'asc') {
      return 'price_asc';
    }

    if (orderBy == 'price' && order == 'desc') {
      return 'price_desc';
    }

    if (orderBy == 'date') {
      return 'date';
    }

    return null;
  }

  void _sortProductsByRequestedOrder(
      List<Product> products,
      String? orderBy,
      ) {
    final value = orderBy?.trim();

    if (products.length < 2) return;

    if (value == 'price_asc') {
      products.sort((a, b) {
        final comparePrice = _productPrice(a).compareTo(_productPrice(b));
        if (comparePrice != 0) return comparePrice;
        return b.id.compareTo(a.id);
      });
      return;
    }

    if (value == 'price_desc') {
      products.sort((a, b) {
        final comparePrice = _productPrice(b).compareTo(_productPrice(a));
        if (comparePrice != 0) return comparePrice;
        return b.id.compareTo(a.id);
      });
      return;
    }

    if (value == 'date' || value == null || value.isEmpty) {
      products.sort((a, b) => b.id.compareTo(a.id));
    }
  }

  CatalogProductsResult _sortCatalogResultPage(
      CatalogProductsResult result,
      String? orderBy,
      ) {
    final products = [...result.products];
    _sortProductsByRequestedOrder(products, orderBy);

    return CatalogProductsResult(
      products: products,
      currentPage: result.currentPage,
      totalPages: result.totalPages,
      totalItems: result.totalItems,
    );
  }

  int _parseHeaderInt(Headers headers, String key, int fallback) {
    return int.tryParse(headers.value(key) ?? '') ?? fallback;
  }

  void _applyProductOrderParams(
      Map<String, dynamic> queryParams,
      String? orderBy,
      ) {
    switch (orderBy) {
      case 'price_asc':
        queryParams['orderby'] = 'price';
        queryParams['order'] = 'asc';
        break;
      case 'price_desc':
        queryParams['orderby'] = 'price';
        queryParams['order'] = 'desc';
        break;
      case 'date':
      case null:
      case '':
        queryParams['orderby'] = 'date';
        queryParams['order'] = 'desc';
        break;
      default:
        queryParams['orderby'] = 'date';
        queryParams['order'] = 'desc';
        break;
    }
  }

  int? _termIdFromDynamic(dynamic value) {
    if (value is int && value > 0) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  Future<List<Map<String, dynamic>>> _getAllBrandTermsForLookup({
    bool hideEmpty = false,
  }) async {
    final allTerms = <Map<String, dynamic>>[];

    Future<void> addTerms(Future<List<Map<String, dynamic>>> future) async {
      try {
        final terms = await future.timeout(const Duration(seconds: 5));
        for (final term in terms) {
          final id = _termIdFromDynamic(term['id']);
          final name = term['name']?.toString().trim() ?? '';
          if (id == null || id <= 0 || name.isEmpty) continue;

          final alreadyExists = allTerms.any((item) {
            final itemId = _termIdFromDynamic(item['id']);
            final itemName = item['name']?.toString().trim() ?? '';
            final itemSlug = item['slug']?.toString().trim() ?? '';
            final slug = term['slug']?.toString().trim() ?? '';
            return itemId == id ||
                _normalizeBrandValue(itemName) == _normalizeBrandValue(name) ||
                (slug.isNotEmpty &&
                    itemSlug.isNotEmpty &&
                    _normalizeBrandValue(itemSlug) == _normalizeBrandValue(slug));
          });

          if (!alreadyExists) {
            allTerms.add(term);
          }
        }
      } catch (_) {
        // No bloqueamos si una fuente de marcas/fabricantes falla.
      }
    }

    // En MundiCam el fabricante principal de la web es el atributo pa_marcas.
    // Se carga primero para que la app filtre como la web.
    await addTerms(_getBrandTermsFromAttributeTerms(hideEmpty: hideEmpty));

    // Compatibilidad con WooCommerce Brands / Product Brands y Store API.
    await addTerms(_getBrandTermsFromStoreApi(hideEmpty: hideEmpty));
    await addTerms(_getBrandTermsFromWooBrandsApi(hideEmpty: hideEmpty));

    // Fallback de la versión anterior: instalaciones donde la marca fuera pa_marca.
    await addTerms(_getBrandTermsFromLegacyMarcaAttributeTerms(hideEmpty: hideEmpty));

    allTerms.sort(
          (a, b) => (a['name']?.toString().toLowerCase() ?? '').compareTo(
        b['name']?.toString().toLowerCase() ?? '',
      ),
    );

    return allTerms;
  }

  Future<int?> getMarcaIdPorNombre(String? brandName) async {
    final value = brandName?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }

    final marcas = await _getAllBrandTermsForLookup(hideEmpty: false);
    final normalizedValue = _normalizeBrandValue(value);

    for (final marca in marcas) {
      final id = _termIdFromDynamic(marca['id']);
      if (id == null || id <= 0) continue;

      final name = marca['name']?.toString() ?? '';
      final slug = marca['slug']?.toString() ?? '';

      if (_normalizeBrandValue(name) == normalizedValue ||
          _normalizeBrandValue(slug) == normalizedValue) {
        return id;
      }
    }

    return null;
  }

  Future<String?> getMarcaNombrePorId(int? brandId) async {
    if (brandId == null || brandId <= 0) return null;

    final marcas = await _getAllBrandTermsForLookup(hideEmpty: false);

    for (final marca in marcas) {
      final id = _termIdFromDynamic(marca['id']);
      if (id == brandId) {
        final name = marca['name']?.toString().trim();
        return name == null || name.isEmpty ? null : name;
      }
    }

    return null;
  }

  List<Map<String, dynamic>> _normalizeBrandTerms(
      dynamic data, {
        required String source,
      }) {
    if (data is! List) return [];

    final marcas = <Map<String, dynamic>>[];

    for (final rawTerm in data) {
      if (rawTerm is! Map) continue;

      final term = Map<dynamic, dynamic>.from(rawTerm);
      final id = _termIdFromDynamic(term['id']);
      final name = term['name']?.toString().trim() ??
          term['label']?.toString().trim() ??
          '';
      final slug = term['slug']?.toString().trim() ?? '';
      final count = int.tryParse(term['count']?.toString() ?? '') ?? 0;

      if (id == null || id <= 0 || name.isEmpty) {
        continue;
      }

      marcas.add({
        'id': id,
        'name': name,
        'slug': slug,
        'count': count,
        'source': source,
      });
    }

    marcas.sort(
          (a, b) => (a['name']?.toString().toLowerCase() ?? '').compareTo(
        b['name']?.toString().toLowerCase() ?? '',
      ),
    );

    return marcas;
  }

  Future<List<Map<String, dynamic>>> _getBrandTermsFromStoreApi({
    required bool hideEmpty,
  }) async {
    try {
      final response = await _dio.get(
        '/wp-json/wc/store/v1/products/brands',
        queryParameters: {
          'per_page': 100,
          'hide_empty': hideEmpty,
        },
        options: _storeApiOptions,
      );

      final marcas = _normalizeBrandTerms(
        response.data,
        source: 'store_brand',
      );

      if (kDebugMode) {
        debugPrint('🏷️ Marcas Store API: ${marcas.length}');
      }

      return marcas;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Store API brands no disponible: $e');
      }
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _getBrandTermsFromWooBrandsApi({
    required bool hideEmpty,
  }) async {
    try {
      final response = await _dio.get(
        '/wp-json/wc/v3/products/brands',
        queryParameters: {
          'per_page': 100,
          'hide_empty': hideEmpty,
        },
        options: _wooOptions,
      );

      final marcas = _normalizeBrandTerms(
        response.data,
        source: 'wc_brand',
      );

      if (kDebugMode) {
        debugPrint('🏷️ Marcas WC Brands: ${marcas.length}');
      }

      return marcas;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ WC products/brands no disponible: $e');
      }
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _getBrandTermsFromAttributeTerms({
    required bool hideEmpty,
  }) async {
    try {
      int page = 1;
      int totalPages = 1;
      final marcas = <Map<String, dynamic>>[];

      do {
        final response = await _dio.get(
          '/wp-json/wc/v3/products/attributes/26/terms',
          queryParameters: {
            'per_page': 100,
            'page': page,
            'hide_empty': hideEmpty,
          },
          options: _wooOptions,
        );

        marcas.addAll(
          _normalizeBrandTerms(
            response.data,
            source: 'pa_marcas',
          ),
        );

        totalPages = _parseHeaderInt(response.headers, 'x-wp-totalpages', 1);
        page++;
      } while (page <= totalPages);

      if (kDebugMode) {
        debugPrint('🏷️ Fabricantes pa_marcas: ${marcas.length}');
      }

      return marcas;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ pa_marcas terms no disponible: $e');
      }
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _getBrandTermsFromLegacyMarcaAttributeTerms({
    required bool hideEmpty,
  }) async {
    try {
      int page = 1;
      int totalPages = 1;
      final marcas = <Map<String, dynamic>>[];

      do {
        final response = await _dio.get(
          '/wp-json/wc/v3/products/attributes/pa_marca/terms',
          queryParameters: {
            'per_page': 100,
            'page': page,
            'hide_empty': hideEmpty,
          },
          options: _wooOptions,
        );

        marcas.addAll(
          _normalizeBrandTerms(
            response.data,
            source: 'pa_marca',
          ),
        );

        totalPages = _parseHeaderInt(response.headers, 'x-wp-totalpages', 1);
        page++;
      } while (page <= totalPages);

      if (kDebugMode) {
        debugPrint('🏷️ Marcas legacy pa_marca: ${marcas.length}');
      }

      return marcas;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ pa_marca legacy terms no disponible: $e');
      }
      return [];
    }
  }

  String _requestProductsCacheKey(
      Map<String, dynamic> queryParams, {
        required int page,
        required int perPage,
      }) {
    final sortedKeys = queryParams.keys.map((key) => key.toString()).toList()
      ..sort();
    final queryPart = sortedKeys
        .map((key) => '$key=${queryParams[key]?.toString() ?? ''}')
        .join('&');
    return 'page:$page|perPage:$perPage|$queryPart';
  }
  Map<String, dynamic> _storeApiQueryFromWooProductsQuery(
      Map<String, dynamic> queryParams, {
        required int page,
        required int perPage,
      }) {
    final query = <String, dynamic>{
      'per_page': perPage,
      'page': page,
    };

    final search = queryParams['search']?.toString().trim();
    if (search != null && search.isNotEmpty) {
      query['search'] = search;
    }

    final category = queryParams['category']?.toString().trim();
    if (category != null && category.isNotEmpty) {
      query['category'] = category;
      query['category_operator'] = queryParams['category_operator'] ?? 'in';
    }

    final orderBy = queryParams['orderby']?.toString().trim();
    final order = queryParams['order']?.toString().trim();

    if (orderBy != null && orderBy.isNotEmpty) {
      query['orderby'] = orderBy;
    }

    if (order != null && order.isNotEmpty) {
      query['order'] = order;
    }

    // Compatibilidad básica con filtros por atributo en Store API.
    // Si el endpoint público no soporta algún filtro, no debe bloquear al cliente:
    // el resultado se valida después en las capas locales cuando corresponde.
    final attribute = queryParams['attribute']?.toString().trim();
    final attributeTerm = queryParams['attribute_term']?.toString().trim();
    if (attribute != null &&
        attribute.isNotEmpty &&
        attributeTerm != null &&
        attributeTerm.isNotEmpty) {
      query['attributes[0][attribute]'] = attribute;
      query['attributes[0][term_id]'] = attributeTerm;
    }

    final brand = queryParams['brand']?.toString().trim();
    if (brand != null && brand.isNotEmpty) {
      query['brand'] = brand;
      query['brand_operator'] = queryParams['brand_operator'] ?? 'in';
    }

    return query;
  }

  String _storeApiPriceToWooPrice(dynamic value, {int minorUnit = 2}) {
    if (value == null) return '0.00';

    final raw = value.toString().trim().replaceAll(',', '.');
    if (raw.isEmpty) return '0.00';

    final parsed = double.tryParse(raw);
    if (parsed == null) return raw;

    if (minorUnit <= 0) {
      return parsed.toStringAsFixed(0);
    }

    final divisor = List<int>.filled(minorUnit, 10).fold<double>(
      1,
          (total, item) => total * item,
    );

    return (parsed / divisor).toStringAsFixed(2);
  }

  Map<String, dynamic> _normalizeStoreProductForProductModel(
      Map<String, dynamic> raw,
      ) {
    final json = Map<String, dynamic>.from(raw);
    final prices = json['prices'];

    if (prices is Map) {
      final priceMap = Map<dynamic, dynamic>.from(prices);
      final minorUnit = _parseIntValue(
        priceMap['currency_minor_unit'],
        fallback: 2,
      );

      json['price'] = _storeApiPriceToWooPrice(
        priceMap['price'],
        minorUnit: minorUnit,
      );
      json['regular_price'] = _storeApiPriceToWooPrice(
        priceMap['regular_price'] ?? priceMap['price'],
        minorUnit: minorUnit,
      );
    }

    final rawStockStatus = json['stock_status']?.toString().trim() ?? '';
    final rawIsInStock = json['is_in_stock'];
    final parsedIsInStock = rawIsInStock == true ||
        rawIsInStock?.toString().toLowerCase().trim() == 'true' ||
        rawIsInStock?.toString().trim() == '1';
    final parsedOutOfStock = rawIsInStock == false ||
        rawIsInStock?.toString().toLowerCase().trim() == 'false' ||
        rawIsInStock?.toString().trim() == '0';

    // En cliente normal WooCommerce REST v3 puede devolver 403 y usamos Store API.
    // Algunas instalaciones B2B no exponen todos los campos comerciales en Store API.
    // Si Store API NO declara explícitamente sin stock, el producto debe seguir siendo
    // operable para el cliente. El stock exacto General/Murcia se oculta por rol en UI.
    if (rawStockStatus.isNotEmpty) {
      json['stock_status'] = rawStockStatus;
    } else if (parsedOutOfStock) {
      json['stock_status'] = 'outofstock';
    } else if (parsedIsInStock) {
      json['stock_status'] = 'instock';
    } else {
      json['stock_status'] = 'instock';
    }

    json['is_in_stock'] = json['stock_status'] == 'instock' ||
        json['stock_status'] == 'onbackorder';

    // En la app B2B, el cliente identificado no debe comportarse como invitado.
    // Store API puede devolver purchasable=false por reglas de Woo/B2B aunque la app
    // deba permitir añadir al carrito/presupuesto. La clase Product solo bloqueará
    // si el texto comercial indica explícitamente “Bajo consulta”.
    json['is_purchasable'] = true;
    json['purchasable'] = true;

    return json;
  }


  // IMPORTANTE: este fallback de Store API se mantiene solo por compatibilidad
  // con consultas no comerciales. _requestCatalogProducts NO debe usarlo para
  // catálogo comprable, porque Store API pública puede devolver precios 0 en B2B.
  Future<CatalogProductsResult> _requestStoreApiProductsFallback(
      Map<String, dynamic> queryParams, {
        required int page,
        required int perPage,
      }) async {
    final storeQuery = _storeApiQueryFromWooProductsQuery(
      queryParams,
      page: page,
      perPage: perPage,
    );

    Response response;
    try {
      response = await _dio.get(
        '/wp-json/wc/store/v1/products',
        queryParameters: storeQuery,
        options: _storeApiOptions,
      );
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;

      if (statusCode == 400 || statusCode == 401 || statusCode == 403) {
        final safeQuery = <String, dynamic>{
          'per_page': perPage,
          'page': page,
        };

        final search = queryParams['search']?.toString().trim();
        if (search != null && search.isNotEmpty) {
          safeQuery['search'] = search;
        }

        final category = queryParams['category']?.toString().trim();
        if (category != null && category.isNotEmpty) {
          safeQuery['category'] = category;
          safeQuery['category_operator'] = 'in';
        }

        final orderBy = queryParams['orderby']?.toString().trim();
        final order = queryParams['order']?.toString().trim();
        if (orderBy != null && orderBy.isNotEmpty) safeQuery['orderby'] = orderBy;
        if (order != null && order.isNotEmpty) safeQuery['order'] = order;

        if (kDebugMode) {
          debugPrint(
            '⚠️ Store API no aceptó el filtro avanzado de productos '
                '(status=$statusCode). Reintentando consulta pública básica.',
          );
        }

        response = await _dio.get(
          '/wp-json/wc/store/v1/products',
          queryParameters: safeQuery,
          options: _storeApiOptions,
        );
      } else {
        rethrow;
      }
    }

    _captureStoreApiAuthFromResponse(response);

    final List data = response.data is List ? response.data as List : [];
    final productos = await _mapProductsWithBrand(
      data
          .whereType<Map>()
          .map((item) => _normalizeStoreProductForProductModel(
        Map<String, dynamic>.from(item),
      ))
          .toList(),
    );

    final hasAnyRealPrice = productos.any((product) => _productPrice(product) > 0);
    if (data.isNotEmpty && productos.isNotEmpty && !hasAnyRealPrice) {
      if (kDebugMode) {
        debugPrint(
          '🔒 Store API autenticada no devuelve precios reales. '
              'No se permite catálogo comprable a 0 €.',
        );
      }

      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: 'Store API sin precios reales para este cliente.',
        message: 'La sesión WordPress no está aplicando precios reales de cliente.',
      );
    }

    _sortProductsByRequestedOrder(
      productos,
      _orderByFromProductQueryParams(queryParams),
    );

    final totalPages = _parseHeaderInt(
      response.headers,
      'x-wp-totalpages',
      productos.length < perPage ? page : page + 1,
    );

    final totalItems = _parseHeaderInt(
      response.headers,
      'x-wp-total',
      productos.length,
    );

    if (kDebugMode) {
      debugPrint(
        '🌐 Productos cargados por Store API autenticada: '
            'page=$page total=$totalItems items=${productos.length}',
      );
    }

    return CatalogProductsResult(
      products: productos,
      currentPage: page,
      totalPages: totalPages <= 0 ? 1 : totalPages,
      totalItems: totalItems,
    );
  }

  void _cacheCatalogProductsResult(
      String cacheKey,
      CatalogProductsResult result,
      ) {
    _requestProductsCache[cacheKey] = _RequestProductsCacheEntry(
      result: result,
      createdAt: DateTime.now(),
    );

    if (_requestProductsCache.length > _maxRequestProductsCacheEntries) {
      final entries = _requestProductsCache.entries.toList()
        ..sort((a, b) => a.value.createdAt.compareTo(b.value.createdAt));

      final removeCount =
          _requestProductsCache.length - _maxRequestProductsCacheEntries;

      for (final entry in entries.take(removeCount)) {
        _requestProductsCache.remove(entry.key);
      }
    }
  }

  Future<CatalogProductsResult> _requestCatalogProducts(
      Map<String, dynamic> queryParams, {
        required int page,
        required int perPage,
      }) async {
    final cacheKey = _requestProductsCacheKey(
      queryParams,
      page: page,
      perPage: perPage,
    );

    final cached = _requestProductsCache[cacheKey];
    if (cached != null && cached.isValid) {
      if (kDebugMode) {
        debugPrint('⚡ Request productos desde caché: $cacheKey');
      }
      return cached.result;
    }

    // Primero se intenta WooCommerce REST v3 para mantener intacto el flujo
    // de admin/comercial y no perder campos internos como stock-gen/stock-tie.
    // Si el cliente normal recibe 401/403, se usa Store API autenticada con
    // cookies + nonce de la sesión WordPress creada en firebase-login.
    try {
      final response = await _dio.get(
        '/wp-json/wc/v3/products',
        queryParameters: queryParams,
        options: _wooOptions,
      );

      final List data = response.data is List ? response.data as List : [];
      final productos = await _mapProductsWithBrand(data);
      _sortProductsByRequestedOrder(
        productos,
        _orderByFromProductQueryParams(queryParams),
      );

      final totalPages = _parseHeaderInt(
        response.headers,
        'x-wp-totalpages',
        productos.length < perPage ? page : page + 1,
      );

      final totalItems = _parseHeaderInt(
        response.headers,
        'x-wp-total',
        productos.length,
      );

      final result = CatalogProductsResult(
        products: productos,
        currentPage: page,
        totalPages: totalPages <= 0 ? 1 : totalPages,
        totalItems: totalItems,
      );

      _cacheCatalogProductsResult(cacheKey, result);

      if (kDebugMode) {
        debugPrint('🌐 Request productos API privada: $cacheKey');
      }

      return result;
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;

      if (statusCode == 401 || statusCode == 403) {
        await _loadWordPressSession();

        if (_hasWordPressSession) {
          try {
            if (kDebugMode) {
              debugPrint(
                '🔐 WC v3 bloqueado (status=$statusCode). '
                    'Probando Store API autenticada con sesión WordPress/WooCommerce.',
              );
            }

            final result = await _requestStoreApiProductsFallback(
              queryParams,
              page: page,
              perPage: perPage,
            );

            _cacheCatalogProductsResult(cacheKey, result);
            return result;
          } catch (fallbackError) {
            if (kDebugMode) {
              debugPrint(
                '🔒 Store API autenticada no pudo devolver catálogo con precio real: '
                    '$fallbackError',
              );
            }

            throw DioException(
              requestOptions: e.requestOptions,
              response: e.response,
              type: e.type,
              error: fallbackError,
              message:
              'La Store API autenticada no ha devuelto productos con precio real.',
            );
          }
        }

        if (kDebugMode) {
          debugPrint(
            '🔒 Productos WC v3 bloqueados (status=$statusCode). '
                'No se usa Store API pública como invitado para evitar precios 0.',
          );
        }

        throw DioException(
          requestOptions: e.requestOptions,
          response: e.response,
          type: e.type,
          error: 'No se pueden cargar productos con precio real desde WooCommerce.',
          message:
          'Falta sesión WordPress/WooCommerce válida. Haz login limpio para guardar cookies y nonce.',
        );
      }

      rethrow;
    }
  }

  bool _catalogResultMatchesBrand(
      CatalogProductsResult result,
      String? brandName,
      ) {
    final cleanBrand = brandName?.trim();

    if (cleanBrand == null || cleanBrand.isEmpty) {
      return result.totalItems > 0 || result.products.isNotEmpty;
    }

    if (result.products.isEmpty) {
      return false;
    }

    // Solo damos por válido el filtro remoto si todos los productos de la página
    // pertenecen realmente a la marca seleccionada. Si WooCommerce ignora el
    // parámetro brand/attribute y mezcla productos, se fuerza fallback local.
    return result.products.every(
          (product) => _productMatchesBrand(product, cleanBrand),
    );
  }

  String? _extractBrandFromProduct(Product product) {
    for (final attr in product.attributes) {
      if (!_isBrandAttributeName(attr.name)) continue;

      for (final option in attr.options) {
        final clean = _cleanBrandCandidate(option);
        if (clean != null && clean.isNotEmpty) {
          return clean;
        }
      }
    }

    return null;
  }

  String _contextProductsCacheKey({
    int? categoryId,
    String? search,
    String? orderBy,
  }) {
    return [
      'cat:${categoryId ?? 0}',
      'search:${(search ?? '').trim().toLowerCase()}',
      'order:${(orderBy ?? '').trim()}',
    ].join('|');
  }

  Future<List<Product>> _getProductsForFilterContext({
    int? categoryId,
    String? search,
    String? orderBy,
  }) async {
    final cacheKey = _contextProductsCacheKey(
      categoryId: categoryId,
      search: search,
      orderBy: orderBy,
    );

    final cached = _contextProductsCache[cacheKey];
    if (cached != null && cached.isValid) {
      if (kDebugMode) {
        debugPrint('⚡ Productos contexto desde caché: $cacheKey');
      }
      return cached.products;
    }

    final baseQueryParams = <String, dynamic>{
      'per_page': 100,
      'page': 1,
      'status': 'publish',
    };

    if (categoryId != null && categoryId > 0) {
      baseQueryParams['category'] = categoryId.toString();
    }

    final cleanSearch = search?.trim();
    final effectiveSearch = _effectiveCatalogSearchTerm(cleanSearch);
    if (effectiveSearch != null && effectiveSearch.isNotEmpty) {
      baseQueryParams['search'] = effectiveSearch;
    }

    _applyProductOrderParams(baseQueryParams, orderBy);

    final products = <Product>[];
    int page = 1;
    int totalPages = 1;

    do {
      final queryParams = Map<String, dynamic>.from(baseQueryParams)
        ..['page'] = page;

      final result = await _requestCatalogProducts(
        queryParams,
        page: page,
        perPage: 100,
      );

      products.addAll(result.products);
      totalPages = result.totalPages;
      page++;
    } while (page <= totalPages);

    _sortProductsByRequestedOrder(products, orderBy);

    _contextProductsCache[cacheKey] = _ContextProductsCacheEntry(
      products: products,
      createdAt: DateTime.now(),
    );

    if (_contextProductsCache.length > 30) {
      final entries = _contextProductsCache.entries.toList()
        ..sort((a, b) => a.value.createdAt.compareTo(b.value.createdAt));

      for (final entry in entries.take(_contextProductsCache.length - 30)) {
        _contextProductsCache.remove(entry.key);
      }
    }

    if (kDebugMode) {
      debugPrint(
        '📦 Productos contexto cargados: category=$categoryId '
            'search="$cleanSearch" total=${products.length}',
      );
    }

    return products;
  }

  CatalogProductsResult _paginateLocalProducts({
    required List<Product> products,
    required int page,
    required int perPage,
  }) {
    final safePage = page <= 0 ? 1 : page;
    final safePerPage = perPage <= 0 ? 30 : perPage;
    final totalItems = products.length;
    final totalPages = totalItems == 0 ? 1 : ((totalItems + safePerPage - 1) ~/ safePerPage);
    final start = (safePage - 1) * safePerPage;

    if (start >= totalItems) {
      return CatalogProductsResult(
        products: const [],
        currentPage: safePage,
        totalPages: totalPages,
        totalItems: totalItems,
      );
    }

    final end = (start + safePerPage) > totalItems ? totalItems : start + safePerPage;

    return CatalogProductsResult(
      products: products.sublist(start, end),
      currentPage: safePage,
      totalPages: totalPages,
      totalItems: totalItems,
    );
  }



  CatalogFilterDefinition? _catalogFilterDefinitionForTaxonomy(String taxonomy) {
    final cleanTaxonomy = taxonomy.trim();
    if (cleanTaxonomy.isEmpty) return null;

    for (final definition in _catalogFilterDefinitions) {
      if (definition.taxonomy == cleanTaxonomy) {
        return definition;
      }
    }

    return null;
  }

  Future<Map<String, String>> _resolveAttributeTermLabels({
    required Map<String, int> attributeTermIds,
    Map<String, String>? attributeLabels,
  }) async {
    final result = <String, String>{};

    for (final entry in attributeTermIds.entries) {
      final taxonomy = entry.key.trim();
      final termId = entry.value;
      if (taxonomy.isEmpty || termId <= 0) continue;

      final explicitLabel = attributeLabels?[taxonomy]?.trim();
      if (explicitLabel != null && explicitLabel.isNotEmpty) {
        result[taxonomy] = explicitLabel;
        continue;
      }

      final localLabel = _localFilterTermLabelsByTaxonomy[taxonomy]?[termId]?.trim();
      if (localLabel != null && localLabel.isNotEmpty) {
        result[taxonomy] = localLabel;
        continue;
      }

      final definition = _catalogFilterDefinitionForTaxonomy(taxonomy);
      if (definition == null) continue;

      try {
        final terms = await _getAttributeTerms(definition).timeout(
          const Duration(seconds: 3),
        );

        for (final term in terms) {
          final id = _parseIntValue(term['id']);
          if (id != termId) continue;

          final name = term['name']?.toString().trim() ?? '';
          if (name.isNotEmpty) {
            result[taxonomy] = name;
          }
          break;
        }
      } catch (_) {
        // Si no podemos resolver la etiqueta, ese atributo no se filtra localmente.
      }
    }

    return result;
  }

  bool _productMatchesCatalogAttributeLabel({
    required Product product,
    required String taxonomy,
    required String label,
  }) {
    final cleanLabel = label.trim();
    if (cleanLabel.isEmpty) return true;

    if (taxonomy == 'pa_marcas' || taxonomy == 'pa_marca') {
      return _productMatchesBrand(product, cleanLabel);
    }

    final definition = _catalogFilterDefinitionForTaxonomy(taxonomy);
    final normalizedTaxonomy = _normalizeBrandValue(
      taxonomy.replaceFirst('pa_', ''),
    );
    final normalizedTitle = _normalizeBrandValue(definition?.title ?? '');
    final normalizedKey = _normalizeBrandValue(definition?.key ?? '');
    final normalizedLabel = _normalizeBrandValue(cleanLabel);

    if (normalizedLabel.isEmpty) return true;

    for (final attr in product.attributes) {
      final attrName = _normalizeBrandValue(attr.name);
      final looksLikeAttribute = attrName == normalizedTaxonomy ||
          attrName == normalizedTitle ||
          attrName == normalizedKey ||
          attrName.contains(normalizedTaxonomy) ||
          (normalizedTitle.isNotEmpty && attrName.contains(normalizedTitle)) ||
          (normalizedKey.isNotEmpty && attrName.contains(normalizedKey));

      if (!looksLikeAttribute) continue;

      for (final option in attr.options) {
        final normalizedOption = _normalizeBrandValue(option);
        if (normalizedOption == normalizedLabel) {
          return true;
        }
      }
    }

    return false;
  }

  Future<CatalogProductsResult> _getAttributeFilteredCatalogResult({
    int? categoryId,
    String? brandName,
    String? search,
    String? orderBy,
    required int page,
    required int perPage,
    required Map<String, int> attributeTermIds,
    Map<String, String>? attributeLabels,
  }) async {
    final contextProducts = await _getProductsForFilterContext(
      categoryId: categoryId,
      search: search,
      orderBy: orderBy,
    );

    final resolvedLabels = await _resolveAttributeTermLabels(
      attributeTermIds: attributeTermIds,
      attributeLabels: attributeLabels,
    );

    var filtered = contextProducts;

    final cleanBrandName = brandName?.trim();
    if (cleanBrandName != null && cleanBrandName.isNotEmpty) {
      filtered = filtered
          .where((product) => _productMatchesBrand(product, cleanBrandName))
          .toList();
    }

    for (final entry in resolvedLabels.entries) {
      filtered = filtered
          .where(
            (product) => _productMatchesCatalogAttributeLabel(
          product: product,
          taxonomy: entry.key,
          label: entry.value,
        ),
      )
          .toList();
    }

    _sortProductsByRequestedOrder(filtered, orderBy);

    if (kDebugMode) {
      debugPrint(
        '🧩 Filtro local por atributos: category=$categoryId '
            'brand="$cleanBrandName" attrs=$resolvedLabels '
            '${contextProducts.length} contexto → ${filtered.length} válidos',
      );
    }

    return _paginateLocalProducts(
      products: filtered,
      page: page,
      perPage: perPage,
    );
  }

  Future<CatalogProductsResult> _getLocalBrandFilteredCatalogResult({
    int? categoryId,
    required String brandName,
    String? search,
    String? orderBy,
    required int page,
    required int perPage,
  }) async {
    final contextProducts = await _getProductsForFilterContext(
      categoryId: categoryId,
      search: search,
      orderBy: orderBy,
    );

    final filtered = contextProducts
        .where((product) => _productMatchesBrand(product, brandName))
        .toList();

    _sortProductsByRequestedOrder(filtered, orderBy);

    if (kDebugMode) {
      debugPrint(
        '🧹 Filtro local por marca "$brandName": '
            '${contextProducts.length} contexto → ${filtered.length} válidos',
      );
    }

    return _paginateLocalProducts(
      products: filtered,
      page: page,
      perPage: perPage,
    );
  }

  CatalogProductsResult _filterCatalogResultByBrand(
      CatalogProductsResult result,
      String? brandName, {
        String? orderBy,
      }) {
    final cleanBrand = brandName?.trim();

    if (cleanBrand == null || cleanBrand.isEmpty) {
      return result;
    }

    final filteredProducts = result.products
        .where((product) => _productMatchesBrand(product, cleanBrand))
        .toList();

    _sortProductsByRequestedOrder(filteredProducts, orderBy);

    if (filteredProducts.length == result.products.length) {
      return _sortCatalogResultPage(result, orderBy);
    }

    if (kDebugMode) {
      debugPrint(
        '🧹 Validación final de marca "$cleanBrand": '
            '${result.products.length} recibidos → ${filteredProducts.length} válidos',
      );
    }

    return CatalogProductsResult(
      products: filteredProducts,
      currentPage: result.currentPage,
      totalPages: filteredProducts.isEmpty ? 1 : result.totalPages,
      totalItems: filteredProducts.length,
    );
  }


  // ================================================================
  // CLIENTES
  // ================================================================

  Future<Map<String, dynamic>?> getCustomerByEmail(String email) async {
    try {
      final response = await _appGet('/me');
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      final user = data['user'] is Map
          ? Map<String, dynamic>.from(data['user'] as Map)
          : <String, dynamic>{};

      final requestedEmail = email.trim().toLowerCase();
      final currentEmail = user['email']?.toString().trim().toLowerCase() ?? '';

      if (requestedEmail.isEmpty || requestedEmail == currentEmail) {
        return user;
      }

      final responseWoo = await _dio.get(
        '/wp-json/wc/v3/customers',
        queryParameters: {'email': email, 'role': 'all'},
        options: _wooOptions,
      );

      if (responseWoo.statusCode == 200 &&
          responseWoo.data is List &&
          (responseWoo.data as List).isNotEmpty) {
        final firstCustomer = (responseWoo.data as List).first;

        if (firstCustomer is Map) {
          return Map<String, dynamic>.from(firstCustomer);
        }
      }

      return null;
    } catch (e) {
      debugPrint('Error en getCustomerByEmail App API: $e');
      return null;
    }
  }


  Future<Map<String, dynamic>?> getCustomerById(int id) async {
    if (id <= 0) return null;

    try {
      final response = await _appGet('/me');
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      final user = data['user'] is Map
          ? Map<String, dynamic>.from(data['user'] as Map)
          : <String, dynamic>{};

      final currentId = _parseIntValue(
        user['id'] ?? user['wordpress_id'] ?? user['woocommerce_id'],
      );

      if (currentId == id) {
        return user;
      }

      final responseWoo = await _dio.get(
        '/wp-json/wc/v3/customers/$id',
        options: _wooOptions,
      );

      if (responseWoo.statusCode == 200 && responseWoo.data is Map) {
        return Map<String, dynamic>.from(responseWoo.data as Map);
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error en getCustomerById App API: $e');
      }
      return null;
    }
  }


  // ================================================================
  // PERMISOS USUARIO / STOCK INTERNO
  // ================================================================

  String _normalizeCustomerRoleValue(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('ä', 'a')
        .replaceAll('â', 'a')
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ì', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('î', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ò', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ù', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('û', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  bool _roleCanViewStockDetails(dynamic value) {
    if (value == null) return false;

    if (value is Iterable) {
      return value.any(_roleCanViewStockDetails);
    }

    if (value is Map) {
      return value.entries.any(
            (entry) =>
        _roleCanViewStockDetails(entry.key) ||
            _roleCanViewStockDetails(entry.value),
      );
    }

    final normalized = _normalizeCustomerRoleValue(value.toString());

    return normalized == 'admin' ||
        normalized == 'administrator' ||
        normalized == 'administrador' ||
        normalized == 'shopmanager' ||
        normalized == 'gestordelatienda' ||
        normalized.startsWith('comercial');
  }

  dynamic _extractCustomerRoleValue(Map<String, dynamic>? customerData) {
    if (customerData == null || customerData.isEmpty) return null;

    final directRole = customerData['role'] ??
        customerData['roles'] ??
        customerData['rol'] ??
        customerData['user_role'] ??
        customerData['userRole'];

    if (directRole != null) return directRole;

    final metaData = customerData['meta_data'];
    if (metaData is List) {
      for (final rawMeta in metaData) {
        if (rawMeta is! Map) continue;

        final meta = Map<dynamic, dynamic>.from(rawMeta);
        final key = _normalizeCustomerRoleValue(meta['key']?.toString() ?? '');

        if (key == 'role' ||
            key == 'roles' ||
            key == 'rol' ||
            key == 'userrole' ||
            key == 'wpuserrole' ||
            key == 'capabilities' ||
            key == 'wpcapabilities') {
          return meta['value'];
        }
      }
    }

    return null;
  }

  String? _roleTextFromDynamic(dynamic value) {
    if (value == null) return null;

    if (value is Iterable) {
      for (final item in value) {
        final role = _roleTextFromDynamic(item);
        if (role != null && role.trim().isNotEmpty) return role;
      }
      return null;
    }

    if (value is Map) {
      for (final item in value.values) {
        final role = _roleTextFromDynamic(item);
        if (role != null && role.trim().isNotEmpty) return role;
      }
      return null;
    }

    final role = value.toString().trim();
    return role.isEmpty ? null : role;
  }

  Future<String?> getCustomerRoleById(int wordpressId) async {
    if (wordpressId <= 0) return null;

    final customer = await getCustomerById(wordpressId).timeout(
      const Duration(seconds: 3),
      onTimeout: () => null,
    );
    final roleValue = _extractCustomerRoleValue(customer);

    return _roleTextFromDynamic(roleValue);
  }

  Future<bool> canCustomerViewStockDetails(int wordpressId) async {
    try {
      final response = await _appGet('/me');
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};

      final permissions = data['permissions'] is Map
          ? Map<String, dynamic>.from(data['permissions'] as Map)
          : <String, dynamic>{};

      final canView = permissions['can_view_stock_details'] == true ||
          permissions['can_view_stock'] == true ||
          data['can_view_stock'] == true;

      if (kDebugMode) {
        final user = data['user'] is Map ? data['user'] as Map : const {};
        debugPrint(
          '👤 Permiso stock App API usuario WP ${user['id'] ?? wordpressId} | '
              'role=${user['role'] ?? user['roles'] ?? '-'} | canView=$canView',
        );
      }

      return canView;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error comprobando permiso de stock App API: $e');
      }
      return false;
    }
  }


  Future<bool> canUserViewStockDetails(int wordpressId) {
    return canCustomerViewStockDetails(wordpressId);
  }

  Future<bool> canWordPressUserViewStockDetails(int wordpressId) {
    return canCustomerViewStockDetails(wordpressId);
  }

  // ================================================================
  // PRODUCTOS / CATÁLOGO
  // ================================================================

  Future<CatalogProductsResult> _getAppLocalAttributeFilteredCatalogResult({
    int? categoryId,
    int? brandId,
    String? brandName,
    String? search,
    int page = 1,
    int perPage = 30,
    String? orderBy,
    required Map<String, int> attributeTermIds,
    Map<String, String>? attributeLabels,
  }) async {
    final safePage = page <= 0 ? 1 : page;
    final safePerPage = perPage <= 0 ? 30 : perPage;

    final resolvedLabels = await _resolveAttributeTermLabels(
      attributeTermIds: attributeTermIds,
      attributeLabels: attributeLabels,
    );

    if (resolvedLabels.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '⚠️ Filtro por atributos sin etiquetas resueltas. '
              'Se devuelve catálogo sin aplicar atributos.',
        );
      }
    }

    final allProducts = <Product>[];
    var fetchPage = 1;
    var totalPages = 1;

    do {
      final query = <String, dynamic>{
        'page': fetchPage,
        'per_page': 100,
      };

      if (categoryId != null && categoryId > 0) {
        query['category'] = categoryId;
      }

      final cleanSearch = search?.trim();
      if (cleanSearch != null && cleanSearch.isNotEmpty) {
        query['search'] = cleanSearch;
      }

      if (brandId != null && brandId > 0) {
        query['brand_id'] = brandId;
      } else {
        final cleanBrand = brandName?.trim();
        if (cleanBrand != null && cleanBrand.isNotEmpty) {
          query['brand'] = cleanBrand;
        }
      }

      if (orderBy != null && orderBy.trim().isNotEmpty) {
        query['orderby'] = orderBy.trim();
      }

      final response = await _appGet('/products', queryParameters: query);
      final rawProducts = _extractAppList(
        response.data,
        const ['products', 'data', 'items'],
      );

      allProducts.addAll(
        rawProducts
            .whereType<Map>()
            .map((item) => Product.fromJson(Map<String, dynamic>.from(item))),
      );

      totalPages = _parseAppTotalPages(
        response.data,
        fallback: rawProducts.length < 100 ? fetchPage : fetchPage + 1,
      );
      fetchPage++;
    } while (fetchPage <= totalPages && fetchPage <= 30);

    var filtered = allProducts;

    for (final entry in resolvedLabels.entries) {
      filtered = filtered
          .where(
            (product) => _productMatchesCatalogAttributeLabel(
          product: product,
          taxonomy: entry.key,
          label: entry.value,
        ),
      )
          .toList();
    }

    _sortProductsByRequestedOrder(filtered, orderBy);

    if (kDebugMode) {
      debugPrint(
        '🧩 Productos filtrados localmente por atributos: '
            'category=$categoryId brandId=$brandId attrs=$resolvedLabels '
            '${allProducts.length} contexto → ${filtered.length} válidos',
      );
    }

    return _paginateLocalProducts(
      products: filtered,
      page: safePage,
      perPage: safePerPage,
    );
  }

  Future<CatalogProductsResult> getProductosCatalogoFiltrado({
    int? categoryId,
    int? brandId,
    String? brandName,
    String? search,
    int page = 1,
    int perPage = 30,
    String? orderBy,
    Map<String, int>? attributeTermIds,
    Map<String, String>? attributeLabels,
  }) async {
    try {
      final cleanAttributeTerms = Map<String, int>.from(
        attributeTermIds ?? const <String, int>{},
      )..removeWhere((key, value) => key.trim().isEmpty || value <= 0);

      final cleanAttributeLabels = Map<String, String>.from(
        attributeLabels ?? const <String, String>{},
      )..removeWhere((key, value) => key.trim().isEmpty || value.trim().isEmpty);

      // Cuando los filtros vienen del drawer, usamos la etiqueta guardada para
      // filtrar localmente sobre productos reales de la App API. Así funciona
      // tanto si el endpoint devuelve IDs reales como si los filtros se han
      // generado por fallback local desde productos en pantalla.
      if (cleanAttributeTerms.isNotEmpty && cleanAttributeLabels.isNotEmpty) {
        return _getAppLocalAttributeFilteredCatalogResult(
          categoryId: categoryId,
          brandId: brandId,
          brandName: brandName,
          search: search,
          page: page,
          perPage: perPage,
          orderBy: orderBy,
          attributeTermIds: cleanAttributeTerms,
          attributeLabels: cleanAttributeLabels,
        );
      }

      final query = <String, dynamic>{
        'page': page <= 0 ? 1 : page,
        'per_page': perPage <= 0 ? 30 : perPage,
      };

      if (categoryId != null && categoryId > 0) {
        query['category'] = categoryId;
      }

      final cleanSearch = search?.trim();
      if (cleanSearch != null && cleanSearch.isNotEmpty) {
        query['search'] = cleanSearch;
      }

      if (brandId != null && brandId > 0) {
        query['brand_id'] = brandId;
      } else {
        final cleanBrand = brandName?.trim();
        if (cleanBrand != null && cleanBrand.isNotEmpty) {
          query['brand'] = cleanBrand;
        }
      }

      if (orderBy != null && orderBy.trim().isNotEmpty) {
        query['orderby'] = orderBy.trim();
      }

      if (cleanAttributeTerms.isNotEmpty) {
        query['attribute_terms'] = jsonEncode(cleanAttributeTerms);
      }

      final response = await _appGet('/products', queryParameters: query);
      final rawProducts = _extractAppList(
        response.data,
        const ['products', 'data', 'items'],
      );

      final products = rawProducts
          .whereType<Map>()
          .map((item) => Product.fromJson(Map<String, dynamic>.from(item)))
          .toList();

      _sortProductsByRequestedOrder(products, orderBy);

      final totalItems = _parseAppTotalItems(
        response.data,
        fallback: products.length,
      );
      final totalPages = _parseAppTotalPages(
        response.data,
        fallback: products.length < perPage ? page : page + 1,
      );

      if (kDebugMode) {
        debugPrint(
          '✅ Productos App API: category=$categoryId brandId=$brandId '
              'brand="$brandName" search="$search" page=$page '
              'items=${products.length} total=$totalItems',
        );
      }

      return CatalogProductsResult(
        products: products,
        currentPage: page,
        totalPages: totalPages <= 0 ? 1 : totalPages,
        totalItems: totalItems,
      );
    } on DioException catch (e) {
      throw Exception(_mapDioError(e));
    } catch (e) {
      throw Exception('Error cargando productos desde MundiCam App API: $e');
    }
  }

  Future<List<Product>> getProductos({
    int? categoryId,
    int perPage = 100,
    String? brand,
    String? orderBy,
  }) async {
    await _ensureInitialized();
    try {
      final brandId = await getMarcaIdPorNombre(brand);
      final result = await getProductosCatalogoFiltrado(
        categoryId: categoryId,
        brandId: brandId,
        brandName: brand,
        page: 1,
        perPage: perPage,
        orderBy: orderBy,
      );

      List<Product> productos = result.products;

      // Compatibilidad con llamadas antiguas que pasan marca por texto.
      if (brand != null && brand.isNotEmpty && brandId == null) {
        productos = productos.where((p) => _productMatchesBrand(p, brand)).toList();
      }

      _sortProductsByRequestedOrder(productos, orderBy);

      if (kDebugMode) {
        debugPrint('📊 Productos finales mostrados: ${productos.length}');
      }
      return productos;
    } on DioException catch (e) {
      throw Exception(_mapDioError(e));
    } catch (e) {
      throw Exception('Error cargando productos: $e');
    }
  }

  Future<List<Product>> getProductosPaginado({
    int? categoryId,
    int page = 1,
    int perPage = 30,
    String? brand,
    int? brandId,
    String? search,
    String? orderBy,
  }) async {
    await _ensureInitialized();
    try {
      final effectiveBrandId = brandId ?? await getMarcaIdPorNombre(brand);
      final result = await getProductosCatalogoFiltrado(
        categoryId: categoryId,
        brandId: effectiveBrandId,
        brandName: brand,
        search: search,
        page: page,
        perPage: perPage,
        orderBy: orderBy,
      );

      List<Product> productos = result.products;

      if (brand != null && brand.isNotEmpty && effectiveBrandId == null) {
        productos = productos.where((p) => _productMatchesBrand(p, brand)).toList();
      }

      _sortProductsByRequestedOrder(productos, orderBy);

      return productos;
    } on DioException catch (e) {
      throw Exception(_mapDioError(e));
    } catch (e) {
      throw Exception('Error cargando productos paginados: $e');
    }
  }

  // ================================================================
  // PEDIDOS
  // ================================================================
  Future<List<OrderMundicam>> getOrders(String customerEmail) async {
    try {
      final response = await _appGet(
        '/orders',
        queryParameters: {
          'page': 1,
          'per_page': 50,
        },
      );

      final rawOrders = _extractAppList(
        response.data,
        const ['orders', 'data', 'items'],
      );

      final orders = rawOrders
          .whereType<Map>()
          .map((item) => OrderMundicam.fromJson(Map<String, dynamic>.from(item)))
          .toList();

      if (kDebugMode) {
        debugPrint('📦 Pedidos App API cargados: ${orders.length}');
      }

      return orders;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error obteniendo pedidos App API: $e');
      }
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
    try {
      final data = Map<String, dynamic>.from(orderData);
      final sanitizedLineItems = _sanitizeNewOrderLineItems(data['line_items']);

      if (sanitizedLineItems.isEmpty) {
        return OrderCreateResult.failure(
          'No hay productos válidos para crear el pedido.',
        );
      }

      data['line_items'] = sanitizedLineItems;

      if (forceProcessingIfPending &&
          (!data.containsKey('status') || data['status'] == 'pending')) {
        data['status'] = 'processing';
      }

      _debugLineItems('LINE ITEMS PEDIDO APP API', sanitizedLineItems);

      final response = await _appPost('/order/create', data: data);

      final responseData = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};

      if (responseData['success'] == false) {
        return OrderCreateResult.failure(
          responseData['message']?.toString() ?? 'No se pudo crear el pedido.',
        );
      }

      final orderDataResponse = responseData['order'] is Map
          ? Map<String, dynamic>.from(responseData['order'] as Map)
          : <String, dynamic>{};

      if (orderDataResponse.isEmpty) {
        orderDataResponse['id'] = responseData['order_id'];
        orderDataResponse['order_key'] = responseData['order_key'];
        orderDataResponse['number'] = responseData['order_number'] ?? responseData['order_id'];
        orderDataResponse['status'] = responseData['status'];
      }

      if (kDebugMode) {
        debugPrint('✅ Pedido App API creado: ${orderDataResponse['id']}');
      }

      return OrderCreateResult.success(orderDataResponse);
    } on DioException catch (e) {
      final responseData = e.response?.data;

      if (responseData is Map && responseData['message'] != null) {
        return OrderCreateResult.failure(responseData['message'].toString());
      }

      return OrderCreateResult.failure(_mapDioError(e));
    } catch (e) {
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
  Future<Map<String, dynamic>?> _buscarPresupuestoAbiertoPorEmail(
      String email,
      ) async {
    await _ensureInitialized();

    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty) return null;

    try {
      final response = await _dio.get(
        '/wp-json/wc/v3/orders',
        queryParameters: {
          'search': cleanEmail,
          'status': 'checkout-draft',
          'per_page': 20,
          'orderby': 'date',
          'order': 'desc',
        },
        options: _wooOptions,
      );

      final data = response.data;

      if (response.statusCode != 200 || data is! List || data.isEmpty) {
        return null;
      }

      for (final rawOrder in data) {
        if (rawOrder is! Map) continue;

        final order = Map<String, dynamic>.from(rawOrder);

        final status = order['status']?.toString() ?? '';
        final billing = order['billing'];
        final billingEmail = billing is Map
            ? billing['email']?.toString().trim().toLowerCase()
            : null;

        if (status == 'checkout-draft' &&
            (billingEmail == null ||
                billingEmail.isEmpty ||
                billingEmail == cleanEmail)) {
          return order;
        }
      }

      return null;
    } catch (e) {
      debugPrint('⚠️ No se pudo buscar presupuesto abierto: $e');
      return null;
    }
  }
  Future<bool> crearPresupuesto({
    required String email,
    required int productId,
    required String productName,
    required double price,
    required int quantity,
    String? customerNote,
  }) async {
    try {
      if (productId <= 0) return false;

      final response = await _appPost(
        '/quote/add',
        data: {
          'product_id': productId,
          'quantity': quantity <= 0 ? 1 : quantity,
          if (customerNote != null && customerNote.trim().isNotEmpty)
            'customer_note': customerNote.trim(),
        },
      );

      final data = response.data;
      if (data is Map) {
        return data['success'] == true || data['ok'] == true;
      }

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error creando presupuesto App API: $e');
      }
      return false;
    }
  }

  Future<bool> actualizarPresupuesto({
    required String orderId,
    required int productId,
    required int quantity,
  }) async {
    await _ensureInitialized();

    try {
      final cleanOrderId = orderId.replaceAll(RegExp(r'[^0-9]'), '');
      final safeQuantity = quantity <= 0 ? 1 : quantity;

      if (cleanOrderId.isEmpty || productId <= 0) {
        return false;
      }

      final orden = await getOrdenCompleta(cleanOrderId);

      if (orden == null) return false;

      final lineItems = _buildMinimalWooLineItemsForUpdate(
        orden['line_items'],
      );

      final index = lineItems.indexWhere(
            (item) => _parseIntValue(item['product_id']) == productId,
      );

      if (index >= 0) {
        final currentQty = _parseIntValue(lineItems[index]['quantity']);
        lineItems[index]['quantity'] = currentQty + safeQuantity;
      } else {
        lineItems.add({
          'product_id': productId,
          'quantity': safeQuantity,
        });
      }

      _debugLineItems('LINE ITEMS PRESUPUESTO ACTUALIZADO', lineItems);

      final response = await _dio.put(
        '/wp-json/wc/v3/orders/$cleanOrderId',
        data: {
          'line_items': lineItems,
        },
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
      final cleanOrderId = orderId.replaceAll(RegExp(r'[^0-9]'), '');

      if (cleanOrderId.isEmpty || productId <= 0) {
        return false;
      }

      final orden = await getOrdenCompleta(cleanOrderId);

      if (orden == null) return false;

      final filteredLineItems = _buildMinimalWooLineItemsForUpdate(
        orden['line_items'],
      ).where((item) => _parseIntValue(item['product_id']) != productId).toList();

      _debugLineItems('LINE ITEMS PRESUPUESTO TRAS ELIMINAR', filteredLineItems);

      final response = await _dio.put(
        '/wp-json/wc/v3/orders/$cleanOrderId',
        data: {
          'line_items': filteredLineItems,
        },
        options: _wooOptions,
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error eliminando producto de presupuesto: $e');
      return false;
    }
  }


  // ================================================================
  // BÚSQUEDA DE PRODUCTOS
  // ================================================================

  Future<List<Product>> buscarProductos(String query) async {
    await _ensureInitialized();
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      return [];
    }

    try {
      final result = await getProductosCatalogoFiltrado(
        search: cleanQuery,
        page: 1,
        perPage: 50,
        orderBy: 'date',
      );

      final lista = [...result.products];
      lista.sort((a, b) {
        if (a.isInstock && !b.isInstock) return -1;
        if (!a.isInstock && b.isInstock) return 1;
        return 0;
      });

      return lista;
    } catch (e) {
      debugPrint('Error en buscarProductos: $e');
      return [];
    }
  }

  // ================================================================
  // CATEGORÍAS
  // ================================================================


  CategoryModel _categoryFromJsonSafe(Map<String, dynamic> raw) {
    final json = Map<String, dynamic>.from(raw);

    json['id'] = _parseIntValue(json['id'] ?? json['term_id'] ?? json['category_id']);
    json['parent'] = _parseIntValue(json['parent'] ?? json['parent_id']);
    json['count'] = _parseIntValue(json['count'] ?? json['product_count'] ?? json['total']);
    json['menu_order'] = _parseIntValue(json['menu_order'] ?? json['menuOrder']);
    json['name'] = json['name']?.toString() ?? 'Sin nombre';
    json['slug'] = json['slug']?.toString() ?? '';

    final image = json['image'];
    if (image is String) {
      json['image'] = <String, dynamic>{'src': image, 'url': image};
      json['image_url'] = image;
    } else if (image is Map) {
      final map = Map<String, dynamic>.from(image);
      final src = map['src']?.toString() ??
          map['url']?.toString() ??
          map['source_url']?.toString() ??
          '';
      json['image'] = <String, dynamic>{...map, 'src': src};
      json['image_url'] = src;
    } else {
      final imageUrl = json['image_url']?.toString() ?? '';
      json['image'] = <String, dynamic>{'src': imageUrl, 'url': imageUrl};
      json['image_url'] = imageUrl;
    }

    return CategoryModel.fromJson(json);
  }

  List<CategoryModel> _postProcessCategories(
      List<CategoryModel> categorias, {
        required bool soloConProductos,
        required bool soloCategoriasPadre,
      }) {
    var resultado = categorias;

    if (soloConProductos) {
      resultado = _filtrarCategoriasVisibles(resultado);
    }

    if (soloCategoriasPadre) {
      resultado = resultado.where((c) => c.parent == 0).toList();
    }

    return resultado;
  }

  Future<List<CategoryModel>> _getCategoriasDesdeStoreApi({
    bool soloConProductos = true,
    bool soloCategoriasPadre = true,
  }) async {
    int page = 1;
    int totalPages = 1;
    final todas = <CategoryModel>[];

    do {
      final response = await _dio.get(
        '/wp-json/wc/store/v1/products/categories',
        queryParameters: {
          'per_page': 100,
          'page': page,
          'orderby': 'name',
          'order': 'asc',
        },
        options: _storeApiOptions,
      );

      final data = response.data is List ? response.data as List : <dynamic>[];
      todas.addAll(
        data.whereType<Map>().map(
              (item) => _categoryFromJsonSafe(
            Map<String, dynamic>.from(item),
          ),
        ),
      );

      totalPages = _parseHeaderInt(response.headers, 'x-wp-totalpages', 1);
      page++;
    } while (page <= totalPages);

    if (kDebugMode) {
      debugPrint('🌐 Categorías cargadas por Store API pública: ${todas.length}');
    }

    return _postProcessCategories(
      todas,
      soloConProductos: soloConProductos,
      soloCategoriasPadre: soloCategoriasPadre,
    );
  }

  Future<List<CategoryModel>> getCategorias({
    bool soloConProductos = true,
    bool soloCategoriasPadre = true,
  }) async {
    await _ensureInitialized();

    // Las categorías no deben depender de que el usuario ya tenga token App API.
    // En el arranque la app puede pedirlas antes de que el login haya guardado
    // la sesión. Por eso la fuente principal es Store API pública/caché.
    try {
      final categorias = await _getCategoriasDesdeStoreApi(
        soloConProductos: soloConProductos,
        soloCategoriasPadre: soloCategoriasPadre,
      ).timeout(const Duration(seconds: 8));

      if (categorias.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('✅ Categorías Store API cargadas: ${categorias.length}');
        }
        return categorias;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Categorías Store API no disponibles, probando App API: $e');
      }
    }

    // Fallback App API cuando ya existe sesión. Nunca debe romper la Home si
    // todavía no hay token; simplemente devolverá lista vacía y el provider podrá
    // seguir usando caché local si la tiene.
    try {
      if (_hasAppToken || _wpCartToken.trim().isNotEmpty) {
        final response = await _appGet(
          '/categories',
          queryParameters: {
            'hide_empty': soloConProductos ? 1 : 0,
            'parent_only': soloCategoriasPadre ? 1 : 0,
          },
        ).timeout(const Duration(seconds: 8));

        final rawCategories = _extractAppList(
          response.data,
          const ['categories', 'data', 'items'],
        );

        final categories = rawCategories
            .whereType<Map>()
            .map((item) => _categoryFromJsonSafe(Map<String, dynamic>.from(item)))
            .toList();

        final processed = _postProcessCategories(
          categories,
          soloConProductos: soloConProductos,
          soloCategoriasPadre: soloCategoriasPadre,
        );

        if (kDebugMode) {
          debugPrint('✅ Categorías App API cargadas: ${processed.length}');
        }

        return processed;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Categorías App API no disponibles: $e');
      }
    }

    if (kDebugMode) {
      debugPrint('⚠️ No se pudieron cargar categorías desde ninguna fuente.');
    }
    return <CategoryModel>[];
  }

  Future<List<CategoryModel>> getSubcategoriasDe(int? parentId) async {
    if (parentId == null || parentId <= 0) return [];

    await _ensureInitialized();

    // Primero Store API: público, estable y no depende de sesión App API.
    try {
      final response = await _dio.get(
        '/wp-json/wc/store/v1/products/categories',
        queryParameters: {
          'per_page': 100,
          'page': 1,
          'parent': parentId,
          'orderby': 'name',
          'order': 'asc',
        },
        options: _storeApiOptions,
      ).timeout(const Duration(seconds: 6));

      final data = response.data is List ? response.data as List : <dynamic>[];
      final categories = data
          .whereType<Map>()
          .map((item) => _categoryFromJsonSafe(Map<String, dynamic>.from(item)))
          .where((category) => category.parent == parentId)
          .toList();

      if (categories.isNotEmpty) {
        return categories;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Subcategorías Store API no disponibles: $e');
      }
    }

    // Fallback App API si hay sesión.
    try {
      if (_hasAppToken || _wpCartToken.trim().isNotEmpty) {
        final response = await _appGet(
          '/categories',
          queryParameters: {
            'parent': parentId,
            'hide_empty': 0,
            'parent_only': 0,
          },
        ).timeout(const Duration(seconds: 6));

        final rawCategories = _extractAppList(
          response.data,
          const ['categories', 'data', 'items'],
        );

        return rawCategories
            .whereType<Map>()
            .map((item) => _categoryFromJsonSafe(Map<String, dynamic>.from(item)))
            .where((category) => category.parent == parentId)
            .toList();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Error cargando subcategorías App API: $e');
      }
    }

    return [];
  }


  Future<List<CategoryModel>> getSubcategoriasDisponiblesCatalogo({
    required int parentCategoryId,
    int? brandId,
    String? search,
  }) async {
    final subcategorias = await getSubcategoriasDe(parentCategoryId);
    if (subcategorias.isEmpty) {
      return [];
    }

    final disponibles = <CategoryModel>[];

    for (final subcategoria in subcategorias) {
      try {
        final result = await getProductosCatalogoFiltrado(
          categoryId: subcategoria.id,
          brandId: brandId,
          search: search,
          page: 1,
          perPage: 1,
        );
        if (result.totalItems > 0 || result.products.isNotEmpty) {
          disponibles.add(subcategoria);
        }
      } catch (_) {
        // Si una subcategoría falla, no bloqueamos todo el filtro.
      }
    }

    return disponibles;
  }

  // ================================================================
  // MARCAS
  // ================================================================

  Future<List<Map<String, dynamic>>> getMarcas({
    bool hideEmpty = true,
    bool forceRefresh = false,
  }) async {
    await _ensureInitialized();

    if (!forceRefresh &&
        _cachedBrandTerms != null &&
        _cachedBrandTerms!.isNotEmpty &&
        hideEmpty) {
      return _cachedBrandTerms!;
    }

    try {
      final marcas = <Map<String, dynamic>>[];

      void addUnique(List<Map<String, dynamic>> sourceTerms) {
        for (final term in sourceTerms) {
          final id = _termIdFromDynamic(term['id']);
          final name = term['name']?.toString().trim() ?? '';
          if (id == null || id <= 0 || name.isEmpty) continue;

          final slug = term['slug']?.toString().trim() ?? '';
          final exists = marcas.any((item) {
            final itemName = item['name']?.toString().trim() ?? '';
            final itemSlug = item['slug']?.toString().trim() ?? '';
            final itemId = _termIdFromDynamic(item['id']);
            return itemId == id ||
                _normalizeBrandValue(itemName) == _normalizeBrandValue(name) ||
                (slug.isNotEmpty &&
                    itemSlug.isNotEmpty &&
                    _normalizeBrandValue(itemSlug) == _normalizeBrandValue(slug));
          });

          if (!exists) marcas.add(term);
        }
      }

      // Primero fabricantes reales de la web actual.
      addUnique(await _getBrandTermsFromAttributeTerms(hideEmpty: hideEmpty));

      // Después compatibilidad con plugins de marca.
      addUnique(await _getBrandTermsFromStoreApi(hideEmpty: hideEmpty));
      addUnique(await _getBrandTermsFromWooBrandsApi(hideEmpty: hideEmpty));

      // Por último, compatibilidad con la versión anterior pa_marca.
      addUnique(await _getBrandTermsFromLegacyMarcaAttributeTerms(hideEmpty: hideEmpty));

      marcas.sort(
            (a, b) => (a['name']?.toString().toLowerCase() ?? '').compareTo(
          b['name']?.toString().toLowerCase() ?? '',
        ),
      );

      if (hideEmpty && marcas.isNotEmpty) {
        _cachedBrandTerms = marcas;
      }

      _cachedBrandNames = marcas
          .map((brand) => brand['name']?.toString().trim() ?? '')
          .where((brand) => brand.isNotEmpty)
          .toList();

      if (kDebugMode) {
        final sources = marcas
            .map((brand) => brand['source']?.toString() ?? '')
            .where((source) => source.isNotEmpty)
            .toSet()
            .join(', ');
        debugPrint('🏷️ Marcas/fabricantes finales: ${marcas.length} · fuentes=$sources');
      }

      return marcas;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Error cargando marcas: $e');
      }
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getMarcasDisponiblesCatalogo({
    int? categoryId,
    String? search,
  }) async {
    final cacheKey =
        'marcas_cat:${categoryId ?? 0}|search:${search?.trim().toLowerCase() ?? ''}';

    final cached = _marcasDisponiblesCache[cacheKey];
    if (cached != null && cached.isValid) {
      if (kDebugMode) {
        debugPrint('⚡ Marcas disponibles desde caché: $cacheKey');
      }
      return cached.marcas;
    }

    if (categoryId != null && categoryId > 0) {
      final categoryBrands = await getBrandsForCategory(
        categoryId,
        search: search,
      );

      if (categoryBrands.isNotEmpty) {
        _marcasDisponiblesCache[cacheKey] = _MarcasDisponiblesCache(
          marcas: categoryBrands,
          timestamp: DateTime.now(),
        );
        return categoryBrands;
      }
    }

    final marcas = await getMarcas(hideEmpty: true);

    if (marcas.isEmpty) {
      return [];
    }

    try {
      final products = await _getProductsForFilterContext(
        categoryId: categoryId,
        search: search,
        orderBy: '',
      ).timeout(const Duration(seconds: 8));

      if (products.isEmpty) {
        return [];
      }

      final brandByNormalizedName = <String, Map<String, dynamic>>{};

      for (final marca in marcas) {
        final id = _termIdFromDynamic(marca['id']);
        final name = marca['name']?.toString().trim() ?? '';
        final slug = marca['slug']?.toString().trim() ?? '';

        if (id == null || id <= 0 || name.isEmpty) {
          continue;
        }

        brandByNormalizedName[_normalizeBrandValue(name)] = marca;

        if (slug.isNotEmpty) {
          brandByNormalizedName[_normalizeBrandValue(slug)] = marca;
        }
      }

      final countsByBrandId = <int, int>{};

      for (final product in products) {
        final productBrand = _extractBrandFromProduct(product);

        if (productBrand == null || productBrand.trim().isEmpty) {
          continue;
        }

        final marca = brandByNormalizedName[_normalizeBrandValue(productBrand)];
        if (marca == null) {
          continue;
        }

        final brandId = _termIdFromDynamic(marca['id']);
        if (brandId == null || brandId <= 0) {
          continue;
        }

        countsByBrandId[brandId] = (countsByBrandId[brandId] ?? 0) + 1;
      }

      final disponibles = <Map<String, dynamic>>[];

      for (final marca in marcas) {
        final brandId = _termIdFromDynamic(marca['id']);
        if (brandId == null || brandId <= 0) {
          continue;
        }

        final count = countsByBrandId[brandId] ?? 0;

        if (count <= 0) {
          continue;
        }

        disponibles.add({
          ...marca,
          'available_count': count,
        });
      }

      disponibles.sort(
            (a, b) => (a['name']?.toString().toLowerCase() ?? '').compareTo(
          b['name']?.toString().toLowerCase() ?? '',
        ),
      );

      _marcasDisponiblesCache[cacheKey] = _MarcasDisponiblesCache(
        marcas: disponibles,
        timestamp: DateTime.now(),
      );

      if (_marcasDisponiblesCache.length > 50) {
        final entries = _marcasDisponiblesCache.entries.toList()
          ..sort((a, b) => a.value.timestamp.compareTo(b.value.timestamp));
        for (final entry in entries.take(10)) {
          _marcasDisponiblesCache.remove(entry.key);
        }
      }

      if (kDebugMode) {
        debugPrint(
          '🏷️ Marcas compatibles por filtros/local: category=$categoryId '
              'search="${search?.trim()}" total=${disponibles.length}',
        );
      }

      return disponibles;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Fallback local de marcas agotado: $e');
      }
      return [];
    }
  }


  // ================================================================
  // FILTROS CATÁLOGO COMO WEB MUNDICAM
  // ================================================================

  static const List<CatalogFilterDefinition> _catalogFilterDefinitions = [
    CatalogFilterDefinition(
      key: 'fabricante',
      title: 'Fabricante',
      taxonomy: 'pa_marcas',
      attributeId: 26,
    ),
    CatalogFilterDefinition(
      key: 'resolucion',
      title: 'Resolución',
      taxonomy: 'pa_resolucion',
      attributeId: 4,
    ),
    CatalogFilterDefinition(
      key: 'lente',
      title: 'Lente',
      taxonomy: 'pa_lente',
      attributeId: 1,
    ),
    CatalogFilterDefinition(
      key: 'proteccion',
      title: 'Protección',
      taxonomy: 'pa_proteccion',
      attributeId: 7,
    ),
    CatalogFilterDefinition(
      key: 'microfono',
      title: 'Micrófono Integrado',
      taxonomy: 'pa_microfono-integrado',
      attributeId: 2,
    ),
    CatalogFilterDefinition(
      key: 'wifi',
      title: 'WIFI',
      taxonomy: 'pa_wifi',
      attributeId: 6,
    ),
    CatalogFilterDefinition(
      key: 'ancho_banda',
      title: 'Ancho de Banda',
      taxonomy: 'pa_ancho-de-banda',
      attributeId: 9,
    ),
    CatalogFilterDefinition(
      key: 'grabacion_main_stream',
      title: 'Grabación Main Stream',
      taxonomy: 'pa_grabacion-main-stream',
      attributeId: 11,
    ),
    CatalogFilterDefinition(
      key: 'protocolo',
      title: 'Protocolo',
      taxonomy: 'pa_protocolo',
      attributeId: 3,
    ),
    CatalogFilterDefinition(
      key: 'smd',
      title: 'SMD+',
      taxonomy: 'pa_smd',
      attributeId: 12,
    ),
  ];

  String _catalogFiltersCacheKey({
    required int categoryId,
    String? search,
  }) {
    return [
      'category:$categoryId',
      'search:${search?.trim().toLowerCase() ?? ''}',
    ].join('|');
  }

  Map<int, int> _parseAttributeCounts(dynamic data) {
    final counts = <int, int>{};

    if (data is! List) {
      return counts;
    }

    for (final raw in data) {
      if (raw is! Map) continue;

      final item = Map<dynamic, dynamic>.from(raw);
      final termId = _parseIntValue(item['term']);
      final count = _parseIntValue(item['count']);

      if (termId > 0 && count > 0) {
        counts[termId] = count;
      }
    }

    return counts;
  }

  Future<List<Map<String, dynamic>>> _getAttributeTerms(
      CatalogFilterDefinition definition,
      ) async {
    final cached = _attributeTermsCache[definition.attributeId];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    final terms = <Map<String, dynamic>>[];

    int page = 1;
    int totalPages = 1;

    do {
      final response = await _dio.get(
        '/wp-json/wc/v3/products/attributes/${definition.attributeId}/terms',
        queryParameters: {
          'per_page': 100,
          'page': page,
          'hide_empty': false,
        },
        options: _wooOptions,
      );

      final data = response.data is List ? response.data as List : [];

      for (final raw in data) {
        if (raw is! Map) continue;

        final term = Map<String, dynamic>.from(raw);
        final id = _parseIntValue(term['id']);
        final name = term['name']?.toString().trim() ?? '';

        if (id <= 0 || name.isEmpty) continue;

        terms.add({
          'id': id,
          'name': name,
          'slug': term['slug']?.toString().trim() ?? '',
          'taxonomy': definition.taxonomy,
          'attribute_id': definition.attributeId,
        });
      }

      totalPages = _parseHeaderInt(response.headers, 'x-wp-totalpages', 1);
      page++;
    } while (page <= totalPages);

    _attributeTermsCache[definition.attributeId] = terms;

    return terms;
  }


  CatalogFilterDefinition? _catalogFilterDefinitionForKeyOrTitle({
    String? key,
    String? title,
    String? taxonomy,
  }) {
    final cleanTaxonomy = taxonomy?.trim() ?? '';
    if (cleanTaxonomy.isNotEmpty) {
      final byTaxonomy = _catalogFilterDefinitionForTaxonomy(cleanTaxonomy);
      if (byTaxonomy != null) return byTaxonomy;
    }

    final normalizedKey = _normalizeBrandValue(key ?? '');
    final normalizedTitle = _normalizeBrandValue(title ?? '');

    for (final definition in _catalogFilterDefinitions) {
      if (normalizedKey.isNotEmpty &&
          _normalizeBrandValue(definition.key) == normalizedKey) {
        return definition;
      }

      if (normalizedTitle.isNotEmpty &&
          _normalizeBrandValue(definition.title) == normalizedTitle) {
        return definition;
      }
    }

    return null;
  }

  List<CatalogFilterGroup> _parseMundicamCatalogFiltersResponse(dynamic rawData) {
    dynamic data = rawData;

    if (data is Map && data['data'] != null) {
      data = data['data'];
    }

    dynamic rawFilters;

    if (data is Map) {
      rawFilters = data['filters'] ?? data['groups'] ?? data['items'];
    } else if (data is List) {
      rawFilters = data;
    }

    if (rawFilters is! List) {
      return const <CatalogFilterGroup>[];
    }

    final groups = <CatalogFilterGroup>[];

    for (final rawGroup in rawFilters) {
      if (rawGroup is! Map) continue;

      final groupMap = Map<dynamic, dynamic>.from(rawGroup);
      final key = groupMap['key']?.toString().trim() ?? '';
      final title = groupMap['title']?.toString().trim() ??
          groupMap['name']?.toString().trim() ??
          key;
      final taxonomy = groupMap['taxonomy']?.toString().trim() ?? '';
      final definition = _catalogFilterDefinitionForKeyOrTitle(
        key: key,
        title: title,
        taxonomy: taxonomy,
      );

      final finalTaxonomy = taxonomy.isNotEmpty
          ? taxonomy
          : definition?.taxonomy ?? key;
      final attributeId = _parseIntValue(
        groupMap['attribute_id'] ?? groupMap['attributeId'],
        fallback: definition?.attributeId ?? 0,
      );

      final rawOptions = groupMap['options'];
      if (rawOptions is! List) continue;

      final options = <CatalogFilterOption>[];
      for (final rawOption in rawOptions) {
        if (rawOption is! Map) continue;

        final optionMap = Map<dynamic, dynamic>.from(rawOption);
        final id = _parseIntValue(
          optionMap['id'] ?? optionMap['term_id'] ?? optionMap['term'],
        );
        final name = optionMap['name']?.toString().trim() ??
            optionMap['label']?.toString().trim() ??
            '';
        final slug = optionMap['slug']?.toString().trim() ?? '';
        final count = _parseIntValue(
          optionMap['count'] ??
              optionMap['available_count'] ??
              optionMap['product_count'] ??
              optionMap['total'],
        );

        if (id <= 0 || name.isEmpty || count <= 0) continue;

        options.add(
          CatalogFilterOption(
            id: id,
            name: name,
            slug: slug,
            count: count,
          ),
        );
      }

      if (options.isEmpty) continue;

      options.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      groups.add(
        CatalogFilterGroup(
          key: key.isNotEmpty ? key : definition?.key ?? finalTaxonomy,
          title: title.isNotEmpty ? title : definition?.title ?? finalTaxonomy,
          taxonomy: finalTaxonomy,
          attributeId: attributeId,
          options: options,
        ),
      );
    }

    return groups;
  }

  Future<List<CatalogFilterGroup>> _loadMundicamCatalogFiltersEndpoint({
    required int categoryId,
    String? search,
  }) async {
    final query = <String, dynamic>{
      'category_id': categoryId,
      'include_subcategories': false,
    };

    final cleanSearch = search?.trim();
    if (cleanSearch != null && cleanSearch.isNotEmpty) {
      query['search'] = cleanSearch;
    }

    final attempts = <Options>[
      _appOptions,
      _storeApiOptions,
      Options(
        headers: const <String, dynamic>{
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ),
    ];

    DioException? lastDioError;
    Object? lastError;

    for (final options in attempts) {
      try {
        final response = await _dio.get(
          '/wp-json/mundicam/v1/catalog-filters',
          queryParameters: query,
          options: options,
        ).timeout(const Duration(seconds: 8));

        final groups = _parseMundicamCatalogFiltersResponse(response.data);

        if (kDebugMode) {
          debugPrint(
            '✅ Filtros endpoint MundiCam category=$categoryId grupos=${groups.length}',
          );
        }

        return groups;
      } on DioException catch (e) {
        lastDioError = e;
        lastError = e;
        final status = e.response?.statusCode;

        if (kDebugMode) {
          debugPrint(
            '⚠️ Intento filtros endpoint MundiCam fallido status=$status: ${e.message}',
          );
        }

        // 401/403 puede depender de cookies/token. Probamos el siguiente modo.
        if (status == 401 || status == 403) continue;
        continue;
      } catch (e) {
        lastError = e;
        if (kDebugMode) {
          debugPrint('⚠️ Intento filtros endpoint MundiCam fallido: $e');
        }
      }
    }

    if (lastDioError != null) throw lastDioError;
    throw Exception(lastError ?? 'No se pudieron cargar filtros MundiCam.');
  }

  bool _catalogAttributeNameMatchesDefinition(
      String attrName,
      CatalogFilterDefinition definition,
      ) {
    final normalizedAttr = _normalizeBrandValue(attrName);
    if (normalizedAttr.isEmpty) return false;

    final normalizedTaxonomy = _normalizeBrandValue(
      definition.taxonomy.replaceFirst('pa_', ''),
    );
    final normalizedTitle = _normalizeBrandValue(definition.title);
    final normalizedKey = _normalizeBrandValue(definition.key);

    return normalizedAttr == normalizedTaxonomy ||
        normalizedAttr == normalizedTitle ||
        normalizedAttr == normalizedKey ||
        normalizedAttr.contains(normalizedTaxonomy) ||
        (normalizedTitle.isNotEmpty && normalizedAttr.contains(normalizedTitle)) ||
        (normalizedKey.isNotEmpty && normalizedAttr.contains(normalizedKey));
  }

  int _stableLocalTermId(String taxonomy, String label) {
    final text = '$taxonomy|$label';
    var hash = 0x811c9dc5;
    for (final codeUnit in text.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash <= 0 ? text.length + 100000 : hash;
  }

  Future<List<CatalogFilterGroup>> _buildCatalogFiltersFromProductsLocal({
    required int categoryId,
    String? search,
  }) async {
    final products = await _getProductsForFilterContext(
      categoryId: categoryId,
      search: search,
      orderBy: 'date',
    ).timeout(const Duration(seconds: 10));

    if (products.isEmpty) {
      return const <CatalogFilterGroup>[];
    }

    final groups = <CatalogFilterGroup>[];

    for (final definition in _catalogFilterDefinitions) {
      final countsByLabel = <String, int>{};
      final displayByLabel = <String, String>{};

      for (final product in products) {
        final labelsForProduct = <String>{};

        if (definition.taxonomy == 'pa_marcas' || definition.taxonomy == 'pa_marca') {
          final brand = product.brandName?.trim();
          if (brand != null && brand.isNotEmpty) {
            labelsForProduct.add(brand);
          }
        }

        for (final attr in product.attributes) {
          if (!_catalogAttributeNameMatchesDefinition(attr.name, definition)) {
            continue;
          }

          for (final option in attr.options) {
            final clean = option.trim();
            if (clean.isNotEmpty) {
              labelsForProduct.add(clean);
            }
          }
        }

        for (final label in labelsForProduct) {
          final normalized = _normalizeBrandValue(label);
          if (normalized.isEmpty) continue;

          countsByLabel[normalized] = (countsByLabel[normalized] ?? 0) + 1;
          displayByLabel.putIfAbsent(normalized, () => label);
        }
      }

      if (countsByLabel.isEmpty) continue;

      final termsByName = <String, Map<String, dynamic>>{};
      try {
        final terms = await _getAttributeTerms(definition).timeout(
          const Duration(seconds: 4),
        );

        for (final term in terms) {
          final name = term['name']?.toString().trim() ?? '';
          if (name.isEmpty) continue;
          termsByName[_normalizeBrandValue(name)] = term;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ No se pudieron resolver términos para ${definition.taxonomy}: $e');
        }
      }

      final options = <CatalogFilterOption>[];
      final fallbackLabels = _localFilterTermLabelsByTaxonomy.putIfAbsent(
        definition.taxonomy,
            () => <int, String>{},
      );

      for (final entry in countsByLabel.entries) {
        final normalizedLabel = entry.key;
        final count = entry.value;
        final display = displayByLabel[normalizedLabel] ?? normalizedLabel;
        final term = termsByName[normalizedLabel];
        final id = _parseIntValue(term?['id']);
        final slug = term?['slug']?.toString().trim() ?? '';
        final optionId = id > 0 ? id : _stableLocalTermId(definition.taxonomy, display);

        fallbackLabels[optionId] = display;

        options.add(
          CatalogFilterOption(
            id: optionId,
            name: display,
            slug: slug,
            count: count,
          ),
        );
      }

      options.sort((a, b) {
        final countCompare = b.count.compareTo(a.count);
        if (countCompare != 0) return countCompare;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      groups.add(
        CatalogFilterGroup(
          key: definition.key,
          title: definition.title,
          taxonomy: definition.taxonomy,
          attributeId: definition.attributeId,
          options: options.take(30).toList(),
        ),
      );
    }

    if (kDebugMode) {
      debugPrint(
        '✅ Filtros locales generados category=$categoryId grupos=${groups.length}',
      );
    }

    return groups;
  }


  List<CatalogFilterGroup> buildLocalCatalogFiltersFromProducts(
      List<Product> products,
      ) {
    if (products.isEmpty) {
      return const <CatalogFilterGroup>[];
    }

    final groups = <CatalogFilterGroup>[];

    for (final definition in _catalogFilterDefinitions) {
      final countsByLabel = <String, int>{};
      final displayByLabel = <String, String>{};

      for (final product in products) {
        final labelsForProduct = <String>{};

        if (definition.taxonomy == 'pa_marcas' || definition.taxonomy == 'pa_marca') {
          final brand = product.brandName?.trim();
          if (brand != null && brand.isNotEmpty) {
            labelsForProduct.add(brand);
          }
        }

        for (final attr in product.attributes) {
          if (!_catalogAttributeNameMatchesDefinition(attr.name, definition)) {
            continue;
          }

          for (final option in attr.options) {
            final clean = option.trim();
            if (clean.isNotEmpty) {
              labelsForProduct.add(clean);
            }
          }
        }

        for (final label in labelsForProduct) {
          final normalized = _normalizeBrandValue(label);
          if (normalized.isEmpty) continue;

          countsByLabel[normalized] = (countsByLabel[normalized] ?? 0) + 1;
          displayByLabel.putIfAbsent(normalized, () => label);
        }
      }

      if (countsByLabel.isEmpty) continue;

      final fallbackLabels = _localFilterTermLabelsByTaxonomy.putIfAbsent(
        definition.taxonomy,
            () => <int, String>{},
      );

      final options = <CatalogFilterOption>[];

      for (final entry in countsByLabel.entries) {
        final display = displayByLabel[entry.key] ?? entry.key;
        final optionId = _stableLocalTermId(definition.taxonomy, display);
        fallbackLabels[optionId] = display;

        options.add(
          CatalogFilterOption(
            id: optionId,
            name: display,
            slug: '',
            count: entry.value,
          ),
        );
      }

      options.sort((a, b) {
        final countCompare = b.count.compareTo(a.count);
        if (countCompare != 0) return countCompare;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      groups.add(
        CatalogFilterGroup(
          key: definition.key,
          title: definition.title,
          taxonomy: definition.taxonomy,
          attributeId: definition.attributeId,
          options: options.take(30).toList(),
        ),
      );
    }

    return groups;
  }

  Future<List<CatalogFilterGroup>> getCatalogFiltersForCategory({
    required int categoryId,
    String? search,
    bool forceRefresh = false,
  }) async {
    await _ensureInitialized();

    if (categoryId <= 0) {
      return [];
    }

    final cacheKey = _catalogFiltersCacheKey(
      categoryId: categoryId,
      search: search,
    );

    if (!forceRefresh) {
      final cached = _catalogFiltersCache[cacheKey];
      if (cached != null && cached.isValid) {
        if (kDebugMode) {
          debugPrint('⚡ Filtros catálogo desde caché: $cacheKey');
        }
        return cached.groups;
      }
    }

    List<CatalogFilterGroup> groups = const <CatalogFilterGroup>[];

    // 1) Endpoint propio nuevo: /wp-json/mundicam/v1/catalog-filters.
    // Es el que debe usar la app. Ya no se depende de endpoint antiguo de WooCommerce porque
    // en cliente normal y en algunas sesiones devuelve 401/403.
    try {
      groups = await _loadMundicamCatalogFiltersEndpoint(
        categoryId: categoryId,
        search: search,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Endpoint MundiCam filtros no disponible, usando fallback local: $e');
      }
    }

    // 2) Fallback local real desde los productos de la categoría.
    // Así admin y cliente siguen viendo filtros aunque el endpoint falle.
    if (groups.isEmpty) {
      try {
        groups = await _buildCatalogFiltersFromProductsLocal(
          categoryId: categoryId,
          search: search,
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Fallback local de filtros no disponible: $e');
        }
      }
    }

    _catalogFiltersCache[cacheKey] = _CatalogFiltersCacheEntry(
      groups: groups,
      createdAt: DateTime.now(),
    );

    if (kDebugMode) {
      debugPrint(
        '📊 Filtros catálogo finales category=$categoryId grupos=${groups.length}',
      );
      for (final group in groups) {
        debugPrint('   ${group.title}: ${group.options.length} opciones');
      }
    }

    return groups;
  }

  Future<List<Map<String, dynamic>>> getBrandsForCategory(
      int categoryId, {
        String? search,
      }) async {
    final groups = await getCatalogFiltersForCategory(
      categoryId: categoryId,
      search: search,
    );

    final fabricanteGroup = groups.where(
          (group) => group.taxonomy == 'pa_marcas',
    );

    if (fabricanteGroup.isEmpty) {
      return [];
    }

    return fabricanteGroup.first.options.map((option) {
      return {
        ...option.toMap(),
        'taxonomy': 'pa_marcas',
        'attribute_id': 26,
        'source': 'mundicam_catalog_filters',
      };
    }).toList();
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

    bool esCategoriaProhibida(CategoryModel cat) {
      final normalizedName = cat.name
          .toLowerCase()
          .trim()
          .replaceAll('á', 'a')
          .replaceAll('à', 'a')
          .replaceAll('ä', 'a')
          .replaceAll('â', 'a')
          .replaceAll('é', 'e')
          .replaceAll('è', 'e')
          .replaceAll('ë', 'e')
          .replaceAll('ê', 'e')
          .replaceAll('í', 'i')
          .replaceAll('ì', 'i')
          .replaceAll('ï', 'i')
          .replaceAll('î', 'i')
          .replaceAll('ó', 'o')
          .replaceAll('ò', 'o')
          .replaceAll('ö', 'o')
          .replaceAll('ô', 'o')
          .replaceAll('ú', 'u')
          .replaceAll('ù', 'u')
          .replaceAll('ü', 'u')
          .replaceAll('û', 'u')
          .replaceAll('ñ', 'n')
          .replaceAll(RegExp(r'\s+'), '');

      return normalizedName.contains('sincategoria') ||
          normalizedName.contains('uncategorized');
    }

    bool tieneProductos(CategoryModel cat) {
      if (cat.id <= 0 || esCategoriaProhibida(cat)) return false;
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
      throw Exception('Error en noticias');
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

    final cleanOrderId = orderId.replaceAll(RegExp(r'[^0-9]'), '');

    if (cleanOrderId.isEmpty) return null;

    try {
      final response = await _dio.get(
        '/wp-json/wc/v3/orders/$cleanOrderId',
        options: _wooOptions,
      );

      if (response.statusCode == 200 && response.data is Map) {
        final orderData = Map<String, dynamic>.from(response.data as Map);
        final rawLineItems = orderData['line_items'];
        final lineItems = rawLineItems is List ? rawLineItems : <dynamic>[];

        debugPrint(
          '📦 Orden #$cleanOrderId cargada con ${lineItems.length} producto(s)',
        );

        return orderData;
      }

      return null;
    } catch (e) {
      debugPrint('Error al obtener orden $cleanOrderId: $e');
      return null;
    }
  }
  Future<List<QuoteMundicam>> getPresupuestosPorEmail(String email) async {
    try {
      final response = await _appGet('/quotes');
      final rawQuotes = _extractAppList(
        response.data,
        const ['quotes', 'data', 'items'],
      );

      final quotes = <QuoteMundicam>[];

      for (final rawQuote in rawQuotes) {
        if (rawQuote is! Map) continue;

        try {
          final item = Map<String, dynamic>.from(rawQuote);

          // Blindaje frente a campos null del backend.
          item['id'] = item['id']?.toString() ?? item['order_id']?.toString() ?? '';
          item['number'] = item['number']?.toString() ?? item['id']?.toString() ?? '';
          item['status'] = item['status']?.toString() ?? '';
          item['date_created'] = item['date_created']?.toString() ??
              item['date']?.toString() ??
              item['created_at']?.toString() ??
              '';
          item['total'] = item['total']?.toString() ?? '0.00';
          item['customer_email'] = item['customer_email']?.toString() ??
              item['billing_email']?.toString() ??
              email;

          quotes.add(QuoteMundicam.fromJson(item));
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ Presupuesto ignorado por formato no compatible: $e');
          }
        }
      }

      return quotes;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error getPresupuestosPorEmail App API: $e');
      }
      return [];
    }
  }



  // ================================================================
  // PRODUCTO POR ID
  // ================================================================

  Future<Product?> getProductoById(int id) async {
    if (id <= 0) return null;

    try {
      final response = await _appGet('/products/$id');
      final productMap = _extractAppMap(
        response.data,
        const ['product', 'data'],
      );

      if (productMap == null || productMap.isEmpty) return null;

      return Product.fromJson(productMap);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error al obtener producto $id desde App API: $e');
      }
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

      case DioExceptionType.receiveTimeout:
        return 'Tiempo de respuesta agotado';

      case DioExceptionType.sendTimeout:
        return 'Tiempo de envío agotado';

      case DioExceptionType.badResponse:
        if (e.response?.statusCode == 401) {
          return 'Error de autenticación (401). Verifica las credenciales API.';
        }

        if (e.response?.statusCode == 403) {
          return 'No tienes permisos para realizar esta acción.';
        }

        if (e.response?.statusCode == 404) {
          return 'No se encontró el recurso solicitado.';
        }

        if (e.response?.statusCode == 400) {
          final data = e.response?.data;

          if (data is Map && data['message'] != null) {
            return data['message'].toString();
          }

          return 'Solicitud no válida. Revisa los datos enviados.';
        }

        final data = e.response?.data;

        if (data is Map && data['message'] != null) {
          return data['message'].toString();
        }

        return 'Error del servidor: ${e.response?.statusCode}';

      case DioExceptionType.cancel:
        return 'Petición cancelada';

      default:
        return 'Error de red: ${e.message}';
    }
  }

}
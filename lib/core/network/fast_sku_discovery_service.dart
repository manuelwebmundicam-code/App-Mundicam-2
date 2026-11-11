import 'package:dio/dio.dart';

/// Descubrimiento rápido de referencias desde el índice PÚBLICO del VPS.
///
/// Esta respuesta NUNCA es un producto comercial. Precio, descuento, stock
/// y permisos solo deben obtenerse de la App API autenticada en WordPress.
/// Desactivado por defecto hasta validar HTTPS, QA y equivalencia de SKUs.
class FastSkuDiscoveryService {
  FastSkuDiscoveryService({
    Dio? dio,
    bool? fastSkuEnabled,
    bool? fastCatalogEnabled,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _enabled = fastSkuEnabled ?? enabled,
       _catalogEnabled = fastCatalogEnabled ?? catalogEnabled,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: endpoint,
               connectTimeout: const Duration(milliseconds: 1200),
               receiveTimeout: const Duration(milliseconds: 1200),
               headers: const {'Accept': 'application/json'},
             ),
           );

  static const bool enabled = bool.fromEnvironment(
    'MUNDICAM_FAST_SKU_ENABLED',
    defaultValue: false,
  );

  /// Opt-in para nombres y fabricantes; sin alterar el buscador comercial.
  static const bool catalogEnabled = bool.fromEnvironment(
    'MUNDICAM_FAST_CATALOG_ENABLED',
    defaultValue: false,
  );

  static const String endpoint = String.fromEnvironment(
    'MUNDICAM_FAST_SKU_URL',
    defaultValue: 'https://app.mundicam.com/app-fast/v1',
  );

  final Dio _dio;
  final bool _enabled;
  final bool _catalogEnabled;
  final DateTime Function() _clock;
  int _consecutiveFailures = 0;
  DateTime? _retryAfter;
  static const Duration _emptyCacheLifetime = Duration(seconds: 8);
  static const Duration _failureCooldown = Duration(seconds: 15);

  void _recordFailure() {
    _consecutiveFailures++;
    if (_consecutiveFailures >= 2) {
      _retryAfter = _clock().add(_failureCooldown);
      _consecutiveFailures = 0;
    }
  }

  void _recordSuccess() {
    _consecutiveFailures = 0;
    _retryAfter = null;
  }

  bool get isEnabled => _enabled;
  bool get canSuggestCatalog => _catalogEnabled;
  final Map<String, ({DateTime savedAt, List<FastSkuSuggestion> items})>
  _recent = {};
  final Map<String, Future<List<FastSkuSuggestion>>> _inFlight = {};
  static const Duration _cacheLifetime = Duration(seconds: 45);

  /// No se delegan marcas, categorías, frases ni búsquedas generales.
  static bool isSkuPrefix(String query) {
    final raw = query.trim();
    if (raw.length < 5 || raw.length > 80 || raw.contains(RegExp(r'\s'))) {
      return false;
    }
    return RegExp(r'[A-Za-z]').hasMatch(raw) &&
        RegExp(r'\d').hasMatch(raw) &&
        RegExp(r'^[A-Za-z0-9._/+()\-]+$').hasMatch(raw);
  }

  /// Coincidencias públicas por nombre, fabricante o tecnología.
  /// Nunca son fichas comerciales ni reemplazan los resultados de WooCommerce.
  Future<List<FastSkuSuggestion>> suggestCatalog(
    String query, {
    int limit = 5,
  }) {
    final q = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (!_catalogEnabled ||
        q.length < 3 ||
        q.length > 80 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(q) ||
        isSkuPrefix(q)) {
      return Future.value(const <FastSkuSuggestion>[]);
    }
    return _suggestInternal(q, limit, skuOnly: false);
  }

  Future<List<FastSkuSuggestion>> suggest(String query, {int limit = 5}) {
    if (!_enabled || !isSkuPrefix(query)) {
      return Future.value(const <FastSkuSuggestion>[]);
    }
    return _suggestInternal(query.trim(), limit, skuOnly: true);
  }

  Future<List<FastSkuSuggestion>> _suggestInternal(
    String q,
    int limit, {
    required bool skuOnly,
  }) async {
    final cap = limit.clamp(1, 8);
    final cacheKey =
        (skuOnly ? 'sku|' : 'catalog|') +
        q.toLowerCase() +
        '|' +
        cap.toString();
    final cached = _recent[cacheKey];
    if (cached != null &&
        _clock().difference(cached.savedAt) <
            (cached.items.isEmpty ? _emptyCacheLifetime : _cacheLifetime)) {
      return cached.items;
    }
    final pending = _inFlight[cacheKey];
    if (pending != null) return pending;
    // El fallo reiterado de VPS nunca debe frenar el buscador comercial:
    // desactivar peticiones públicas durante 15 segundos y dejar hacer fallback.
    if (_retryAfter != null && _clock().isBefore(_retryAfter!)) {
      return const <FastSkuSuggestion>[];
    }
    final request = _fetchSuggestions(q, cap, cacheKey, skuOnly: skuOnly);
    _inFlight[cacheKey] = request;
    try {
      return await request;
    } finally {
      _inFlight.remove(cacheKey);
    }
  }

  Future<List<FastSkuSuggestion>> _fetchSuggestions(
    String q,
    int cap,
    String cacheKey, {
    required bool skuOnly,
  }) async {
    try {
      final result = await _dio.get<Map<String, dynamic>>(
        '/suggest',
        queryParameters: <String, dynamic>{'q': q, 'limit': cap},
        options: Options(
          headers: const <String, dynamic>{'Accept': 'application/json'},
          responseType: ResponseType.json,
        ),
      );
      if (result.statusCode != 200) {
        _recordFailure();
        return const <FastSkuSuggestion>[];
      }
      final data = result.data;
      if (data == null ||
          data['scope'] != 'public_metadata_only' ||
          data['requires_authenticated_hydration'] != true ||
          data['results'] is! List) {
        _recordFailure();
        return const <FastSkuSuggestion>[];
      }
      final items = <FastSkuSuggestion>[];
      final ids = <int>{};
      for (final row in data['results'] as List<dynamic>) {
        if (row is! Map) continue;
        final value = FastSkuSuggestion.tryParse(row);
        if (value == null || !ids.add(value.id)) continue;
        // El índice público puede coincidir por título. Sólo aceptamos SKU
        // cuyo prefijo real corresponda a lo que está escribiendo el técnico.
        if (skuOnly && !value.sku.toLowerCase().startsWith(q.toLowerCase())) {
          continue;
        }
        items.add(value);
        if (items.length >= cap) break;
      }
      _recordSuccess();
      // Las búsquedas sin coincidencias reales no deben repetir peticiones
      // mientras el instalador sigue tecleando la misma referencia.
      if (_recent.length >= 40) _recent.clear();
      _recent[cacheKey] = (savedAt: _clock(), items: List.unmodifiable(items));
      return items;
    } on DioException {
      _recordFailure();
      // El acelerador es opcional: si falla, el buscador autenticado existente
      // sigue trabajando como antes, sin errores visibles al cliente.
      return const <FastSkuSuggestion>[];
    } on FormatException {
      _recordFailure();
      return const <FastSkuSuggestion>[];
    } on TypeError {
      _recordFailure();
      return const <FastSkuSuggestion>[];
    }
  }
}

class FastSkuSuggestion {
  const FastSkuSuggestion({
    required this.id,
    required this.sku,
    required this.name,
  });

  final int id;
  final String sku;
  final String name;

  static FastSkuSuggestion? tryParse(Map<dynamic, dynamic> raw) {
    final id = raw['id'];
    final sku = raw['sku'];
    final name = raw['name'];
    if (id is! int ||
        id <= 0 ||
        sku is! String ||
        sku.isEmpty ||
        sku.length > 160 ||
        name is! String ||
        name.isEmpty ||
        name.length > 500) {
      return null;
    }
    return FastSkuSuggestion(id: id, sku: sku, name: name);
  }
}

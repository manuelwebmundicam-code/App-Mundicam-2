import 'dart:async';

import 'package:mundicam/features/catalog/data/models/producto.dart';

class ProductCacheService {
  static final ProductCacheService _instance = ProductCacheService._();
  factory ProductCacheService() => _instance;
  ProductCacheService._();

  static const Duration defaultTtl = Duration(minutes: 30);
  static const Duration searchTtl = Duration(minutes: 3);
  static const Duration suggestionsTtl = Duration(minutes: 3);
  static const Duration prewarmTtl = Duration(minutes: 12);
  static const int _maxMemoryEntries = 240;
  static const int _maxInflightEntries = 80;

  final Map<int, CacheEntry<List<Product>>> _categoryCache = {};
  final Map<int, CacheEntry<Product>> _productCache = {};

  /// Caché genérica de catálogo/buscador.
  ///
  /// Se usa para sacar peso de pantallas como productos_por_categoria.dart y
  /// providers: páginas de catálogo, respuestas API, sugerencias y precargas.
  final Map<String, CacheEntry<dynamic>> _memoryCache = {};

  /// Deduplicación de peticiones simultáneas.
  ///
  /// Si el autocomplete, el provider y la precarga piden la misma clave a la vez,
  /// solo se ejecuta una llamada real. El resto espera el mismo Future.
  final Map<String, Future<dynamic>> _inflight = {};

  final Map<String, DateTime> _prewarmRuns = {};

  List<Product>? getCachedProducts(int categoryId) {
    final entry = _categoryCache[categoryId];
    if (entry != null && !entry.isExpired) return entry.data;
    _categoryCache.remove(categoryId);
    return null;
  }

  void cacheProducts(int categoryId, List<Product> products) {
    _categoryCache[categoryId] = CacheEntry<List<Product>>(products);
  }

  Product? getCachedProduct(int productId) {
    final entry = _productCache[productId];
    if (entry != null && !entry.isExpired) return entry.data;
    _productCache.remove(productId);
    return null;
  }

  void cacheProduct(int productId, Product product) {
    _productCache[productId] = CacheEntry<Product>(product);
  }

  T? getMemory<T>(String key) {
    final entry = _memoryCache[key];
    if (entry == null) return null;
    if (entry.isExpired) {
      _memoryCache.remove(key);
      return null;
    }
    final data = entry.data;
    if (data is T) return data;
    return null;
  }

  void cacheMemory<T>(
      String key,
      T data, {
        Duration ttl = defaultTtl,
      }) {
    _memoryCache[key] = CacheEntry<T>(data, ttl: ttl);
    _trimMemoryCache();
  }

  /// Lee de memoria o ejecuta el loader una sola vez para la misma clave.
  ///
  /// Esto evita duplicar llamadas cuando el usuario escribe rápido, abre filtros
  /// o vuelve a una búsqueda recién consultada.
  Future<T> getOrLoadMemory<T>(
      String key, {
        required Future<T> Function() loader,
        Duration ttl = defaultTtl,
        bool forceRefresh = false,
      }) async {
    if (!forceRefresh) {
      final cached = getMemory<T>(key);
      if (cached != null) return cached;

      final running = _inflight[key];
      if (running != null) {
        final data = await running;
        if (data is T) return data;
      }
    } else {
      _memoryCache.remove(key);
    }

    final future = loader();
    _inflight[key] = future;
    _trimInflight();

    try {
      final data = await future;
      cacheMemory<T>(key, data, ttl: ttl);
      return data;
    } finally {
      final running = _inflight[key];
      if (identical(running, future)) {
        _inflight.remove(key);
      }
    }
  }

  void clearMemoryKey(String key) {
    _memoryCache.remove(key);
    _inflight.remove(key);
  }

  void clearMemoryPrefix(String prefix) {
    _memoryCache.removeWhere((key, value) => key.startsWith(prefix));
    _inflight.removeWhere((key, value) => key.startsWith(prefix));
  }

  void clearCatalogMemory() {
    clearMemoryPrefix('catalog_page|');
    clearMemoryPrefix('api_products|');
    clearMemoryPrefix('search_suggestions|');
  }

  bool shouldPrewarm(
      String key, {
        Duration ttl = prewarmTtl,
      }) {
    final lastRun = _prewarmRuns[key];
    if (lastRun == null) return true;
    return DateTime.now().difference(lastRun) > ttl;
  }

  void markPrewarmRun(String key) {
    _prewarmRuns[key] = DateTime.now();
    if (_prewarmRuns.length <= 80) return;

    final entries = _prewarmRuns.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    for (final entry in entries.take(_prewarmRuns.length - 80)) {
      _prewarmRuns.remove(entry.key);
    }
  }

  void _trimMemoryCache() {
    if (_memoryCache.length <= _maxMemoryEntries) return;

    final entries = _memoryCache.entries.toList()
      ..sort((a, b) => a.value.timestamp.compareTo(b.value.timestamp));
    final amountToRemove = _memoryCache.length - _maxMemoryEntries;

    for (final entry in entries.take(amountToRemove)) {
      _memoryCache.remove(entry.key);
    }
  }

  void _trimInflight() {
    if (_inflight.length <= _maxInflightEntries) return;
    final amountToRemove = _inflight.length - _maxInflightEntries;
    for (final key in _inflight.keys.take(amountToRemove).toList()) {
      _inflight.remove(key);
    }
  }

  void clearAll() {
    _categoryCache.clear();
    _productCache.clear();
    _memoryCache.clear();
    _inflight.clear();
    _prewarmRuns.clear();
  }
}

class CacheEntry<T> {
  final T data;
  final DateTime timestamp;
  final Duration ttl;

  CacheEntry(
      this.data, {
        this.ttl = ProductCacheService.defaultTtl,
      }) : timestamp = DateTime.now();

  bool get isExpired => DateTime.now().difference(timestamp) > ttl;
}

// services/product_cache_service.dart
import '../features/catalog/data/models/producto.dart';

class ProductCacheService {
  static final ProductCacheService _instance = ProductCacheService._();
  factory ProductCacheService() => _instance;
  ProductCacheService._();

  final Map<int, CacheEntry<List<Product>>> _categoryCache = {};
  final Map<int, CacheEntry<Product>> _productCache = {};
  static const Duration _ttl = Duration(minutes: 30);

  List<Product>? getCachedProducts(int categoryId) {
    final entry = _categoryCache[categoryId];
    if (entry != null && !entry.isExpired) return entry.data;
    return null;
  }

  void cacheProducts(int categoryId, List<Product> products) {
    _categoryCache[categoryId] = CacheEntry(products);
  }

  Product? getCachedProduct(int productId) {
    final entry = _productCache[productId];
    if (entry != null && !entry.isExpired) return entry.data;
    return null;
  }

  void cacheProduct(int productId, Product product) {
    _productCache[productId] = CacheEntry(product);
  }

  void clearAll() {
    _categoryCache.clear();
    _productCache.clear();
  }
}

class CacheEntry<T> {
  final T data;
  final DateTime timestamp;
  CacheEntry(this.data) : timestamp = DateTime.now();
  bool get isExpired =>
      DateTime.now().difference(timestamp) > ProductCacheService._ttl;
}

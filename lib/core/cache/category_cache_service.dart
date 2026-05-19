// services/category_cache_service.dart
import 'package:mundicam/features/catalog/data/models/category_model.dart';

class CategoryCacheService {
  static final CategoryCacheService _instance = CategoryCacheService._();
  factory CategoryCacheService() => _instance;
  CategoryCacheService._();

  List<CategoryModel>? _categorias;
  DateTime? _timestamp;
  static const Duration _ttl = Duration(hours: 2);

  List<CategoryModel>? getCachedCategories() {
    if (_categorias != null && _timestamp != null) {
      if (DateTime.now().difference(_timestamp!) < _ttl) return _categorias;
    }
    return null;
  }

  void cacheCategories(List<CategoryModel> categories) {
    _categorias = categories;
    _timestamp = DateTime.now();
  }

  void clearCache() {
    _categorias = null;
    _timestamp = null;
  }
}

/// Parámetros comerciales para /mundicam/v1/catalog-filters.
///
/// No contiene tokens: la autenticación se mantiene en ApiService._appOptions.
/// En producción, R19 opt-in permanece DESACTIVADO hasta QA en WordPress.
class CatalogFilterRequest {
  const CatalogFilterRequest._();

  static Map<String, dynamic> params({
    required int categoryId,
    int? brandId,
    String? search,
    bool fastFacetsOnly = false,
  }) {
    final cleanedSearch = search?.trim() ?? '';
    return <String, dynamic>{
      'category_id': categoryId,
      'include_subcategories': 1,
      if (brandId != null && brandId > 0) 'brand_id': brandId,
      if (brandId != null && brandId > 0) 'brandId': brandId,
      if (cleanedSearch.isNotEmpty) 'search': cleanedSearch,
      if (fastFacetsOnly) 'facets_only': 1,
    };
  }
}

/// Respuesta real R19: /mundicam/v1/catalog-filters devuelve un objeto plano
/// con 'filters', 'total_products', 'price_range' y 'stock_filter'.
/// Algunas versiones de integración pueden usar {data: {filters: [...]}}.
/// Un listado vacío de filtros es válido. Nunca exigimos success=true porque
/// el endpoint de producción no devuelve ese campo en respuestas satisfactorias.
class CatalogFilterResponseContract {
  const CatalogFilterResponseContract._();

  static bool isUsable(dynamic raw) {
    if (raw is! Map || raw['success'] == false) return false;
    if (raw['filters'] is List) return true;
    final nested = raw['data'];
    return nested is Map && nested['filters'] is List;
  }

  static Map<String, dynamic> unwrap(dynamic raw) {
    if (raw is! Map) return const <String, dynamic>{};
    final nested = raw['data'];
    return Map<String, dynamic>.from(
      nested is Map && nested['filters'] is List ? nested : raw,
    );
  }
}

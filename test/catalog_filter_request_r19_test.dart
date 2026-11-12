import 'package:flutter_test/flutter_test.dart';
import 'package:mundicam/core/network/catalog_filter_request.dart';

void main() {
  test('R17: sin flag no se envía facets_only ni cambia el contrato', () {
    final query = CatalogFilterRequest.params(categoryId: 144);
    expect(query, {'category_id': 144, 'include_subcategories': 1});
    expect(query.containsKey('facets_only'), isFalse);
  });

  test('R19 opt-in conserva filtros comerciales, marca y texto', () {
    final query = CatalogFilterRequest.params(
      categoryId: 44,
      brandId: 1714,
      search: '  cámara Turret  ',
      fastFacetsOnly: true,
    );
    expect(query, {
      'category_id': 44,
      'include_subcategories': 1,
      'brand_id': 1714,
      'brandId': 1714,
      'search': 'cámara Turret',
      'facets_only': 1,
    });
  });

  test('modo histórico y rápido solo difieren en facets_only', () {
    for (final id in [144, 44, 85, 49]) {
      final full = CatalogFilterRequest.params(
        categoryId: id,
        brandId: 1694,
        search: 'NVR 8CH',
      );
      final fast = CatalogFilterRequest.params(
        categoryId: id,
        brandId: 1694,
        search: 'NVR 8CH',
        fastFacetsOnly: true,
      );
      expect(fast..remove('facets_only'), full);
    }
  });

  test('una marca nula o inválida nunca crea filtro de marca', () {
    expect(
      CatalogFilterRequest.params(
        categoryId: 85,
        brandId: 0,
        search: ' ',
        fastFacetsOnly: true,
      ),
      {'category_id': 85, 'include_subcategories': 1, 'facets_only': 1},
    );
  });
}

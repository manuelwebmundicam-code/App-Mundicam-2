import 'package:flutter_test/flutter_test.dart';
import 'package:mundicam/features/catalog/presentation/providers/filter_provider.dart';

void main() {
  test('MundiCam: nueva categoría sin ordenar ni arrastrar filtros de otra marca', () {
    final filters = FilterNotifier();
    addTearDown(filters.dispose);

    MundiFilters? state;
    final stop = filters.addListener((value) => state = value, fireImmediately: true);
    addTearDown(stop);
    expect(state?.orderBy, isEmpty);
    filters.setBrand(name: 'Hikvision HiWatch', id: 1700);
    filters.setSearch('cámara');
    filters.toggleAttributeTerm(
      taxonomy: 'pa_resolucion',
      termId: 25,
      label: '4 MP',
      groupLabel: 'Resolución',
    );
    filters.setOrderBy('price_desc');

    filters.resetForCatalogCategory();

    expect(state?.brandId, isNull);
    expect(state?.brand, isEmpty);
    expect(state?.search, isEmpty);
    expect(state?.attributeTermIds, isEmpty);
    expect(state?.orderBy,
        mundicamQaNoDefaultSort ? '' : 'price_asc');

    filters.setOrderBy('price_asc');
    expect(state?.orderBy, 'price_asc');
  });
}

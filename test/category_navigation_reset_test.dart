import 'package:flutter_test/flutter_test.dart';
import 'package:mundicam/features/catalog/presentation/providers/filter_provider.dart';

void main() {
  test('cambio de categoria elimina marca y atributos en una sola transicion', () {
    final filters = FilterNotifier();
    MundiFilters? current;
    int notifications = 0;
    final stop = filters.addListener((value) {
      current = value;
      notifications++;
    }, fireImmediately: true);
    filters.setBrand(name: 'HIKVISION Hiwatch', id: 1714);
    filters.setSearch('camara');
    filters.setOrderBy('price_desc');
    filters.toggleAttributeTerm(
      taxonomy: 'pa_resolucion',
      termId: 3,
      label: '3 MP',
      groupLabel: 'Resolución',
    );
    final before = notifications;
    filters.resetForCatalogCategory();
    expect(notifications, before + 1);
    expect(current?.brand, '');
    expect(current?.brandId, null);
    expect(current?.search, '');
    expect(current?.attributeTermIds, isEmpty);
    expect(current?.orderBy, mundicamQaNoDefaultSort ? '' : 'price_asc');
    stop();
    filters.dispose();
  });

  test('una nueva categoria comienza con filtros predeterminados', () {
    final filters = FilterNotifier();
    MundiFilters? current;
    final stop = filters.addListener((value) => current = value,
        fireImmediately: true);
    filters.resetForCatalogCategory();
    expect(current, MundiFilters(orderBy: mundicamQaNoDefaultSort ? '' : 'price_asc'));
    stop();
    filters.dispose();
  });
}

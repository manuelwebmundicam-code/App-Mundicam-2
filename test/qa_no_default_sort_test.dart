import 'package:flutter_test/flutter_test.dart';
import 'package:mundicam/features/catalog/presentation/providers/filter_provider.dart';

void main() {
  test('release candidate defaults to backend catalog order', () {
    expect(
      mundicamQaNoDefaultSort,
      const bool.fromEnvironment(
        'MUNDICAM_QA_NO_DEFAULT_SORT',
        defaultValue: true,
      ),
    );
  });

  test('new category does not select a sort in QA, manual sort still works', () {
    final notifier = FilterNotifier();
    late MundiFilters current;
    final stop = notifier.addListener(
      (value) => current = value,
      fireImmediately: true,
    );
    expect(current.orderBy, isEmpty);
    notifier.resetForCatalogCategory();
    expect(current.orderBy, mundicamQaNoDefaultSort ? '' : 'price_asc');
    notifier.setOrderBy('price_desc');
    expect(current.orderBy, 'price_desc');
    notifier.setOrderBy('date');
    expect(current.orderBy, 'date');
    notifier.clearOrderBy();
    expect(current.orderBy, isEmpty);
    notifier.setBrand(name: 'HIKVISION Hiwatch', id: 123);
    notifier.resetForCatalogCategory();
    expect(current.brand, isEmpty);
    expect(current.brandId, null);
    expect(current.orderBy, mundicamQaNoDefaultSort ? '' : 'price_asc');
    stop();
    notifier.dispose();
  });
}

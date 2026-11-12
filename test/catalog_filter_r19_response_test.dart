import 'package:flutter_test/flutter_test.dart';
import 'package:mundicam/core/network/catalog_filter_request.dart';

void main() {
  test('compatibilidad: filtros planos sin success=true son válidos', () {
    final response = <String, dynamic>{
      'total_products': 5,
      'price_range': null,
      'stock_filter': null,
      'filters': [
        {
          'taxonomy': 'pa_tipo',
          'options': [
            {'id': 13, 'count': 5},
          ],
        },
      ],
    };
    expect(CatalogFilterResponseContract.isUsable(response), isTrue);
    expect(CatalogFilterResponseContract.unwrap(response)['total_products'], 5);
  });

  test('R19 real: respuesta con success y data.filters es compatible', () {
    final response = <String, dynamic>{
      'success': true,
      'data': {'filters': <dynamic>[], 'total_products': 0},
    };
    expect(CatalogFilterResponseContract.isUsable(response), isTrue);
    expect(CatalogFilterResponseContract.unwrap(response)['total_products'], 0);
  });

  test('respuesta denegada o sin filtros NO se considera faceta válida', () {
    expect(
      CatalogFilterResponseContract.isUsable({'success': false, 'filters': []}),
      isFalse,
    );
    expect(
      CatalogFilterResponseContract.isUsable({'message': 'unauthorized'}),
      isFalse,
    );
    expect(CatalogFilterResponseContract.isUsable(null), isFalse);
  });
}

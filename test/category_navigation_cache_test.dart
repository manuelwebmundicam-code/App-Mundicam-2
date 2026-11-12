import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mundicam/core/cache/product_cache_service.dart';
import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/features/catalog/data/models/producto.dart';
import 'package:mundicam/features/home/presentation/providers/banner_mix_provider.dart';
import 'package:mundicam/features/catalog/presentation/providers/filter_provider.dart';
import 'package:mundicam/features/catalog/presentation/providers/products_paginated_provider.dart';

class _CatalogTestApi implements ApiService {
  String identity = 'user:qaA|roles:distribuidor|stock0';
  int calls = 0;
  final List<String> requests = [];

  @override
  String get catalogCacheIdentity => identity;

  @override
  Future<int?> getMarcaIdPorNombre(String? name) async => null;

  @override
  Future<CatalogProductsResult> getProductosCatalogoFiltrado({
    int? categoryId,
    int? brandId,
    String? brandName,
    String? search,
    int page = 1,
    int perPage = 30,
    String? orderBy,
    Map<String, int>? attributeTermIds,
    Map<String, String>? attributeLabels,
  }) async {
    calls++;
    requests.add(
      '$identity|cat:$categoryId|brand:$brandId|'
      'order:$orderBy|attr:${attributeTermIds?.entries.toList()}',
    );
    final price = identity.contains('qaA') ? '12.34' : '56.78';
    return CatalogProductsResult(
      currentPage: page,
      totalPages: 1,
      totalItems: 1,
      products: [
        Product(
          id: 111,
          name: 'Referencia comercial ficticia',
          price: price,
          regularPrice: price,
          imageUrl: '',
          sku: 'TEST-111',
          stockQuantity: 1,
          onSale: false,
          isInstock: true,
          shortDescription: '',
          description: '',
          attributes: const [],
        ),
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _settled(ProductsPaginatedNotifier notifier) async {
  for (var i = 0; i < 40; i++) {
    if (notifier.hasLoadedFirstPage && !notifier.isLoading) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Catalog page never settled');
}

void main() {
  setUp(ProductCacheService().clearAll);

  test(
    'volver a la misma categoría reutiliza los precios B2B recientes',
    () async {
      final api = _CatalogTestApi();
      final container = ProviderContainer(
        overrides: [apiServiceProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      final sub = container.listen(productsPaginatedProvider(144), (_, __) {});
      addTearDown(sub.close);
      final notifier = container.read(productsPaginatedProvider(144).notifier);
      await _settled(notifier);
      expect(api.calls, 1);
      expect(
        container.read(productsPaginatedProvider(144)).single.price,
        '12.34',
      );

      notifier.showReloadingState();
      await notifier.loadFirstPage(restartPending: true);
      expect(api.calls, 1, reason: 'No repetir GET a Woo con caché reciente');
      expect(
        container.read(productsPaginatedProvider(144)).single.price,
        '12.34',
      );
    },
  );

  test(
    'marca, atributos y usuario nuevos nunca usan el catálogo anterior',
    () async {
      final api = _CatalogTestApi();
      final container = ProviderContainer(
        overrides: [apiServiceProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      final sub = container.listen(productsPaginatedProvider(44), (_, __) {});
      addTearDown(sub.close);
      final notifier = container.read(productsPaginatedProvider(44).notifier);
      await _settled(notifier);
      expect(api.calls, 1);

      final filters = container.read(productFilterProvider.notifier);
      filters.setBrand(name: 'HIKVISION Hiwatch', id: 1714);
      notifier.showReloadingState();
      await notifier.loadFirstPage(restartPending: true);
      expect(api.calls, 2);
      expect(api.requests.last, contains('brand:1714'));

      filters.toggleAttributeTerm(
        taxonomy: 'pa_resolucion',
        termId: 3,
        label: '3MP',
        groupLabel: 'Resolución',
      );
      notifier.showReloadingState();
      await notifier.loadFirstPage(restartPending: true);
      expect(api.calls, 3);
      expect(api.requests.last, contains('pa_resolucion'));

      filters.resetForCatalogCategory();
      notifier.showReloadingState();
      await notifier.loadFirstPage(restartPending: true);
      // Sin orden automático, el regreso reutiliza la primera página en caché.
      expect(api.calls, 3, reason: 'No recargar tras quitar marca y atributos');
      expect(container.read(productFilterProvider).brandId, isNull);
      expect(container.read(productFilterProvider).attributeTermIds, isEmpty);
      expect(container.read(productFilterProvider).orderBy, isEmpty);

      // Ordenación ELEGIDA por el cliente: consulta distinta y nueva clave.
      filters.setOrderBy('price_asc');
      notifier.showReloadingState();
      await notifier.loadFirstPage(restartPending: true);
      expect(api.calls, 4, reason: 'La ordenación manual distingue caché');
      expect(api.requests.last, contains('order:price_asc'));
      expect(api.requests.last, contains('brand:null'));

      api.identity = 'user:qaB|roles:mayorista|stock0';
      notifier.showReloadingState();
      await notifier.loadFirstPage(restartPending: true);
      expect(api.calls, 5, reason: 'Nunca compartir tarifa entre usuarios');
      expect(
        container.read(productsPaginatedProvider(44)).single.price,
        '56.78',
      );
    },
  );

  test(
    'actualización explícita invalida caché comercial de esa categoría',
    () async {
      final api = _CatalogTestApi();
      final container = ProviderContainer(
        overrides: [apiServiceProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      final sub = container.listen(productsPaginatedProvider(85), (_, __) {});
      addTearDown(sub.close);
      final notifier = container.read(productsPaginatedProvider(85).notifier);
      await _settled(notifier);
      expect(api.calls, 1);

      final cache = ProductCacheService();
      const apiKey =
          'api_products|user:qaA|roles:distribuidor|stock0|'
          'cat:85|brandId:0|page:1';
      const otherUserKey =
          'api_products|user:qaB|roles:mayorista|stock0|'
          'cat:85|brandId:0|page:1';
      cache.cacheMemory(apiKey, 'stale-sample');
      cache.cacheMemory(otherUserKey, 'unrelated-sample');

      notifier.clearCacheForCurrentCategory();
      expect(cache.getMemory<String>(apiKey), isNull);
      expect(
        cache.getMemory<String>(otherUserKey),
        'unrelated-sample',
        reason: 'Nunca eliminar caché de otro usuario al refrescar',
      );
      notifier.showReloadingState();
      await notifier.loadFirstPage(restartPending: true);
      expect(api.calls, 2, reason: 'La clave de invalidación debe coincidir');
    },
  );
}

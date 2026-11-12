import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mundicam/core/network/vps_catalog_service.dart';

Dio mockDio() {
  final dio = Dio(BaseOptions(baseUrl: 'https://app.mundicam.com/app-fast/v1'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (request, handler) {
        if (request.path == '/catalog/brands' &&
            request.queryParameters['source'] == 'complete') {
          return handler.resolve(
            Response(
              requestOptions: request,
              statusCode: 200,
              data: {
                'scope': 'public_metadata_only',
                'results': [
                  {
                    'id': 1713,
                    'name': 'HIKVISION',
                    'slug': 'hikvision',
                    'indexed_product_count': 1084,
                    'taxonomy': 'brand',
                    'vps_filter': 'xstore_brand',
                    'source': 'verified_storefront',
                  },
                  {
                    'id': 1714,
                    'name': 'HIKVISION Hiwatch',
                    'slug': 'hikvision-hiwatch',
                    'indexed_product_count': 98,
                    'taxonomy': 'brand',
                    'vps_filter': 'xstore_brand',
                    'source': 'verified_storefront',
                  },
                ],
              },
            ),
          );
        }
        if (request.path == '/catalog/brands' &&
            request.queryParameters['source'] == 'wp') {
          return handler.resolve(
            Response(
              requestOptions: request,
              statusCode: 200,
              data: {
                'scope': 'public_metadata_only',
                'results': [
                  {
                    'id': 3444,
                    'name': 'AISCAN',
                    'slug': 'aiscan',
                    'indexed_product_count': 3,
                    'taxonomy': 'brand',
                    'vps_filter': 'xstore_brand',
                    'source': 'wp_rest_verified',
                  },
                ],
              },
            ),
          );
        }
        if (request.path == '/catalog/brands') {
          return handler.resolve(
            Response(
              requestOptions: request,
              statusCode: 200,
              data: {
                'scope': 'public_metadata_only',
                'results': [
                  {
                    'id': 3231,
                    'name': 'DAHUA',
                    'slug': 'dahua',
                    'indexed_product_count': 708,
                  },
                ],
              },
            ),
          );
        }
        if (request.path == '/catalog/products') {
          if (request.queryParameters['taxonomy'] == 'category' &&
              request.queryParameters['id'] == 369) {
            expect(request.queryParameters['children'], '1');
          }
          return handler.resolve(
            Response(
              requestOptions: request,
              statusCode: 200,
              data: {
                'scope': 'public_metadata_only',
                'requires_authenticated_hydration': true,
                'total': 1,
                'results': [
                  {
                    'id': 10,
                    'sku': 'IPC-10',
                    'name': 'Cámara',
                    'image_url': 'https://example.com/a.png',
                    'price': '999',
                  },
                ],
              },
            ),
          );
        }
        handler.reject(DioException(requestOptions: request));
      },
    ),
  );
  return dio;
}

void main() {
  test('brands are public metadata only', () async {
    final service = VpsCatalogService(dio: mockDio());
    final brands = await service.brands();
    expect(brands.single['id'], 3231);
  });
  test('product metadata requires authenticated hydration', () async {
    final page = await VpsCatalogService(
      dio: mockDio(),
    ).productPage(taxonomy: 'brand', id: 3231);
    expect(page?['total'], 1);
    expect((page?['results'] as List).single.containsKey('price'), isFalse);
  });
  test(
    'real WP brands use explicit source and distinct XStore identity',
    () async {
      final brands = await VpsCatalogService(
        dio: mockDio(),
      ).verifiedWordPressBrands();
      expect(brands.single['id'], 3444);
      expect(brands.single['name'], 'AISCAN');
      expect(brands.single['vps_filter'], 'xstore_brand');
    },
  );
  test(
    'XStore brand products are candidates only, never commercial prices',
    () async {
      final page = await VpsCatalogService(
        dio: mockDio(),
      ).productPage(taxonomy: 'xstore_brand', id: 3444);
      expect(page?['total'], 1);
      expect((page?['results'] as List).single.containsKey('price'), isFalse);
      expect((page?['results'] as List).single.containsKey('stock'), isFalse);
    },
  );
  test(
    'full storefront brands preserve distinct XStore manufacturer IDs',
    () async {
      final brands = await VpsCatalogService(
        dio: mockDio(),
      ).verifiedCompleteBrands();
      expect(brands.length, 2);
      expect(brands.map((b) => b['id']).toList(), [1713, 1714]);
      expect(brands.map((b) => b['name']).toList(), [
        'HIKVISION',
        'HIKVISION Hiwatch',
      ]);
      expect(brands.last['indexed_product_count'], 98);
    },
  );
  test('category descendants use the existing public catalog route', () async {
    final page = await VpsCatalogService(
      dio: mockDio(),
    ).productPage(taxonomy: 'category', id: 369, includeChildren: true);
    expect(page?['total'], 1);
  });
  test('brand lookup cannot enable category descendants', () async {
    final page = await VpsCatalogService(
      dio: mockDio(),
    ).productPage(taxonomy: 'xstore_brand', id: 3444, includeChildren: true);
    expect(page, isNull);
  });
  test('invalid taxonomy is never sent to the VPS', () async {
    final page = await VpsCatalogService(
      dio: mockDio(),
    ).productPage(taxonomy: 'price', id: 3231);
    expect(page, isNull);
  });
}

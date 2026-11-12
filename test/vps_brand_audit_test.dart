import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mundicam/core/network/vps_brand_audit.dart';
import 'package:mundicam/core/network/vps_catalog_service.dart';

VpsBrandAudit fixture() {
  final dio = Dio(BaseOptions(baseUrl: 'https://app.mundicam.com/app-fast/v1'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'scope': 'public_metadata_only',
              'results': [
                {
                  'id': 3237,
                  'name': 'HIKVISION',
                  'slug': 'hikvision',
                  'indexed_product_count': 31,
                },
                {
                  'id': 3238,
                  'name': 'HIKVISION Hiwatch',
                  'slug': 'hiwatch',
                  'indexed_product_count': 0,
                },
              ],
            },
          ),
        );
      },
    ),
  );
  return VpsBrandAudit(catalog: VpsCatalogService(dio: dio));
}

void main() {
  test('HIKVISION and Hiwatch remain different brand IDs', () async {
    final result = await fixture().compare([
      {'id': 3237, 'name': 'HIKVISION'},
      {'id': 3238, 'name': 'HIKVISION Hiwatch'},
    ]);
    expect(result.matches, isTrue);
  });
  test('brand missing from source is visible to audit', () async {
    final result = await fixture().compare([
      {'id': 3237, 'name': 'HIKVISION'},
    ]);
    expect(result.missingInApp, [3238]);
    expect(result.matches, isFalse);
  });
  test(
    'different labels are reported without changing product listing',
    () async {
      final result = await fixture().compare([
        {'id': 3237, 'name': 'HIKVISION Hiwatch'},
        {'id': 3238, 'name': 'HIKVISION Hiwatch'},
      ]);
      expect(result.nameDifferences, [3237]);
    },
  );
}

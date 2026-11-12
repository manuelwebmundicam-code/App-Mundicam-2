import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mundicam/core/network/fast_sku_discovery_service.dart';

Dio fixtureDio(
  Map<String, dynamic> response, {
  void Function(RequestOptions request)? inspect,
  bool error = false,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://app.mundicam.com/app-fast/v1'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        inspect?.call(options);
        if (error) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionTimeout,
            ),
          );
          return;
        }
        handler.resolve(
          Response<Map<String, dynamic>>(
            requestOptions: options,
            statusCode: 200,
            data: response,
          ),
        );
      },
    ),
  );
  return dio;
}

void main() {
  const full = <String, dynamic>{
    'scope': 'public_metadata_only',
    'requires_authenticated_hydration': true,
    'results': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 199025,
        'sku': 'NVR4108-P-4KS3',
        'name': 'Grabador NVR Dahua',
        'price': '999999.00',
        'stock': 999,
      },
      <String, dynamic>{
        'id': 199025,
        'sku': 'NVR4108-P-4KS3',
        'name': 'Duplicado',
      },
      <String, dynamic>{
        'id': 100,
        'sku': 'IPC-HFW123',
        'name': 'Tiene NVR4108 en el nombre',
      },
      <String, dynamic>{'id': -1, 'sku': 'NVR4108-INVALID', 'name': 'Invalido'},
    ],
  };

  test('feature flag is disabled by default', () {
    expect(FastSkuDiscoveryService.enabled, isFalse);
    expect(FastSkuDiscoveryService.isSkuPrefix('NVR4108'), isTrue);
    expect(FastSkuDiscoveryService.isSkuPrefix('DS-K1T320EFWX'), isTrue);
    expect(FastSkuDiscoveryService.isSkuPrefix('NVR'), isFalse);
    expect(FastSkuDiscoveryService.isSkuPrefix('dahua 6mp'), isFalse);
    expect(FastSkuDiscoveryService.isSkuPrefix('hikvision'), isFalse);
    expect(FastSkuDiscoveryService.isSkuPrefix('camara ajax'), isFalse);
  });

  test('general catalog search remains disabled by default', () async {
    var calls = 0;
    final service = FastSkuDiscoveryService(
      fastSkuEnabled: false,
      dio: fixtureDio(full, inspect: (_) => calls++),
    );
    expect(FastSkuDiscoveryService.catalogEnabled, isFalse);
    expect(await service.suggestCatalog('HIKVISION Hiwatch'), isEmpty);
    expect(calls, 0);
  });

  test(
    'opt-in catalog search returns public candidates without commercial data',
    () async {
      var calls = 0;
      final service = FastSkuDiscoveryService(
        fastSkuEnabled: false,
        fastCatalogEnabled: true,
        dio: fixtureDio(
          {
            'scope': 'public_metadata_only',
            'requires_authenticated_hydration': true,
            'results': [
              {
                'id': 155090,
                'sku': 'HWT-B110-M',
                'name': 'Hiwatch cámara',
                'price': '999999',
              },
              {
                'id': 159939,
                'sku': 'P05E',
                'name': 'Century accesorio',
                'stock': 88,
              },
              {'id': 155090, 'sku': 'HWT-B110-M', 'name': 'Duplicado'},
            ],
          },
          inspect: (r) {
            calls++;
            expect(r.path, '/suggest');
            expect(r.queryParameters['q'], 'HIKVISION Hiwatch');
            expect(r.headers.containsKey('Authorization'), isFalse);
            expect(r.headers.containsKey('X-MundiCam-App-Token'), isFalse);
          },
        ),
      );
      final rows = await service.suggestCatalog('HIKVISION   Hiwatch');
      expect(rows.map((x) => x.id).toList(), [155090, 159939]);
      expect(rows.first.sku, 'HWT-B110-M');
      expect(calls, 1);
      expect((await service.suggestCatalog('hikvision hiwatch')).length, 2);
      expect(
        calls,
        1,
        reason: 'general query should use public metadata cache',
      );
    },
  );

  test(
    'general search refuses SKU shapes and missing public contract',
    () async {
      var calls = 0;
      final service = FastSkuDiscoveryService(
        fastSkuEnabled: false,
        fastCatalogEnabled: true,
        dio: fixtureDio({
          'scope': 'commercial_prices',
          'requires_authenticated_hydration': false,
          'results': [
            {'id': 155090, 'sku': 'HWT-B110-M', 'name': 'Unsafe'},
          ],
        }, inspect: (_) => calls++),
      );
      expect(await service.suggestCatalog('NVR4108'), isEmpty);
      expect(await service.suggestCatalog('da'), isEmpty);
      expect(await service.suggestCatalog('dahua'), isEmpty);
      expect(calls, 1);
    },
  );

  test('disabled version sends no network requests', () async {
    var touched = false;
    final service = FastSkuDiscoveryService(
      dio: fixtureDio(full, inspect: (_) => touched = true),
      fastSkuEnabled: false,
    );
    expect(await service.suggest('NVR4108'), isEmpty);
    expect(touched, isFalse);
  });

  test('returns ONLY matching public SKU suggestions, never a price', () async {
    final service = FastSkuDiscoveryService(
      dio: fixtureDio(
        full,
        inspect: (request) {
          expect(request.path, '/suggest');
          expect(request.queryParameters['q'], 'NVR4108');
          expect(request.queryParameters['limit'], 5);
          expect(request.headers.containsKey('Authorization'), isFalse);
          expect(request.headers.containsKey('X-MundiCam-App-Token'), isFalse);
        },
      ),
      fastSkuEnabled: true,
    );
    final results = await service.suggest('NVR4108');
    expect(results.length, 1);
    expect(results.single.id, 199025);
    expect(results.single.sku, 'NVR4108-P-4KS3');
    expect(results.single.name, 'Grabador NVR Dahua');
    // The type does not contain price/stock; they must be loaded after tap
    // from the authenticated WooCommerce endpoint.
  });

  test('repeated SKU suggestions reuse short-lived public cache', () async {
    var requests = 0;
    final service = FastSkuDiscoveryService(
      dio: fixtureDio(full, inspect: (_) => requests++),
      fastSkuEnabled: true,
    );
    expect((await service.suggest('NVR4108')).length, 1);
    expect((await service.suggest('nvr4108')).length, 1);
    expect(requests, 1);
    expect((await service.suggest('NVR4108', limit: 4)).length, 1);
    expect(requests, 2);
  });

  test('simultaneous identical SKU requests share one HTTP call', () async {
    var requests = 0;
    final service = FastSkuDiscoveryService(
      dio: fixtureDio(full, inspect: (_) => requests++),
      fastSkuEnabled: true,
    );
    final results = await Future.wait([
      service.suggest('NVR4108'),
      service.suggest('nvr4108'),
      service.suggest('NVR4108'),
    ]);
    expect(requests, 1);
    expect(results.every((items) => items.length == 1), isTrue);
  });

  test('rejects incomplete/wrong contract', () async {
    final service = FastSkuDiscoveryService(
      dio: fixtureDio({
        'scope': 'commercial_prices',
        'requires_authenticated_hydration': false,
        'results': full['results'],
      }),
      fastSkuEnabled: true,
    );
    expect(await service.suggest('NVR4108'), isEmpty);
  });

  test('fail-open fallback: errors produce no public product cards', () async {
    final service = FastSkuDiscoveryService(
      dio: fixtureDio(full, error: true),
      fastSkuEnabled: true,
    );
    expect(await service.suggest('NVR4108'), isEmpty);
  });

  test(
    'valid empty response is cached briefly without becoming a permanent miss',
    () async {
      var calls = 0;
      var now = DateTime.utc(2026, 11, 2, 12);
      final service = FastSkuDiscoveryService(
        dio: fixtureDio({
          'scope': 'public_metadata_only',
          'requires_authenticated_hydration': true,
          'results': <Map<String, dynamic>>[],
        }, inspect: (_) => calls++),
        fastSkuEnabled: true,
        clock: () => now,
      );
      expect(await service.suggest('UNKNOWN123'), isEmpty);
      expect(await service.suggest('unknown123'), isEmpty);
      expect(calls, 1);
      now = now.add(const Duration(seconds: 9));
      expect(await service.suggest('unknown123'), isEmpty);
      expect(calls, 2);
    },
  );

  test(
    'two failed requests pause VPS calls and retry after cooldown',
    () async {
      var calls = 0;
      var now = DateTime.utc(2026, 11, 2, 12);
      final service = FastSkuDiscoveryService(
        dio: fixtureDio(full, error: true, inspect: (_) => calls++),
        fastSkuEnabled: true,
        clock: () => now,
      );
      expect(await service.suggest('NVR4108'), isEmpty);
      expect(await service.suggest('NVR4109'), isEmpty);
      expect(calls, 2);
      expect(await service.suggest('NVR4110'), isEmpty);
      expect(calls, 2, reason: 'VPS outage must not slow down each keystroke');
      now = now.add(const Duration(seconds: 16));
      expect(await service.suggest('NVR4110'), isEmpty);
      expect(
        calls,
        3,
        reason: 'VPS must be retried after brief circuit cooldown',
      );
    },
  );

  test(
    'a valid response resets the failure counter and keeps public SKUs only',
    () async {
      var attempts = 0;
      final dio = Dio(BaseOptions(baseUrl: FastSkuDiscoveryService.endpoint));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            attempts++;
            if (attempts == 1 || attempts == 3) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.connectionTimeout,
                ),
              );
            } else {
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: full,
                ),
              );
            }
          },
        ),
      );
      final service = FastSkuDiscoveryService(dio: dio, fastSkuEnabled: true);
      expect(await service.suggest('NVR4108'), isEmpty);
      expect(await service.suggest('NVR4108', limit: 4), isNotEmpty);
      expect(await service.suggest('NVR4110'), isEmpty);
      expect(await service.suggest('NVR4108', limit: 7), isNotEmpty);
      expect(
        attempts,
        4,
        reason: 'Successful results should reset repeated-error protection',
      );
    },
  );

  test('no other brand or free-form search is delegated', () async {
    var called = false;
    final service = FastSkuDiscoveryService(
      dio: fixtureDio(full, inspect: (_) => called = true),
      fastSkuEnabled: true,
    );
    expect(await service.suggest('HIKVISION Hiwatch'), isEmpty);
    expect(await service.suggest('camara ajax'), isEmpty);
    expect(called, isFalse);
  });
}

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:mundicam/features/catalog/data/models/producto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mundicam/core/network/fast_sku_discovery_service.dart';
import 'package:mundicam/features/home/presentation/widgets/search_bar.dart';

Dio quickSuggestions() {
  final dio = Dio(BaseOptions(baseUrl: 'https://app.mundicam.com/app-fast/v1'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (request, handler) {
        if (request.path != '/suggest') {
          return handler.reject(DioException(requestOptions: request));
        }
        return handler.resolve(
          Response<Map<String, dynamic>>(
            requestOptions: request,
            statusCode: 200,
            data: <String, dynamic>{
              'scope': 'public_metadata_only',
              'requires_authenticated_hydration': true,
              'results': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 199025,
                  'sku': 'NVR4108-P-4KS3',
                  'name': 'Grabador NVR Dahua',
                },
              ],
            },
          ),
        );
      },
    ),
  );
  return dio;
}

Product commercialHiwatch() => Product(
  id: 155090,
  sku: 'HWT-B110-M',
  name: 'Cámara Hiwatch comercial autenticada',
  price: '89.90',
  regularPrice: '150.00',
  imageUrl: '',
  stockQuantity: 8,
  onSale: false,
  isInstock: true,
  shortDescription: '',
  description: '',
  attributes: const [],
);

Dio catalogSuggestions({bool fail = false}) {
  final dio = Dio(BaseOptions(baseUrl: FastSkuDiscoveryService.endpoint));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (request, handler) {
        if (fail) {
          handler.reject(
            DioException(
              requestOptions: request,
              type: DioExceptionType.connectionTimeout,
            ),
          );
          return;
        }
        handler.resolve(
          Response<Map<String, dynamic>>(
            requestOptions: request,
            statusCode: 200,
            data: {
              'scope': 'public_metadata_only',
              'requires_authenticated_hydration': true,
              'results': [
                {
                  'id': 155090,
                  'sku': 'HWT-B110-M',
                  'name': 'Cámara HIKVISION Hiwatch rápida',
                },
              ],
            },
          ),
        );
      },
    ),
  );
  return dio;
}

void main() {
  testWidgets(
    'catalog preview appears first, authenticated commercial results take precedence',
    (tester) async {
      final commercialResponse = Completer<List<Product>>();
      final service = FastSkuDiscoveryService(
        dio: catalogSuggestions(),
        fastSkuEnabled: false,
        fastCatalogEnabled: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchBarWidget(
              fastSkuService: service,
              suggestionLoader: (_) => commercialResponse.future,
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField).first, 'HIKVISION Hiwatch');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.textContaining('COINCIDENCIAS RÁPIDAS'), findsOneWidget);
      expect(find.text('Cámara HIKVISION Hiwatch rápida'), findsOneWidget);
      expect(find.textContaining('999999'), findsNothing);
      commercialResponse.complete([commercialHiwatch()]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(find.textContaining('PRODUCTOS RELACIONADOS'), findsOneWidget);
      expect(find.textContaining('COINCIDENCIAS RÁPIDAS'), findsNothing);
      expect(find.text('SKU: HWT-B110-M'), findsOneWidget);
    },
  );

  testWidgets('VPS outage keeps WooCommerce commercial suggestion working', (
    tester,
  ) async {
    final service = FastSkuDiscoveryService(
      dio: catalogSuggestions(fail: true),
      fastSkuEnabled: false,
      fastCatalogEnabled: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchBarWidget(
            fastSkuService: service,
            suggestionLoader: (_) async => [commercialHiwatch()],
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'HIKVISION Hiwatch');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 90));
    expect(find.textContaining('PRODUCTOS RELACIONADOS'), findsOneWidget);
    expect(find.textContaining('COINCIDENCIAS RÁPIDAS'), findsNothing);
  });

  testWidgets('SKU suggestion remains visible after network loading finishes', (
    tester,
  ) async {
    final service = FastSkuDiscoveryService(
      dio: quickSuggestions(),
      fastSkuEnabled: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SearchBarWidget(fastSkuService: service)),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'NVR4108');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Grabador NVR Dahua'), findsOneWidget);
    expect(find.textContaining('NVR4108-P-4KS3'), findsOneWidget);
    expect(find.textContaining('No se ha encontrado ese SKU'), findsNothing);
    expect(find.textContaining('REFERENCIAS RÁPIDAS'), findsOneWidget);
    // The public preview must never show a B2B price.
    expect(find.textContaining('999999'), findsNothing);
  });
}

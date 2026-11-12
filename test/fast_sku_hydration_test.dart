import 'package:flutter_test/flutter_test.dart';
import 'package:mundicam/core/network/fast_sku_discovery_service.dart';
import 'package:mundicam/core/network/fast_sku_hydration.dart';
import 'package:mundicam/features/catalog/data/models/producto.dart';

const preview = FastSkuSuggestion(
  id: 199025,
  sku: 'NVR4108-P-4KS3',
  name: 'Grabador público (sin precios)',
);

Product commercial({
  String price = '89.90',
  String sku = 'NVR4108-P-4KS3',
  int id = 199025,
  int stock = 8,
}) => Product(
  id: id,
  sku: sku,
  name: 'Ficha comercial autenticada',
  price: price,
  regularPrice: '150.00',
  imageUrl: '',
  stockQuantity: stock,
  onSale: true,
  isInstock: stock > 0,
  shortDescription: '',
  description: '',
  attributes: const [],
);

void main() {
  test(
    'tarifas B2B simuladas: devuelve la ficha autenticada del perfil A',
    () async {
      final roleA = commercial(price: '89.90', stock: 8);
      final selected = await hydrateVerifiedFastSku(
        preview: preview,
        loadAuthenticated: (id) async {
          expect(id, 199025);
          return roleA;
        },
      );
      expect(identical(selected, roleA), isTrue);
      expect(selected!.price, '89.90');
      expect(selected.stockQuantity, 8);
    },
  );

  test(
    'tarifas B2B simuladas: el mismo ID usa el precio del perfil B',
    () async {
      final roleB = commercial(price: '112.50', stock: 2);
      final selected = await hydrateVerifiedFastSku(
        preview: preview,
        loadAuthenticated: (_) async => roleB,
      );
      expect(identical(selected, roleB), isTrue);
      expect(selected!.price, '112.50');
      expect(selected.stockQuantity, 2);
    },
  );

  test('jamás abre una ficha si el servidor devuelve otro ID', () async {
    final result = await hydrateVerifiedFastSku(
      preview: preview,
      loadAuthenticated: (_) async => commercial(id: 230397),
    );
    expect(result, isNull);
  });

  test('jamás abre una ficha si el SKU ha cambiado en WooCommerce', () async {
    final result = await hydrateVerifiedFastSku(
      preview: preview,
      loadAuthenticated: (_) async => commercial(sku: 'NVR4108-UPDATED'),
    );
    expect(result, isNull);
  });

  test(
    'normaliza solo mayúsculas y espacios, no referencias diferentes',
    () async {
      final result = await hydrateVerifiedFastSku(
        preview: preview,
        loadAuthenticated: (_) async => commercial(sku: ' nvr4108-p-4ks3 '),
      );
      expect(result!.price, '89.90');
    },
  );

  test('sesión caducada o producto no disponible no genera ficha', () async {
    final result = await hydrateVerifiedFastSku(
      preview: preview,
      loadAuthenticated: (_) async => null,
    );
    expect(result, isNull);
  });

  test('errores de autenticación o red no se propagan al UI', () async {
    final result = await hydrateVerifiedFastSku(
      preview: preview,
      loadAuthenticated: (_) async => throw StateError('403'),
    );
    expect(result, isNull);
  });

  test('timeout de la API comercial devuelve null para fallback', () async {
    final result = await hydrateVerifiedFastSku(
      preview: preview,
      timeout: const Duration(milliseconds: 1),
      loadAuthenticated: (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return commercial();
      },
    );
    expect(result, isNull);
  });
}

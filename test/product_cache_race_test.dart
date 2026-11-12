import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mundicam/core/cache/product_cache_service.dart';

void main() {
  final cache = ProductCacheService();
  setUp(cache.clearAll);

  test('refresh posterior prevalece aunque termine primero', () async {
    final old = Completer<String>();
    final fresh = Completer<String>();
    final previous = cache.getOrLoadMemory<String>(
      'api_products|user:A|cat:1', loader: () => old.future,
    );
    final refreshed = cache.getOrLoadMemory<String>(
      'api_products|user:A|cat:1', forceRefresh: true,
      loader: () => fresh.future,
    );
    fresh.complete('tarifa nueva');
    expect(await refreshed, 'tarifa nueva');
    old.complete('tarifa antigua');
    expect(await previous, 'tarifa antigua');
    expect(cache.getMemory<String>('api_products|user:A|cat:1'), 'tarifa nueva');
  });

  test('invalidar no permite que la solicitud antigua repueble caché', () async {
    final slow = Completer<String>();
    final pending = cache.getOrLoadMemory<String>(
      'catalog_page|user:A|cat:5', loader: () => slow.future,
    );
    cache.clearMemoryPrefix('catalog_page|');
    slow.complete('respuesta de sesión anterior');
    await pending;
    expect(cache.getMemory<String>('catalog_page|user:A|cat:5'), isNull);
  });

  test('peticiones simultáneas sin refresh comparten una sola carga', () async {
    final slow = Completer<String>();
    var calls = 0;
    Future<String> load() {
      calls++;
      return slow.future;
    }
    final first = cache.getOrLoadMemory<String>('cat:7', loader: load);
    final second = cache.getOrLoadMemory<String>('cat:7', loader: load);
    expect(calls, 1);
    slow.complete('ok');
    expect(await first, 'ok');
    expect(await second, 'ok');
  });
}

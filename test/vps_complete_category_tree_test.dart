import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mundicam/core/network/vps_catalog_service.dart';
import 'package:mundicam/features/catalog/data/models/category_model.dart';

List<Map<String, dynamic>> sampleTree() {
  return List.generate(490, (i) {
    final id = i + 1;
    return {
      'id': id,
      'name': 'Categoria $id',
      'slug': 'categoria-$id',
      'parent': id <= 10 ? 0 : 1,
      'count': i,
      'menu_order': i,
      'description': '',
      'image_url': '',
    };
  });
}

Map<String, dynamic> sampleResponse(List<Map<String, dynamic>> rows) {
  return {
    'scope': 'public_metadata_only',
    'source': 'public_wordpress_complete_category_tree',
    'commercial_parity_confirmed': false,
    'requires_authenticated_products': true,
    'count': rows.length,
    'synced_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    'results': rows,
  };
}

class CategoryTreeMock {
  CategoryTreeMock(this.payload);
  Map<String, dynamic> payload;
  int requests = 0;
  String? lastPath;
  Map<String, dynamic>? lastQuery;

  Dio dio() {
    final instance = Dio(
      BaseOptions(baseUrl: 'https://app.mundicam.com/app-fast/v1'),
    );
    instance.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          requests++;
          lastPath = request.path;
          lastQuery = request.queryParameters;
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: request,
              statusCode: 200,
              data: payload,
            ),
          );
        },
      ),
    );
    return instance;
  }
}

void main() {
  test(
    'verified 490-category public tree preserves IDs, parents and order',
    () async {
      final mock = CategoryTreeMock(sampleResponse(sampleTree()));
      final api = VpsCatalogService(dio: mock.dio());
      final raw = await api.completeCategoryTree();
      expect(raw, isNotNull);
      expect(raw!.length, 490);
      expect(mock.lastPath, '/catalog/categories');
      expect(mock.lastQuery, {'source': 'wp-complete-qa'});
      expect(raw.first['parent'], 0);
      expect(raw[10]['parent'], 1);
      // Deducir hijos de los 490 términos reales, no consultar cada hoja.
      expect(raw.first['has_children'], isTrue);
      expect(raw.first['children_count'], 480);
      expect(raw[1]['has_children'], isFalse);
      expect(raw[1]['children_count'], 0);
      expect(raw[10]['has_children'], isFalse);
      expect(raw[10]['children_count'], 0);
      final parentModel = CategoryModel.fromJson(raw.first);
      expect(parentModel.hasChildren, isTrue);
      expect(parentModel.childrenCount, 480);
      final model = CategoryModel.fromJson(raw[10]);
      expect(model.id, 11);
      expect(model.parent, 1);
      expect(model.menuOrder, 10);
      // Cache public metadata only, no customer data.
      expect((await api.completeCategoryTree())!.length, 490);
      expect(mock.requests, 1);
    },
  );

  test('fail closed if public categories are missing', () async {
    final mock = CategoryTreeMock(sampleResponse(sampleTree()..removeLast()));
    expect(
      await VpsCatalogService(dio: mock.dio()).completeCategoryTree(),
      isNull,
    );
  });

  test('fail closed if public hierarchy has a cycle', () async {
    final tree = sampleTree();
    tree[0]['parent'] = 11; // 11 -> 1 -> 11.
    final mock = CategoryTreeMock(sampleResponse(tree));
    expect(
      await VpsCatalogService(dio: mock.dio()).completeCategoryTree(),
      isNull,
    );
  });

  test('fail closed on duplicate IDs', () async {
    final tree = sampleTree();
    tree[10]['id'] = 1;
    final mock = CategoryTreeMock(sampleResponse(tree));
    expect(
      await VpsCatalogService(dio: mock.dio()).completeCategoryTree(),
      isNull,
    );
  });

  test('fail closed on commercial claims or stale snapshots', () async {
    final data = sampleResponse(sampleTree());
    data['commercial_parity_confirmed'] = true;
    final mock = CategoryTreeMock(data);
    expect(
      await VpsCatalogService(dio: mock.dio()).completeCategoryTree(),
      isNull,
    );

    final old = sampleResponse(sampleTree());
    old['synced_at'] = 1;
    final stale = CategoryTreeMock(old);
    expect(
      await VpsCatalogService(dio: stale.dio()).completeCategoryTree(),
      isNull,
    );
  });

  test('concurrent reads share one public request', () async {
    final mock = CategoryTreeMock(sampleResponse(sampleTree()));
    final api = VpsCatalogService(dio: mock.dio());
    final result = await Future.wait([
      api.completeCategoryTree(),
      api.completeCategoryTree(),
      api.completeCategoryTree(),
    ]);
    expect(result.every((rows) => rows?.length == 490), isTrue);
    expect(mock.requests, 1);
  });
}

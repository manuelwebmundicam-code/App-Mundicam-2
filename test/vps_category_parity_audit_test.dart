import 'package:flutter_test/flutter_test.dart';
import 'package:mundicam/core/network/vps_category_parity_audit.dart';
import 'package:mundicam/features/catalog/data/models/category_model.dart';

const category44 = CategoryModel(
  id: 44,
  name: 'VIDEO CCTV HD',
  slug: 'video-cctv-hd',
  parent: 0,
  count: 654,
  menuOrder: 1,
  hasChildren: true,
);
const category49 = CategoryModel(
  id: 49,
  name: 'Cámaras Minidomo HD',
  slug: 'camaras-minidomo-hd',
  parent: 44,
  count: 78,
  menuOrder: 2,
  hasChildren: false,
);

List<Map<String, dynamic>> publicTree() => [
  {
    'id': 44,
    'name': 'VIDEO CCTV HD',
    'slug': 'video-cctv-hd',
    'parent': 0,
    'count': 654,
    'menu_order': 1,
    'has_children': true,
    'children_count': 1,
  },
  {
    'id': 49,
    'name': 'Cámaras Minidomo HD',
    'slug': 'camaras-minidomo-hd',
    'parent': 44,
    'count': 78,
    'menu_order': 2,
    'has_children': false,
    'children_count': 0,
  },
];

void main() {
  test('identidad y jerarquía coincidentes no autorizan productos B2B', () {
    final result = VpsCategoryParityAudit.compare(
      authenticated: [category44, category49],
      publicTree: publicTree(),
    );
    expect(result.available, isTrue);
    expect(result.structureMatches, isTrue);
    expect(result.b2bProductParityConfirmed, isFalse);
    expect(result.authenticatedCount, 2);
    expect(result.publicCount, 2);
    expect(result.summary, contains('b2b_products_confirmed=false'));
    expect(result.summary, isNot(contains('token')));
  });

  test('una categoría pública adicional jamás equivale a visibilidad B2B', () {
    final result = VpsCategoryParityAudit.compare(
      authenticated: [category44],
      publicTree: publicTree(),
    );
    expect(result.onlyInVps, 1);
    expect(result.structureMatches, isFalse);
    expect(result.b2bProductParityConfirmed, isFalse);
  });

  test('una categoría comercial ausente del índice bloquea equivalencia', () {
    final result = VpsCategoryParityAudit.compare(
      authenticated: [category44, category49],
      publicTree: publicTree()..removeLast(),
    );
    expect(result.missingInVps, 1);
    expect(result.structureMatches, isFalse);
  });

  test('se detectan diferencias de nombre, slug, padre, orden e hijos', () {
    final tree = publicTree();
    tree[1] = {
      ...tree[1],
      'name': 'Otra marca y categoría',
      'slug': 'otro-slug',
      'parent': 0,
      'menu_order': 999,
      'has_children': true,
    };
    final result = VpsCategoryParityAudit.compare(
      authenticated: [category44, category49],
      publicTree: tree,
    );
    expect(result.nameDifferences, 1);
    expect(result.slugDifferences, 1);
    expect(result.parentDifferences, 1);
    expect(result.orderDifferences, 1);
    expect(result.childrenHintDifferences, 1);
    expect(result.structureMatches, isFalse);
  });

  test('recuentos de usuario diferentes no se reutilizan como comerciales', () {
    const customerCategory = CategoryModel(
      id: 44,
      name: 'VIDEO CCTV HD',
      slug: 'video-cctv-hd',
      parent: 0,
      count: 19,
      menuOrder: 1,
      hasChildren: true,
    );
    final result = VpsCategoryParityAudit.compare(
      authenticated: [customerCategory, category49],
      publicTree: publicTree(),
    );
    expect(result.countDifferences, 1);
    expect(result.structureMatches, isTrue);
    expect(result.b2bProductParityConfirmed, isFalse);
  });

  test('árbol nulo o datos duplicados devuelve no disponible', () {
    expect(
      VpsCategoryParityAudit.compare(
        authenticated: [category44],
        publicTree: null,
      ).available,
      isFalse,
    );
    expect(
      VpsCategoryParityAudit.compare(
        authenticated: [category44, category44],
        publicTree: publicTree(),
      ).available,
      isFalse,
    );
    expect(
      VpsCategoryParityAudit.compare(
        authenticated: [category44],
        publicTree: [...publicTree(), publicTree().first],
      ).available,
      isFalse,
    );
  });

  test('sin categoría autenticada nunca se considera equivalencia', () {
    final result = VpsCategoryParityAudit.compare(
      authenticated: [],
      publicTree: publicTree(),
    );
    expect(result.available, isFalse);
    expect(result.structureMatches, isFalse);
  });
}

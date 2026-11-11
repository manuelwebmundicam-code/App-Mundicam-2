import 'package:mundicam/features/catalog/data/models/category_model.dart';

/// Auditoría de identidad de categorías. Compara metadatos públicos del VPS
/// con las categorías recibidas por la API MundiCam autenticada.
//// No evalúa productos/precios/stock ni certifica visibilidad comercial.
class VpsCategoryParityResult {
  const VpsCategoryParityResult({
    required this.available,
    required this.authenticatedCount,
    required this.publicCount,
    required this.missingInVps,
    required this.onlyInVps,
    required this.nameDifferences,
    required this.slugDifferences,
    required this.parentDifferences,
    required this.orderDifferences,
    required this.countDifferences,
    required this.childrenHintDifferences,
  });

  const VpsCategoryParityResult.unavailable()
    : available = false,
      authenticatedCount = 0,
      publicCount = 0,
      missingInVps = 0,
      onlyInVps = 0,
      nameDifferences = 0,
      slugDifferences = 0,
      parentDifferences = 0,
      orderDifferences = 0,
      countDifferences = 0,
      childrenHintDifferences = 0;

  final bool available;
  final int authenticatedCount;
  final int publicCount;
  final int missingInVps;
  final int onlyInVps;
  final int nameDifferences;
  final int slugDifferences;
  final int parentDifferences;
  final int orderDifferences;
  final int countDifferences;
  final int childrenHintDifferences;

  /// Solo identidad y estructura del árbol; NO productos comerciales.
  bool get structureMatches =>
      available &&
      missingInVps == 0 &&
      onlyInVps == 0 &&
      nameDifferences == 0 &&
      slugDifferences == 0 &&
      parentDifferences == 0 &&
      orderDifferences == 0 &&
      childrenHintDifferences == 0;

  /// Una taxonomía pública idéntica NO demuestra que los productos B2B lo sean.
  bool get b2bProductParityConfirmed => false;

  /// Formato de QA agregado: no incluye clientes, tokens, SKUs ni PVP.
  String get summary =>
      'available=$available '
      'wp=$authenticatedCount vps=$publicCount '
      'missing_in_vps=$missingInVps only_vps=$onlyInVps '
      'name=$nameDifferences slug=$slugDifferences '
      'parent=$parentDifferences order=$orderDifferences '
      'counts=$countDifferences children=$childrenHintDifferences '
      'structure_matches=$structureMatches b2b_products_confirmed=false';
}

class VpsCategoryParityAudit {
  const VpsCategoryParityAudit._();

  static VpsCategoryParityResult compare({
    required List<CategoryModel> authenticated,
    required List<Map<String, dynamic>>? publicTree,
  }) {
    // Una respuesta nula/incompleta no autoriza sustituir WordPress.
    if (publicTree == null || publicTree.isEmpty || authenticated.isEmpty) {
      return const VpsCategoryParityResult.unavailable();
    }

    final wpById = <int, CategoryModel>{};
    for (final category in authenticated) {
      if (category.id <= 0 || wpById.containsKey(category.id)) {
        return const VpsCategoryParityResult.unavailable();
      }
      wpById[category.id] = category;
    }

    final vpsById = <int, CategoryModel>{};
    for (final raw in publicTree) {
      final category = CategoryModel.fromJson(raw);
      if (category.id <= 0 || vpsById.containsKey(category.id)) {
        return const VpsCategoryParityResult.unavailable();
      }
      vpsById[category.id] = category;
    }

    var names = 0;
    var slugs = 0;
    var parents = 0;
    var orders = 0;
    var counts = 0;
    var hints = 0;
    for (final entry in wpById.entries) {
      final vps = vpsById[entry.key];
      if (vps == null) continue;
      final wp = entry.value;
      if (wp.name.trim().toLowerCase() != vps.name.trim().toLowerCase())
        names++;
      if (wp.slug.trim().toLowerCase() != vps.slug.trim().toLowerCase())
        slugs++;
      if (wp.parent != vps.parent) parents++;
      if (wp.menuOrder != vps.menuOrder) orders++;
      if (wp.count != vps.count) counts++;
      if (wp.hasChildren != null && wp.hasChildren != vps.hasChildren) hints++;
    }

    return VpsCategoryParityResult(
      available: true,
      authenticatedCount: wpById.length,
      publicCount: vpsById.length,
      missingInVps: wpById.keys.where((id) => !vpsById.containsKey(id)).length,
      onlyInVps: vpsById.keys.where((id) => !wpById.containsKey(id)).length,
      nameDifferences: names,
      slugDifferences: slugs,
      parentDifferences: parents,
      orderDifferences: orders,
      countDifferences: counts,
      childrenHintDifferences: hints,
    );
  }
}

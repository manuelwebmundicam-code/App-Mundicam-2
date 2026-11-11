import 'vps_catalog_service.dart';

/// Compara únicamente identidad pública de marcas. No usa cantidades de VPS
/// para ocultar marcas: el origen comercial sigue siendo la App API autenticada.
class VpsBrandAudit {
  VpsBrandAudit({VpsCatalogService? catalog})
    : _catalog = catalog ?? VpsCatalogService();

  final VpsCatalogService _catalog;

  Future<BrandAuditResult> compare(List<Map<String, dynamic>> appBrands) async {
    final vpsBrands = await _catalog.brands();
    if (vpsBrands.isEmpty) {
      return const BrandAuditResult(
        available: false,
        missingInVps: [],
        missingInApp: [],
        nameDifferences: [],
      );
    }
    final app = <int, String>{};
    for (final b in appBrands) {
      final id = b['id'];
      final name = b['name'];
      if (id is! int || id <= 0 || name is! String || name.trim().isEmpty) {
        continue;
      }
      app[id] = name.trim();
    }
    final vps = <int, String>{
      for (final b in vpsBrands) b['id'] as int: (b['name'] as String).trim(),
    };
    return BrandAuditResult(
      available: true,
      missingInVps: app.keys.where((id) => !vps.containsKey(id)).toList()
        ..sort(),
      missingInApp: vps.keys.where((id) => !app.containsKey(id)).toList()
        ..sort(),
      nameDifferences:
          app.keys
              .where(
                (id) =>
                    vps.containsKey(id) &&
                    app[id]!.toLowerCase() != vps[id]!.toLowerCase(),
              )
              .toList()
            ..sort(),
    );
  }
}

class BrandAuditResult {
  const BrandAuditResult({
    required this.available,
    required this.missingInVps,
    required this.missingInApp,
    required this.nameDifferences,
  });

  final bool available;
  final List<int> missingInVps;
  final List<int> missingInApp;
  final List<int> nameDifferences;

  bool get matches =>
      available &&
      missingInVps.isEmpty &&
      missingInApp.isEmpty &&
      nameDifferences.isEmpty;
}

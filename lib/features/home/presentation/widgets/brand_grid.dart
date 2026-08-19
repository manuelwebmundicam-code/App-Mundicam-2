import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/features/catalog/presentation/pages/categorias_por_marca_page.dart';
import 'package:mundicam/shared/theme/app_theme.dart';

final homeBrandsProvider =
FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final brands =
  await ApiService().getMarcas(hideEmpty: true, forceRefresh: true);

  final deduped = <Map<String, dynamic>>[];
  final seen = <String>{};

  for (final rawBrand in brands) {
    final brand = Map<String, dynamic>.from(rawBrand);
    final name = brand['name']?.toString() ?? '';
    final slug = brand['slug']?.toString() ?? '';

    final canonical = _canonicalBrandKey(
      name.isNotEmpty ? name : slug,
    );

    if (canonical.isEmpty || !seen.add(canonical)) {
      continue;
    }

    deduped.add(brand);
  }

  final indexed = List.generate(
    deduped.length,
        (index) => MapEntry(index, deduped[index]),
  );

  indexed.sort((a, b) {
    final priorityA =
    _brandPriority(a.value['name']?.toString() ?? '');
    final priorityB =
    _brandPriority(b.value['name']?.toString() ?? '');

    if (priorityA != priorityB) {
      return priorityA.compareTo(priorityB);
    }

    // Para marcas no destacadas conservamos el orden que entrega la API/web.
    return a.key.compareTo(b.key);
  });

  return indexed.map((entry) => entry.value).toList();
});

final homeBrandAssetsProvider =
FutureProvider<Map<String, String>>((ref) async {
  final manifest =
  await AssetManifest.loadFromAssetBundle(rootBundle);

  final assets = <String, String>{};

  for (final path in manifest.listAssets()) {
    final lowerPath = path.toLowerCase();

    if (!lowerPath.startsWith('assets/brands/')) {
      continue;
    }

    if (!(lowerPath.endsWith('.png') ||
        lowerPath.endsWith('.jpg') ||
        lowerPath.endsWith('.jpeg') ||
        lowerPath.endsWith('.webp'))) {
      continue;
    }

    final fileName = path.split('/').last;
    final dot = fileName.lastIndexOf('.');
    final baseName =
    dot > 0 ? fileName.substring(0, dot) : fileName;

    final canonical = _canonicalBrandKey(baseName);

    if (canonical.isEmpty) {
      continue;
    }

    assets.putIfAbsent(
      canonical,
          () => path,
    );
  }

  return assets;
});

class BrandGrid extends ConsumerWidget {
  final VoidCallback? onGoCart;
  final VoidCallback? onGoQuotes;

  const BrandGrid({
    super.key,
    this.onGoCart,
    this.onGoQuotes,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brandsAsync = ref.watch(homeBrandsProvider);

    final localBrandAssets =
    ref.watch(homeBrandAssetsProvider).maybeWhen(
      data: (assets) => assets,
      orElse: () => const <String, String>{},
    );

    return brandsAsync.when(
      loading: () => const SizedBox(
        height: 200,
        child: Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
          ),
        ),
      ),
      error: (error, stack) => SizedBox(
        height: 130,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Error al cargar marcas'),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () =>
                    ref.invalidate(homeBrandsProvider),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('REINTENTAR'),
              ),
            ],
          ),
        ),
      ),
      data: (brands) {
        final visibleBrands = brands.where((brand) {
          final id = _parseInt(brand['id']);
          final name =
              brand['name']?.toString().trim() ?? '';

          return id > 0 && name.isNotEmpty;
        }).toList();

        if (visibleBrands.isEmpty) {
          return const SizedBox(
            height: 120,
            child: Center(
              child: Text('No hay marcas disponibles'),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
          child: GridView.builder(
            shrinkWrap: true,
            physics:
            const NeverScrollableScrollPhysics(),
            itemCount: visibleBrands.length,
            gridDelegate:
            const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.25,
            ),
            itemBuilder: (context, index) {
              final brand = visibleBrands[index];

              final brandId =
              _parseInt(brand['id']);

              final brandName =
                  brand['name']?.toString().trim() ?? '';

              final brandTaxonomy =
                  brand['taxonomy']
                      ?.toString()
                      .trim() ??
                      '';

              return _BrandCard(
                brand: brand,
                localBrandAssets: localBrandAssets,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) =>
                          CategoriasPorMarcaPage(
                            brandId: brandId,
                            brandName: brandName,
                            brandTaxonomy:
                            brandTaxonomy,
                            onGoCart: onGoCart,
                            onGoQuotes: onGoQuotes,
                          ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _BrandCard extends StatelessWidget {
  final Map<String, dynamic> brand;
  final Map<String, String> localBrandAssets;
  final VoidCallback onTap;

  const _BrandCard({
    required this.brand,
    required this.localBrandAssets,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name =
        brand['name']?.toString().trim() ?? '';

    final imageUrl =
        brand['image']?.toString().trim() ?? '';

    final assetPath =
    _brandAssetPath(
      name,
      localBrandAssets,
    );

    // La propia marca es el botón completo.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius:
        BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color:
            const Color(0xFFF4F5F7),
            borderRadius:
            BorderRadius.circular(18),
          ),
          child: ClipRRect(
            borderRadius:
            BorderRadius.circular(18),
            child: SizedBox.expand(
              child: _BrandLogo(
                brandName: name,
                assetPath: assetPath,
                networkUrl: imageUrl,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandLogo extends StatelessWidget {
  final String brandName;
  final String? assetPath;
  final String networkUrl;

  const _BrandLogo({
    required this.brandName,
    required this.assetPath,
    required this.networkUrl,
  });

  @override
  Widget build(BuildContext context) {
    final ImageProvider? provider;

    if (assetPath != null &&
        assetPath!.isNotEmpty) {
      provider = AssetImage(
        assetPath!,
      );
    } else if (networkUrl.isNotEmpty &&
        (networkUrl.startsWith('http://') ||
            networkUrl.startsWith(
              'https://',
            ))) {
      provider = NetworkImage(
        networkUrl,
      );
    } else {
      provider = null;
    }

    if (provider == null) {
      return _fallback();
    }

    final logoFactor =
    _brandLogoFactor(brandName);

    return ClipRect(
      child: Center(
        child: FractionallySizedBox(
          widthFactor: logoFactor,
          heightFactor: logoFactor,
          child: Image(
            image: provider,
            fit: BoxFit.contain,
            alignment:
            Alignment.center,
            filterQuality:
            FilterQuality.high,
            errorBuilder:
                (
                context,
                error,
                stackTrace,
                ) =>
                _fallback(),
          ),
        ),
      ),
    );
  }

  Widget _fallback() {
    final words = brandName
        .trim()
        .split(RegExp(r'\s+'))
        .where(
          (word) =>
      word.isNotEmpty,
    )
        .toList();

    final initials =
    words.isEmpty
        ? 'M'
        : words
        .take(2)
        .map(
          (word) =>
          word[0]
              .toUpperCase(),
    )
        .join();

    return Center(
      child: Text(
        initials,
        style:
        const TextStyle(
          color:
          Color(0xFF98A2B3),
          fontSize: 24,
          fontWeight:
          FontWeight.w900,
          fontFamily: 'Oswald',
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// Ajuste VISUAL únicamente.
///
/// Base general = 0.65.
///
/// Más pequeños:
/// TVT, DJI y ZTE = 0.55.
///
/// Más grandes:
/// AISCAN / ALICSAN
/// PARADOX
/// SEAGA
/// JADEBIRD
/// VISIONAPROTECT
/// UNV
/// WESTERN DIGITAL
/// VISONIC
/// VAELIS / VAELSYS
/// VIDEOFIED
/// URFOG
/// UBIQUITI
/// UNIARC / UNIARCH
/// = 0.75.
///
/// Todos siguen usando BoxFit.contain:
/// no se deforman y permanecen centrados.
double _brandLogoFactor(String brandName) {
  final key = _brandKey(brandName);
  final canonicalKey = _canonicalBrandKey(brandName);

  bool isAny(String value, List<String> aliases) {
    return aliases.contains(value);
  }

  // ---------------------------------------------------------
  // MUY GRANDE
  // ---------------------------------------------------------
  // Seagate necesita un tratamiento independiente. Tiene que ir
  // antes que cualquier grupo general para que ningún return previo
  // anule su escala específica.
  if (isAny(key, const [
        'seagate',
      ]) ||
      isAny(canonicalKey, const [
        'seagate',
      ])) {
    return 1.05;
  }

  // ---------------------------------------------------------
  // GRANDES ESPECIALES
  // ---------------------------------------------------------
  if (isAny(key, const [
        'jadebird',
        'century',
        'dmtech',
      ]) ||
      isAny(canonicalKey, const [
        'jadebird',
        'century',
        'dmtech',
      ])) {
    return 0.80;
  }

  // ---------------------------------------------------------
  // MÁS PEQUEÑOS
  // ---------------------------------------------------------
  // Incluimos los nombres reales y las variantes que pueden llegar
  // desde WooCommerce o desde los nombres de los assets.
  if (isAny(key, const [
        'tvt',
        'dji',
        'zte',
        'imou',
        'evolve',
        'evolveextended',
        'evolveextender',
        'evolvextender',
        'hectronica',
      ]) ||
      isAny(canonicalKey, const [
        'tvt',
        'dji',
        'zte',
        'imou',
        'evolveextended',
        'evolveextender',
        'evolvextender',
        'hectronica',
      ])) {
    return 0.65;
  }

  // ---------------------------------------------------------
  // MÁS GRANDES
  // ---------------------------------------------------------
  // Se corrigen también alias/errores habituales para que no dependa
  // de que el nombre de WooCommerce coincida letra por letra.
  if (isAny(key, const [
        'aiscan',
        'alicsan',
        'paradox',
        'seaga',
        'visionaprotect',
        'unv',
        'uniview',
        'westerndigital',
        'visonic',
        'vaelis',
        'vaelsys',
        'videofied',
        'urfog',
        'urdog',
        'ubiquiti',
        'amc',
        'trikdis',
        'trikids',
        'hysoon',
        'bewave',
        'uniarc',
        'uniarch',
      ]) ||
      isAny(canonicalKey, const [
        'aiscan',
        'alicsan',
        'paradox',
        'seaga',
        'visionaprotect',
        'unv',
        'uniview',
        'westerndigital',
        'visonic',
        'vaelis',
        'vaelsys',
        'videofied',
        'urfog',
        'urdog',
        'ubiquiti',
        'amc',
        'trikdis',
        'trikids',
        'hysoon',
        'bewave',
        'uniarc',
        'uniarch',
      ])) {
    return 0.75;
  }

  // ---------------------------------------------------------
  // RESTO DE MARCAS
  // ---------------------------------------------------------
  return 0.65;
}

int _parseInt(dynamic value) {
  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(
    value?.toString() ?? '',
  ) ??
      0;
}

String _brandKey(String value) {
  return value
      .toLowerCase()
      .trim()
      .replaceAll('á', 'a')
      .replaceAll('à', 'a')
      .replaceAll('ä', 'a')
      .replaceAll('â', 'a')
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ë', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ì', 'i')
      .replaceAll('ï', 'i')
      .replaceAll('î', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ò', 'o')
      .replaceAll('ö', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ù', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('û', 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(
    RegExp(r'[^a-z0-9]+'),
    '',
  );
}

String _canonicalBrandKey(
    String value,
    ) {
  final key =
  _brandKey(value);

  if (key == 'hickvision') {
    return 'hikvision';
  }

  if (key == 'secury360') {
    return 'security360';
  }

  if (key == 'zkteko') {
    return 'zkteco';
  }

  if (key == 'mci' ||
      key == 'mcipro') {
    return 'mcipro';
  }

  if (key ==
      'evolveextended' ||
      key == 'evolve') {
    return 'evolveextended';
  }

  if (key == 'assaabloy' ||
      key ==
          'tesaassaabloy') {
    return 'tesaassaabloy';
  }

  return key;
}

int _brandPriority(
    String name,
    ) {
  final key =
  _canonicalBrandKey(name);

  if (key.isEmpty) {
    return 1000;
  }

  // Orden comercial solicitado para Inicio.
  // Las demás marcas mantienen el orden de la API/web.
  const priorityGroups =
  <List<String>>[
    ['ajax'],
    ['dahua'],
    [
      'hikvision',
      'hickvision'
    ],
    [
      'security360',
      'secury360'
    ],
    ['tplink'],
    [
      'zkteco',
      'zkteko'
    ],
    ['anviz'],
    ['teletek'],
    ['paradox'],
    ['powersafe'],
    [
      'evolveextended',
      'evolve'
    ],
    [
      'mcipro',
      'mci'
    ],
  ];

  for (var index = 0;
  index <
      priorityGroups.length;
  index++) {
    final aliases =
    priorityGroups[index];

    if (aliases.any(
          (alias) => key == alias,
    )) {
      return index;
    }
  }

  return 1000;
}

String? _brandAssetPath(
    String name,
    Map<String, String>
    discoveredAssets,
    ) {
  final canonical =
  _canonicalBrandKey(name);

  final discovered =
  discoveredAssets[
  canonical];

  if (discovered != null &&
      discovered.isNotEmpty) {
    return discovered;
  }

  final key =
  _brandKey(name);

  const exact =
  <String, String>{
    'ajax':
    'assets/brands/AJAX.png',
    'anviz':
    'assets/brands/ANVIZ.png',
    'assaabloy':
    'assets/brands/ASSAABLOY.png',
    'tesaassaabloy':
    'assets/brands/ASSAABLOY.png',
    'dahua':
    'assets/brands/DAHUA.png',
    'dji':
    'assets/brands/DJI.png',
    'evolve':
    'assets/brands/EVOLVE.png',
    'evolveextended':
    'assets/brands/EVOLVE.png',
    'ezviz':
    'assets/brands/EZVIZ.png',
    'hikvision':
    'assets/brands/HIKVISION.png',
    'hickvision':
    'assets/brands/HIKVISION.png',
    'mci':
    'assets/brands/MCI.png',
    'mcipro':
    'assets/brands/MCI.png',
    'mobotix':
    'assets/brands/MOBOTIX.png',
    'optex':
    'assets/brands/OPTEX.png',
    'paradox':
    'assets/brands/PARADOX.png',
    'powersafe':
    'assets/brands/POWER-SAFE.png',
    'satel':
    'assets/brands/SATEL.png',
    'secury360':
    'assets/brands/SECURITY360.png',
    'security360':
    'assets/brands/SECURITY360.png',
    'tplink':
    'assets/brands/TPLINK.png',
    'trikdis':
    'assets/brands/TRIKDIS.png',
    'yale':
    'assets/brands/Yale.png',
    'zkteco':
    'assets/brands/ZKTECO.png',
    'zkteko':
    'assets/brands/ZKTECO.png',
  };

  if (exact.containsKey(key)) {
    return exact[key];
  }

  for (final entry
  in exact.entries) {
    if (key.contains(
      entry.key,
    ) ||
        entry.key.contains(
          key,
        )) {
      return entry.value;
    }
  }

  return null;
}
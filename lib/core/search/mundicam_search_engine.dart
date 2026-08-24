import 'package:mundicam/features/catalog/data/models/producto.dart';

/// Motor de búsqueda local/profesional de MundiCam.
///
/// No sustituye al backend: lo complementa corrigiendo errores habituales
/// de instalador, ampliando términos técnicos y reordenando los resultados
/// para que Home, Catálogo y Chatbox se comporten igual.
class MundicamSearchEngine {
  static const Set<String> _stopWords = {
    'de', 'del', 'la', 'las', 'el', 'los', 'para', 'por', 'con', 'sin',
    'en', 'un', 'una', 'unos', 'unas', 'y', 'o', 'a', 'al', 'the', 'of',
  };

  static const Map<String, List<String>> _synonyms = {
    'camara': [
      'camara',
      'camaras',
      'camera',
      'cameras',
      'cctv',
      'video',
      'ip',
      'hd',
      'hdcvi',
      'turret',
      'bullet',
      'tubular',
      'domo',
      'dome',
      'ptz',
      'motioncam',
      'fotodetector',
    ],
    'grabador': [
      'grabador',
      'grabadores',
      'nvr',
      'xvr',
      'dvr',
      'recorder',
      'videograbador',
      'canales',
      'h265',
      'h 265',
      'poe',
    ],
    'alarma': [
      'alarma',
      'alarmas',
      'intrusion',
      'hub',
      'detector',
      'sirena',
      'teclado',
      'contacto',
      'jeweller',
      'fibra',
      'ajax',
      'ksenia',
    ],
    'incendio': [
      'incendio',
      'fuego',
      'detector humo',
      'detector termico',
      'sirena incendio',
      'central incendio',
      'en54',
      'teletek',
    ],
    'acceso': [
      'acceso',
      'control acceso',
      'lector',
      'tarjeta',
      'biometrico',
      'cerradura',
      'terminal',
      'zkteco',
    ],
    'networking': [
      'networking',
      'red',
      'switch',
      'router',
      'poe',
      'wifi',
      'omada',
      'vigi',
      'tplink',
      'tp link',
      'tp-link',
    ],
    'accesorio': [
      'accesorio',
      'accesorios',
      'cable',
      'latiguillo',
      'conector',
      'rj45',
      'utp',
      'ftp',
      'cat5',
      'cat6',
      'cat7',
      'bnc',
      'coaxial',
      'pila',
      'bateria',
      'fuente',
      'alimentador',
    ],
    'software': [
      'software',
      'licencia',
      'licencias',
      'hikcentral',
      'dss',
      'dmss',
      'ivss',
    ],
  };

  static const List<String> knownBrands = [
    'ajax',
    'dahua',
    'hikvision',
    'hiwatch',
    'hiluxtel',
    'ksenia',
    'teletek',
    'tp-link',
    'tplink',
    'vigi',
    'omada',
    'mobotix',
    'secury360',
    'evolve',
    'wisim',
    'softguard',
    'mci',
    'powersafe',
    'power safe',
    'zkteco',
    'ubiquiti',
    'ruijie',
  ];

  static String cleanQuery(String value) {
    final fixed = _fixCommonTypos(value.trim().replaceAll(RegExp(r'\s+'), ' '));
    return fixed.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static bool looksLikeSku(String value) {
    final clean = value.trim();
    if (clean.length < 4) return false;
    return RegExp(r'[A-Za-z]').hasMatch(clean) &&
        (RegExp(r'\d').hasMatch(clean) || clean.contains('-') || clean.contains('_'));
  }

  /// Términos que se mandan al backend. Se limita el número para no matar
  /// el servidor ni hacer esperar al usuario.
  static List<String> buildBackendQueries(
    String query, {
    int maxTerms = 5,
  }) {
    final clean = cleanQuery(query);
    if (clean.length < 2) return const <String>[];
    if (looksLikeSku(clean)) return <String>[clean];

    final normalized = normalize(clean);
    final tokens = meaningfulTerms(clean);
    final brands = detectedBrands(clean);
    final mp = detectedMegapixels(clean);
    final terms = <String>[];

    void add(String value) {
      final text = cleanQuery(value);
      if (text.length < 2) return;
      final key = normalize(text);
      if (terms.any((item) => normalize(item) == key)) return;
      terms.add(text);
    }

    add(clean);

    if (tokens.contains('camara') || _containsAny(normalized, _synonyms['camara']!)) {
      if (brands.isNotEmpty && mp != null) {
        add('camara ${brands.first} ${mp}MP');
        add('${brands.first} camara ${mp}MP');
      } else if (brands.isNotEmpty) {
        add('camara ${brands.first}');
        add('${brands.first} camara');
      } else if (mp != null) {
        add('camara ${mp}MP');
        add('${mp}MP camara');
        add('camara ip ${mp}MP');
      } else {
        add('camara IP');
        add('camara CCTV');
      }
    }

    if (brands.isNotEmpty) {
      add(brands.first);
      if (brands.length > 1) add(brands[1]);
    }

    if (_containsAny(normalized, _synonyms['grabador']!)) {
      add('NVR');
      add('grabador');
      if (brands.isNotEmpty) add('NVR ${brands.first}');
    }

    if (_containsAny(normalized, _synonyms['networking']!)) {
      add('switch PoE');
      add('router wifi');
      if (brands.isNotEmpty) add('${brands.first} networking');
    }

    if (_containsAny(normalized, _synonyms['accesorio']!)) {
      if (normalized.contains('rj45') || normalized.contains('rj 45')) {
        add('conector RJ45');
        add('latiguillo RJ45');
      }
      if (normalized.contains('cat6')) add('cable Cat6');
      if (normalized.contains('cat5')) add('cable Cat5');
      if (normalized.contains('fuente') || normalized.contains('aliment')) {
        add('fuente alimentacion');
      }
    }

    if (terms.length < maxTerms) {
      for (final token in tokens) {
        if (terms.length >= maxTerms) break;
        if (token.length >= 3 && !knownBrands.map(normalize).contains(token)) {
          add(token);
        }
      }
    }

    return terms.take(maxTerms).toList();
  }

  static List<Product> sortAndFilter(
    Iterable<Product> products,
    String query, {
    int? limit,
    bool strict = true,
  }) {
    final clean = cleanQuery(query);
    if (clean.isEmpty) return products.where((p) => p.id > 0).toList();
    final terms = meaningfulTerms(clean);
    final scored = products
        .where((product) => product.id > 0)
        .map((product) => _ScoredProduct(
              product: product,
              score: scoreProduct(product, clean, terms: terms),
            ))
        .where((item) => !strict || item.score >= minimumScoreFor(clean, terms))
        .toList();

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final stock = (b.product.hasStock ? 1 : 0).compareTo(a.product.hasStock ? 1 : 0);
      if (stock != 0) return stock;
      return a.product.name.compareTo(b.product.name);
    });

    final sorted = scored.map((item) => item.product).toList();
    return limit == null ? sorted : sorted.take(limit).toList();
  }

  static int minimumScoreFor(String query, List<String> terms) {
    if (looksLikeSku(query)) return 1000;
    if (terms.length >= 3) return 70;
    if (terms.length == 2) return 48;
    return 22;
  }

  static int scoreProduct(
    Product product,
    String query, {
    List<String>? terms,
  }) {
    final clean = cleanQuery(query);
    final normalizedQuery = normalize(clean);
    final queryTerms = terms ?? meaningfulTerms(clean);
    final sku = normalize(product.sku);
    final name = normalize(product.name);
    final brand = normalize(product.brandName ?? '');
    final description = normalize('${product.shortDescription} ${product.description}');
    final categories = normalize('${product.categoryNames.join(' ')} ${product.categorySlugs.join(' ')}');
    final attributes = normalize(product.attributes
        .map((attribute) => '${attribute.name} ${attribute.options.join(' ')}')
        .join(' '));
    final strongText = '$sku $name $brand $categories $attributes';
    final fullText = '$strongText $description';

    if (looksLikeSku(clean)) {
      final compactSku = compact(product.sku);
      final compactQuery = compact(clean);
      if (compactSku.isEmpty) return 0;
      if (compactSku == compactQuery) return 5000;
      if (compactSku.startsWith(compactQuery)) return 3800;
      if (compactSku.contains(compactQuery)) return 2600;
      return 0;
    }

    final brands = detectedBrands(clean);
    if (brands.isNotEmpty) {
      final hasBrand = brands.any((item) => strongText.contains(normalize(item)));
      if (!hasBrand) return 0;
    }

    final mp = detectedMegapixels(clean);
    if (mp != null && _isCameraQuery(clean)) {
      final mpVariants = <String>{
        '${mp}mp',
        '$mp mp',
        '$mp mpx',
        '${mp}megapixel',
        '${mp}megapixeles',
        '${mp}m',
      }.map(normalize).toSet();
      final hasResolution = mpVariants.any(fullText.contains) ||
          fullText.contains((mp * 100).toString()) ||
          fullText.contains('$mp mpx');
      if (!hasResolution) return 0;
    }

    if (_isCameraQuery(clean) && !_productLooksCamera(fullText)) {
      return 0;
    }

    var score = 0;
    if (sku.isNotEmpty && sku == normalizedQuery) score += 3000;
    if (sku.isNotEmpty && sku.startsWith(normalizedQuery)) score += 2200;
    if (sku.isNotEmpty && sku.contains(normalizedQuery)) score += 1500;
    if (name == normalizedQuery) score += 1000;
    if (name.startsWith(normalizedQuery)) score += 780;
    if (name.contains(normalizedQuery)) score += 620;
    if (brand.isNotEmpty && brand == normalizedQuery) score += 560;
    if (brand.isNotEmpty && brand.contains(normalizedQuery)) score += 430;

    var matchedTerms = 0;
    for (final term in queryTerms) {
      if (term.length < 2) continue;
      final variants = variantsForTerm(term);
      final strongMatch = variants.any(strongText.contains);
      final fullMatch = strongMatch || variants.any(fullText.contains);
      if (!fullMatch) continue;
      matchedTerms++;
      if (sku.contains(term)) score += 260;
      if (name.contains(term)) score += 210;
      if (brand.contains(term)) score += 190;
      if (categories.contains(term)) score += 95;
      if (attributes.contains(term)) score += 85;
      if (description.contains(term)) score += 45;
    }

    if (queryTerms.length >= 2 && matchedTerms < queryTerms.length) {
      final hasBrand = brands.isNotEmpty;
      final missingAllowed = hasBrand && matchedTerms >= queryTerms.length - 1;
      if (!missingAllowed) score -= 120;
    }

    if (_isCameraQuery(clean) && _productLooksCamera(fullText)) score += 180;
    if (_containsAny(normalizedQuery, _synonyms['grabador']!) && _productLooksRecorder(fullText)) score += 180;
    if (_containsAny(normalizedQuery, _synonyms['networking']!) && _productLooksNetworking(fullText)) score += 160;
    if (_containsAny(normalizedQuery, _synonyms['alarma']!) && _productLooksAlarm(fullText)) score += 160;
    if (_containsAny(normalizedQuery, _synonyms['accesorio']!) && _productLooksAccessory(fullText)) score += 120;

    if (product.imageUrl.trim().isNotEmpty) score += 8;
    if (product.hasStock || product.isInstock) score += 6;
    if (product.hasValidPrice) score += 4;

    return score;
  }

  static List<String> meaningfulTerms(String query) {
    final normalized = normalize(cleanQuery(query));
    final rawTerms = normalized
        .split(' ')
        .map((term) => _singularize(term.trim()))
        .where((term) => term.length >= 2 && !_stopWords.contains(term));
    final terms = <String>{};

    for (final term in rawTerms) {
      terms.add(term);
    }

    final mp = detectedMegapixels(query);
    if (mp != null) {
      terms
        ..remove('mp')
        ..remove('mpx')
        ..add('${mp}mp');
    }

    _synonyms.forEach((key, values) {
      final normalizedKey = normalize(key);
      if (normalized.contains(normalizedKey) ||
          values.any((value) => normalized.contains(normalize(value)))) {
        terms.add(normalizedKey);
      }
    });

    for (final brand in detectedBrands(query)) {
      terms.add(normalize(brand));
    }

    return terms.toList();
  }

  static List<String> detectedBrands(String query) {
    final normalized = normalize(query);
    final result = <String>[];
    for (final brand in knownBrands) {
      final normalizedBrand = normalize(brand);
      if (normalizedBrand.isEmpty) continue;
      if (normalized == normalizedBrand ||
          normalized.contains(' $normalizedBrand ') ||
          normalized.startsWith('$normalizedBrand ') ||
          normalized.endsWith(' $normalizedBrand') ||
          normalized.contains(normalizedBrand.replaceAll(' ', ''))) {
        if (!result.any((item) => normalize(item) == normalizedBrand)) {
          result.add(brandLabel(brand));
        }
      }
    }
    return result;
  }

  static int? detectedMegapixels(String query) {
    final normalized = normalize(_fixCommonTypos(query));
    final compacted = compact(normalized);
    final direct = RegExp(r'(^|\D)([1-9][0-9]?)(\s*)(mp|mpx|megapixel|megapixeles)(\D|$)')
        .firstMatch(normalized);
    if (direct != null) return int.tryParse(direct.group(2) ?? '');

    final compactMatch = RegExp(r'(^|\D)([1-9][0-9]?)(mp|mpx)(\D|$)').firstMatch(compacted);
    if (compactMatch != null) return int.tryParse(compactMatch.group(2) ?? '');
    return null;
  }

  static List<String> suggestionsFor(String query) {
    final normalized = normalize(query);
    final brands = detectedBrands(query);
    final brand = brands.isNotEmpty ? brands.first : '';
    final mp = detectedMegapixels(query);

    if (_isCameraQuery(query)) {
      if (brand.isNotEmpty && mp != null) {
        return ['cámara $brand ${mp}MP', '$brand ${mp}MP', 'cámara IP $brand', 'cámara ${mp}MP'];
      }
      if (brand.isNotEmpty) {
        return ['cámara $brand', '$brand cámara IP', '$brand domo', '$brand bullet'];
      }
      if (mp != null) {
        return ['cámara ${mp}MP', 'cámara IP ${mp}MP', 'domo ${mp}MP', 'bullet ${mp}MP'];
      }
      return ['cámara IP', 'cámara domo', 'cámara bullet', 'cámara PoE'];
    }

    if (_containsAny(normalized, _synonyms['grabador']!)) {
      return ['NVR Dahua', 'NVR Hikvision', 'grabador IP', 'XVR'];
    }

    if (_containsAny(normalized, _synonyms['alarma']!)) {
      return ['Ajax Hub', 'detector Ajax', 'sirena Ajax', 'Ksenia lares'];
    }

    if (_containsAny(normalized, _synonyms['networking']!)) {
      return ['switch PoE', 'router 4G', 'Omada', 'VIGI'];
    }

    return ['Ajax', 'Dahua', 'Hikvision', 'cámara IP', 'NVR', 'switch PoE'];
  }

  static String normalize(String value) {
    var text = value.toLowerCase().trim();
    const replacements = {
      'á': 'a',
      'à': 'a',
      'ä': 'a',
      'â': 'a',
      'é': 'e',
      'è': 'e',
      'ë': 'e',
      'ê': 'e',
      'í': 'i',
      'ì': 'i',
      'ï': 'i',
      'î': 'i',
      'ó': 'o',
      'ò': 'o',
      'ö': 'o',
      'ô': 'o',
      'ú': 'u',
      'ù': 'u',
      'ü': 'u',
      'û': 'u',
      'ñ': 'n',
      '/': ' ',
      '-': ' ',
      '_': ' ',
      '.': ' ',
      ',': ' ',
      ';': ' ',
      ':': ' ',
      '(': ' ',
      ')': ' ',
      '[': ' ',
      ']': ' ',
      '+': ' ',
    };
    replacements.forEach((from, to) => text = text.replaceAll(from, to));
    text = text.replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ');
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String compact(String value) => normalize(value).replaceAll(' ', '');

  static Set<String> variantsForTerm(String term) {
    final normalized = normalize(term);
    final variants = <String>{normalized};
    if (normalized == 'camara') {
      variants.addAll(['camara', 'camaras', 'camera', 'cctv', 'motioncam', 'fotodetector']);
    }
    if (normalized == '5mp') variants.addAll(['5mp', '5 mp', '5mpx', '5 mpx', '5 megapixel', '5 megapixeles']);
    if (normalized == '8mp') variants.addAll(['8mp', '8 mp', '8mpx', '8 mpx', '8 megapixel', '8 megapixeles']);
    if (normalized == '4mp') variants.addAll(['4mp', '4 mp', '4mpx', '4 mpx', '4 megapixel', '4 megapixeles']);
    if (normalized == 'rj45') variants.addAll(['rj45', 'rj 45']);
    if (normalized == 'tplink') variants.addAll(['tplink', 'tp link', 'tp-link']);
    if (normalized == 'poe') variants.addAll(['poe', 'poe+', 'poe plus']);
    return variants.map(normalize).where((item) => item.isNotEmpty).toSet();
  }

  static String brandLabel(String brand) {
    switch (normalize(brand)) {
      case 'tplink':
      case 'tp link':
        return 'TP-Link';
      case 'vigi':
        return 'VIGI';
      case 'omada':
        return 'Omada';
      case 'ajax':
        return 'Ajax';
      case 'dahua':
        return 'Dahua';
      case 'hikvision':
        return 'Hikvision';
      case 'hiwatch':
        return 'HiWatch';
      case 'ksenia':
        return 'Ksenia';
      case 'teletek':
        return 'Teletek';
      case 'mobotix':
        return 'Mobotix';
      case 'secury360':
        return 'Secury360';
      case 'evolve':
        return 'Evolve Xtender';
      case 'wisim':
        return 'WiSIM';
      case 'zkteco':
        return 'ZKTeco';
      default:
        return brand.trim().isEmpty ? brand : brand.trim();
    }
  }

  static String _fixCommonTypos(String value) {
    var text = value;
    final replacements = <RegExp, String>{
      RegExp(r'\bcamra\b', caseSensitive: false): 'camara',
      RegExp(r'\bcamara\b', caseSensitive: false): 'camara',
      RegExp(r'\bcamaras\b', caseSensitive: false): 'camaras',
      RegExp(r'\bcamera\b', caseSensitive: false): 'camara',
      RegExp(r'\bcam\s+', caseSensitive: false): 'camara ',
      RegExp(r'\bmpx\b', caseSensitive: false): 'MP',
      RegExp(r'\bmegapixels\b', caseSensitive: false): 'MP',
      RegExp(r'\bturet\b', caseSensitive: false): 'turret',
      RegExp(r'\btubular\b', caseSensitive: false): 'bullet',
      RegExp(r'\btp link\b', caseSensitive: false): 'TP-Link',
    };
    replacements.forEach((from, to) => text = text.replaceAll(from, to));
    text = text.replaceAllMapped(
      RegExp(r'\b([1-9][0-9]?)\s*(mp|mpx)\b', caseSensitive: false),
      (match) => '${match.group(1)}MP',
    );
    return text;
  }

  static String _singularize(String value) {
    if (value.endsWith('es') && value.length > 4) return value.substring(0, value.length - 2);
    if (value.endsWith('s') && value.length > 3 && !value.endsWith('ss')) {
      return value.substring(0, value.length - 1);
    }
    return value;
  }

  static bool _isCameraQuery(String query) {
    final normalized = normalize(query);
    return _containsAny(normalized, _synonyms['camara']!) ||
        RegExp(r'(^|\s)[1-9][0-9]?\s*mp(\s|$)').hasMatch(normalized);
  }

  static bool _productLooksCamera(String text) {
    return _containsAny(text, const [
      'camara',
      'camera',
      'cctv',
      'ip hd',
      'hdcvi',
      'domo',
      'dome',
      'turret',
      'bullet',
      'tubular',
      'ptz',
      'motioncam',
      'fotodetector',
      'imagen',
      'videoverificacion',
    ]);
  }

  static bool _productLooksRecorder(String text) {
    return _containsAny(text, const ['nvr', 'xvr', 'dvr', 'grabador', 'recorder', 'videograbador']);
  }

  static bool _productLooksNetworking(String text) {
    return _containsAny(text, const ['switch', 'router', 'wifi', 'poe', 'omada', 'vigi', 'networking', 'red']);
  }

  static bool _productLooksAlarm(String text) {
    return _containsAny(text, const ['alarma', 'intrusion', 'hub', 'detector', 'sirena', 'jeweller', 'ajax', 'ksenia']);
  }

  static bool _productLooksAccessory(String text) {
    return _containsAny(text, const [
      'cable',
      'latiguillo',
      'conector',
      'rj45',
      'utp',
      'ftp',
      'cat5',
      'cat6',
      'cat7',
      'bnc',
      'coaxial',
      'pila',
      'bateria',
      'fuente',
      'alimentador',
      'transformador',
    ]);
  }

  static bool _containsAny(String source, List<String> values) {
    final normalizedSource = normalize(source);
    return values.any((value) => normalizedSource.contains(normalize(value)));
  }
}

class _ScoredProduct {
  final Product product;
  final int score;

  const _ScoredProduct({required this.product, required this.score});
}

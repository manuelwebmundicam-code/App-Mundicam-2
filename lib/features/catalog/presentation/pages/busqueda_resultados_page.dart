// busqueda_resultados_page.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:mundicam/core/firebase/firebase_service.dart';
import 'package:mundicam/features/cart/presentation/providers/cart_provider.dart';
import 'package:mundicam/features/catalog/data/models/producto.dart';
import 'package:mundicam/features/catalog/presentation/pages/producto_detalles_page.dart';
import 'package:mundicam/features/catalog/presentation/providers/products_provider.dart';
import 'package:mundicam/features/quotes/data/models/local_quote_model.dart';
import 'package:mundicam/features/quotes/presentation/providers/local_quote_provider.dart';
import 'package:mundicam/features/quotes/presentation/widgets/quote_selection_dialog.dart';
import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/shared/widgets/professional_page_app_bar.dart';

class BusquedaResultadosPage extends ConsumerWidget {
  final String query;
  final VoidCallback? onGoCart;
  final VoidCallback? onGoQuotes;

  const BusquedaResultadosPage({
    super.key,
    required this.query,
    this.onGoCart,
    this.onGoQuotes,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String cleanedQuery = _SearchEngine.cleanQuery(query);
    final searchAsync = ref.watch(searchProductsProvider(cleanedQuery));
    final FirebaseService firebase = FirebaseService();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: ProfessionalPageAppBar(
        title: cleanedQuery.isEmpty ? 'RESULTADOS' : 'RESULTADOS: $cleanedQuery',
        subtitle: '',
        icon: Icons.search_rounded,
        onBack: () => Navigator.of(context).pop(),
      ),
      body: searchAsync.when(
        loading: () => const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppColors.primary),
              SizedBox(height: 16),
              Text(
                'Buscando productos...',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
        error: (error, stack) => _buildErrorState(context, error),
        data: (productosOriginales) {
          final List<Product> productos = _SearchEngine.sortByRelevance(
            productosOriginales,
            cleanedQuery,
          );

          if (productos.isEmpty) {
            return _buildEmptyState(context, cleanedQuery);
          }

          final detectedTerms =
          _SearchEngine.detectedReadableTerms(cleanedQuery);

          return Column(
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE7E7E7)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${productos.length} producto${productos.length != 1 ? 's' : ''} encontrado${productos.length != 1 ? 's' : ''}',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (detectedTerms.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: detectedTerms.map((term) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color:
                                AppColors.primary.withValues(alpha: 0.18),
                              ),
                            ),
                            child: Text(
                              term,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                  itemCount: productos.length,
                  itemBuilder: (context, index) {
                    return ProductTileBusqueda(
                      p: productos[index],
                      firebase: firebase,
                      onGoCart: onGoCart,
                      onGoQuotes: onGoQuotes,
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: Color(0xFFF8EAEA),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                size: 48,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Error al buscar productos',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontFamily: 'Oswald',
                fontWeight: FontWeight.w900,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Volver'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, String cleanedQuery) {
    final suggestions = _SearchEngine.suggestionsFor(cleanedQuery);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: const BoxDecoration(
                color: Color(0xFFF8EAEA),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.search_off_rounded,
                size: 58,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No encontramos "$cleanedQuery"',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontFamily: 'Oswald',
                fontWeight: FontWeight.w900,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Prueba con una búsqueda más general, una marca, una referencia o una tecnología concreta.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                height: 1.5,
              ),
            ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: suggestions.map((suggestion) {
                  return ActionChip(
                    label: Text(
                      suggestion,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BusquedaResultadosPage(
                            query: suggestion,
                            onGoCart: onGoCart,
                            onGoQuotes: onGoQuotes,
                          ),
                        ),
                      );
                    },
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Volver a buscar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchEngine {
  static final Map<String, List<String>> _synonyms = {
    'camara': [
      'camara',
      'camaras',
      'camera',
      'cctv',
      'ip',
      'hd',
      'hdcvi',
      'turret',
      'bullet',
      'domo',
      'ptz',
      'lente',
      'varifocal',
    ],
    'grabador': [
      'grabador',
      'nvr',
      'xvr',
      'dvr',
      'recorder',
      'canales',
      'h265',
      'h.265',
      'poe',
    ],
    'alarma': [
      'alarma',
      'alarmas',
      'intrusion',
      'intrusión',
      'hub',
      'detector',
      'sirena',
      'teclado',
      'contacto',
      'jeweller',
      'fibra',
    ],
    'incendio': [
      'incendio',
      'fuego',
      'detector humo',
      'detector termico',
      'sirena incendio',
      'en54',
      'teletek',
    ],
    'acceso': [
      'acceso',
      'control acceso',
      'lector',
      'tarjeta',
      'biometrico',
      'biométrico',
      'cerradura',
      'terminal',
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
      'tp-link',
    ],
    '4g': [
      '4g',
      'lte',
      'sim',
      'm2m',
      'iot',
      'router 4g',
      'multioperador',
    ],
    'solar': [
      'solar',
      'panel solar',
      'autonomo',
      'autónomo',
      'bateria',
      'batería',
      'torre',
      'pod',
      'evolve',
    ],
    'analitica': [
      'analitica',
      'analítica',
      'ia',
      'ai',
      'deteccion',
      'detección',
      'persona',
      'vehiculo',
      'vehículo',
      'perimetral',
      'secury360',
    ],
  };

  static final List<String> _knownBrands = [
    'ajax',
    'dahua',
    'hikvision',
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
  ];

  static String cleanQuery(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static List<Product> sortByRelevance(List<Product> products, String query) {
    final terms = _expandedTerms(query);
    final scored = products
        .map(
          (product) => _ScoredProduct(
        product: product,
        score: _score(product, query, terms),
      ),
    )
        .toList();

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.product.name.compareTo(b.product.name);
    });

    return scored.map((item) => item.product).toList();
  }

  static int _score(Product product, String query, List<String> terms) {
    final normalizedQuery = _normalize(query);
    final name = _normalize(product.name);
    final sku = _normalize(product.sku);
    final description = _normalize(product.shortDescription);
    final fullText = '$name $sku $description';

    int score = 0;

    if (sku.isNotEmpty && sku == normalizedQuery) score += 500;
    if (sku.isNotEmpty && sku.contains(normalizedQuery)) score += 300;
    if (name == normalizedQuery) score += 260;
    if (name.startsWith(normalizedQuery)) score += 210;
    if (name.contains(normalizedQuery)) score += 170;

    for (final brand in _knownBrands) {
      final normalizedBrand = _normalize(brand);
      if (normalizedQuery.contains(normalizedBrand)) {
        if (name.contains(normalizedBrand)) score += 120;
        if (description.contains(normalizedBrand)) score += 60;
        if (sku.contains(normalizedBrand)) score += 90;
      }
    }

    for (final term in terms) {
      if (term.length < 2) continue;
      if (name.contains(term)) score += 38;
      if (sku.contains(term)) score += 45;
      if (description.contains(term)) score += 18;
      if (fullText.contains(term)) score += 10;
    }

    if (product.isInstock) score += 8;

    if (name.contains('kit') && normalizedQuery.contains('kit')) score += 35;
    if (name.contains('poe') && normalizedQuery.contains('poe')) score += 35;
    if (name.contains('wifi') && normalizedQuery.contains('wifi')) score += 35;
    if (name.contains('4g') && normalizedQuery.contains('4g')) score += 35;
    if (name.contains('en54') && normalizedQuery.contains('en54')) score += 45;

    if (name.contains('grado') && normalizedQuery.contains('grado')) {
      score += 30;
    }

    return score;
  }

  static List<String> _expandedTerms(String query) {
    final normalized = _normalize(query);
    final terms = <String>{};

    for (final raw in normalized.split(' ')) {
      final term = raw.trim();
      if (term.length >= 2) terms.add(term);
    }

    _synonyms.forEach((key, values) {
      final normalizedKey = _normalize(key);
      if (normalized.contains(normalizedKey) ||
          values.any((v) => normalized.contains(_normalize(v)))) {
        for (final value in values) {
          for (final part in _normalize(value).split(' ')) {
            if (part.trim().length >= 2) terms.add(part.trim());
          }
        }
      }
    });

    for (final brand in _knownBrands) {
      final normalizedBrand = _normalize(brand);
      if (normalized.contains(normalizedBrand)) {
        for (final part in normalizedBrand.split(' ')) {
          if (part.trim().length >= 2) terms.add(part.trim());
        }
      }
    }

    return terms.toList();
  }

  static List<String> detectedReadableTerms(String query) {
    final normalized = _normalize(query);
    final detected = <String>[];

    for (final brand in _knownBrands) {
      if (normalized.contains(_normalize(brand))) {
        detected.add(_brandLabel(brand));
      }
    }

    if (_containsAny(
      normalized,
      ['camara', 'camaras', 'cctv', 'turret', 'bullet', 'domo', 'ptz'],
    )) {
      detected.add('CCTV / Cámaras');
    }

    if (_containsAny(normalized, ['nvr', 'xvr', 'dvr', 'grabador'])) {
      detected.add('Grabadores');
    }

    if (_containsAny(
      normalized,
      ['alarma', 'intrusion', 'hub', 'detector', 'sirena'],
    )) {
      detected.add('Intrusión');
    }

    if (_containsAny(normalized, ['incendio', 'fuego', 'en54', 'humo'])) {
      detected.add('Incendio');
    }

    if (_containsAny(
      normalized,
      ['poe', 'switch', 'router', 'wifi', 'networking', 'red'],
    )) {
      detected.add('Networking');
    }

    if (_containsAny(normalized, ['4g', 'lte', 'sim', 'm2m', 'iot'])) {
      detected.add('IoT / M2M');
    }

    return detected.toSet().take(6).toList();
  }

  static List<String> suggestionsFor(String query) {
    final normalized = _normalize(query);

    if (_containsAny(normalized, ['camara', 'camera', 'cctv'])) {
      return ['cámara IP', 'cámara PoE', 'cámara Dahua', 'cámara Hikvision'];
    }

    if (_containsAny(normalized, ['grabador', 'nvr', 'xvr', 'dvr'])) {
      return ['NVR Dahua', 'grabador IP', 'XVR', 'NVR PoE'];
    }

    if (_containsAny(normalized, ['alarma', 'intrusion', 'intrusión'])) {
      return ['Ajax Hub', 'detector Ajax', 'sirena Ajax', 'Ksenia lares'];
    }

    if (_containsAny(normalized, ['incendio', 'fuego', 'en54'])) {
      return ['Teletek EN54', 'Ajax EN54', 'detector humo', 'central incendio'];
    }

    if (_containsAny(normalized, ['red', 'poe', 'switch', 'router', 'wifi'])) {
      return ['switch PoE', 'router 4G', 'Omada', 'VIGI'];
    }

    return ['Dahua', 'Ajax', 'Hikvision', 'cámara IP', 'NVR', 'switch PoE'];
  }

  static String _normalize(String value) {
    String text = value.toLowerCase().trim();

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
    };

    replacements.forEach((from, to) => text = text.replaceAll(from, to));

    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool _containsAny(String source, List<String> values) {
    return values.any((value) => source.contains(_normalize(value)));
  }

  static String _brandLabel(String brand) {
    switch (_normalize(brand)) {
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
      default:
        return brand.toUpperCase();
    }
  }
}

class _ScoredProduct {
  final Product product;
  final int score;

  const _ScoredProduct({
    required this.product,
    required this.score,
  });
}

class ProductTileBusqueda extends ConsumerStatefulWidget {
  final Product p;
  final FirebaseService firebase;
  final VoidCallback? onGoCart;
  final VoidCallback? onGoQuotes;

  const ProductTileBusqueda({
    super.key,
    required this.p,
    required this.firebase,
    this.onGoCart,
    this.onGoQuotes,
  });

  @override
  ConsumerState<ProductTileBusqueda> createState() =>
      _ProductTileBusquedaState();
}

class _ProductTileBusquedaState extends ConsumerState<ProductTileBusqueda> {
  int cantidad = 1;
  bool _isAddingToQuote = false;

  double _precioDouble(Product p) {
    return double.tryParse(p.price.replaceAll(',', '.').trim()) ?? 0;
  }

  String _formatearPrecio(double value) {
    return value <= 0
        ? 'Bajo consulta'
        : '${value.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  void _goToQuotesKeepingTabs() {
    final goQuotes = widget.onGoQuotes;

    if (goQuotes != null) {
      final navigator = Navigator.of(context);
      if (navigator.canPop()) navigator.popUntil((route) => route.isFirst);
      WidgetsBinding.instance.addPostFrameCallback((_) => goQuotes());
      return;
    }

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Producto añadido al presupuesto'),
        backgroundColor: AppColors.primary,
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final precio = _precioDouble(p);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE7E7E7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProductDetailScreen(
                      product: p,
                      onGoCart: widget.onGoCart,
                      onGoQuotes: widget.onGoQuotes,
                    ),
                  ),
                );
              },
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Hero(
                    tag: 'search_${p.id}',
                    child: ProductImageBusqueda(p: p),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                p.name,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.textPrimary,
                                  height: 1.17,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _stockChip(p),
                          ],
                        ),
                        if (p.shortDescription.trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            p.shortDescription,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B7280),
                              height: 1.25,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Text(
                          _formatearPrecio(precio),
                          style: TextStyle(
                            fontSize: precio > 0 ? 22 : 18,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primary,
                            fontFamily: 'Oswald',
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _quantitySelector(p),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: p.isInstock
                          ? () {
                        ref
                            .read(cartProvider.notifier)
                            .addProduct(p, cantidad);

                        ScaffoldMessenger.of(context).clearSnackBars();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '$cantidad x ${p.name} añadido al carrito',
                            ),
                            backgroundColor: AppColors.primary,
                            duration: const Duration(seconds: 1),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                          : null,
                      icon: Icon(
                        p.isInstock
                            ? Icons.shopping_cart_outlined
                            : Icons.block_rounded,
                        size: 17,
                        color: Colors.white,
                      ),
                      label: Text(
                        p.isInstock ? 'AÑADIR CARRITO' : 'SIN STOCK',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                          color: Colors.white,
                          fontFamily: 'Oswald',
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                        p.isInstock ? AppColors.primary : Colors.grey.shade400,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: OutlinedButton.icon(
                onPressed: (p.isInstock && !_isAddingToQuote)
                    ? () => _addToQuote(p)
                    : null,
                icon: _isAddingToQuote
                    ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                )
                    : Icon(
                  p.isInstock
                      ? Icons.description_outlined
                      : Icons.block_rounded,
                  size: 17,
                ),
                label: Text(
                  !p.isInstock
                      ? 'SIN STOCK'
                      : _isAddingToQuote
                      ? 'AÑADIENDO...'
                      : 'AÑADIR AL PRESUPUESTO',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                    fontFamily: 'Oswald',
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  backgroundColor: p.isInstock
                      ? Colors.white
                      : Colors.grey.shade100,
                  foregroundColor: AppColors.textPrimary,
                  disabledForegroundColor: Colors.grey.shade500,
                  side: BorderSide(
                    color: p.isInstock
                        ? const Color(0xFFD9DEE7)
                        : Colors.grey.shade300,
                    width: 1.2,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quantitySelector(Product p) {
    return Opacity(
      opacity: p.isInstock ? 1.0 : 0.55,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FB),
          border: Border.all(color: const Color(0xFFE1E4EA)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _qtyBtn(
              Icons.remove,
              enabled: p.isInstock,
              onTap: () {
                if (cantidad > 1) setState(() => cantidad--);
              },
            ),
            SizedBox(
              width: 34,
              child: Text(
                '$cantidad',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: p.isInstock ? AppColors.textPrimary : Colors.grey,
                ),
              ),
            ),
            _qtyBtn(
              Icons.add,
              enabled: p.isInstock,
              isPrimary: p.isInstock,
              onTap: () {
                if (p.isInstock) setState(() => cantidad++);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _stockChip(Product p) {
    final hasStock = p.isInstock;
    final bgColor = hasStock ? const Color(0xFFEAF7EE) : const Color(0xFFFDECEC);
    final textColor = hasStock ? const Color(0xFF218047) : const Color(0xFFC62828);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: textColor.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: textColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            hasStock ? 'En stock' : 'Sin stock',
            style: TextStyle(
              fontSize: 10.5,
              color: textColor,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _qtyBtn(
      IconData icon, {
        required bool enabled,
        required VoidCallback onTap,
        bool isPrimary = false,
      }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: SizedBox(
        width: 34,
        height: 42,
        child: Icon(
          icon,
          size: 17,
          color: enabled
              ? (isPrimary ? AppColors.primary : Colors.black87)
              : Colors.grey.shade400,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // AÑADIR AL PRESUPUESTO CON QuoteSelectionDialog
  // ═══════════════════════════════════════════════════════════════

  Future<void> _addToQuote(Product product) async {
    if (_isAddingToQuote) return;
    if (product.id == 0) return;

    if (!product.isInstock) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se puede añadir "${product.name}" al presupuesto porque no hay stock.',
          ),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final precio = _precioDouble(product);

    // Mostrar el diálogo de selección de presupuesto
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => QuoteSelectionDialog(
        productName: product.name,
        productId: product.id,
        price: precio,
        quantity: cantidad,
      ),
    );

    // Usuario canceló el diálogo
    if (result == null || !mounted) return;

    setState(() => _isAddingToQuote = true);

    try {
      final action = result['action'] as String;
      final notifier = ref.read(localQuotesProvider.notifier);
      String mensaje = '';

      if (action == 'crear_y_anadir') {
        // CREAR NUEVO PRESUPUESTO
        final nombre = result['nombre'] as String;
        final orderId = DateTime.now().millisecondsSinceEpoch.toString();
        final nombreFinal = nombre.isNotEmpty ? nombre : 'Presupuesto #$orderId';

        await notifier.crearPresupuesto(
          orderId: orderId,
          nombre: nombreFinal,
        );

        await notifier.anadirItem(
          orderId: orderId,
          item: LocalQuoteItem(
            productId: product.id,
            productName: product.name,
            quantity: cantidad,
            price: precio,
          ),
        );

        mensaje = '$cantidad x ${product.name} añadido a "$nombreFinal"';
      } else if (action == 'anadir_existente') {
        // AÑADIR A PRESUPUESTO EXISTENTE
        final orderId = result['orderId'] as String;
        final nombre = result['nombre'] as String;

        await notifier.anadirItem(
          orderId: orderId,
          item: LocalQuoteItem(
            productId: product.id,
            productName: product.name,
            quantity: cantidad,
            price: precio,
          ),
        );

        mensaje = '$cantidad x ${product.name} añadido a "$nombre"';
      }

      if (mounted && mensaje.isNotEmpty) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(mensaje),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'VER',
              textColor: Colors.white,
              onPressed: _goToQuotesKeepingTabs,
            ),
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error en _addToQuote búsqueda: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAddingToQuote = false);
      }
    }
  }
}

class ProductImageBusqueda extends StatelessWidget {
  final Product p;

  const ProductImageBusqueda({
    super.key,
    required this.p,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7E7E7)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: CachedNetworkImage(
          imageUrl: p.imageUrl,
          fit: BoxFit.contain,
          placeholder: (context, url) => Container(color: Colors.grey[100]),
          errorWidget: (context, url, error) => const Icon(
            Icons.broken_image,
            color: Colors.grey,
          ),
        ),
      ),
    );
  }
}
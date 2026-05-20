import 'package:mundicam/features/catalog/presentation/pages/producto_detalles_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/features/cart/presentation/pages/cart_page.dart';
import 'package:mundicam/features/catalog/data/models/producto.dart';
import 'package:mundicam/features/catalog/presentation/providers/products_provider.dart';
import 'package:mundicam/features/cart/presentation/providers/cart_provider.dart';
import 'package:mundicam/features/quotes/presentation/providers/quote_provider.dart';
import 'package:mundicam/features/quotes/presentation/pages/quotes_page.dart';
import 'package:mundicam/features/profile/presentation/providers/user_provider.dart';
import 'package:mundicam/core/firebase/firebase_service.dart';
import 'package:mundicam/shared/theme/app_theme.dart';

class BusquedaResultadosPage extends ConsumerWidget {
  final String query;

  const BusquedaResultadosPage({super.key, required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String cleanedQuery = _SearchEngine.cleanQuery(query);
    final searchAsync = ref.watch(searchProductsProvider(cleanedQuery));
    final FirebaseService firebase = FirebaseService();

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      appBar: AppBar(
        title: Text(
          'Resultados: "$cleanedQuery"',
          style: const TextStyle(fontSize: 16, fontFamily: 'Oswald'),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        centerTitle: true,
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

          final List<String> detectedTerms =
          _SearchEngine.detectedReadableTerms(cleanedQuery);

          return Column(
            children: [
              Container(
                width: double.infinity,
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.search_rounded,
                          size: 17,
                          color: Colors.grey[700],
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${productos.length} producto${productos.length != 1 ? 's' : ''} encontrado${productos.length != 1 ? 's' : ''}',
                            style: TextStyle(
                              color: Colors.grey[800],
                              fontWeight: FontWeight.w700,
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
                                color: AppColors.primary.withValues(
                                  alpha: 0.18,
                                ),
                              ),
                            ),
                            child: Text(
                              term,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
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
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: productos.length,
                  itemBuilder: (context, index) {
                    return ProductTileBusqueda(
                      p: productos[index],
                      firebase: firebase,
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
            const Icon(Icons.error_outline, size: 60, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Error al buscar productos',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
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
    final List<String> suggestions = _SearchEngine.suggestionsFor(cleanedQuery);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 90, color: Colors.grey[350]),
            const SizedBox(height: 20),
            Text(
              'No encontramos "$cleanedQuery"',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
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
                          builder: (_) =>
                              BusquedaResultadosPage(query: suggestion),
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

// ------------------------------------------------------------
// MOTOR LOCAL DE RELEVANCIA PARA BÚSQUEDA
// ------------------------------------------------------------

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
    '4g': ['4g', 'lte', 'sim', 'm2m', 'iot', 'router 4g', 'multioperador'],
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
    final List<String> terms = _expandedTerms(query);

    final List<_ScoredProduct> scored = products.map((product) {
      return _ScoredProduct(
        product: product,
        score: _score(product, query, terms),
      );
    }).toList();

    scored.sort((a, b) {
      final int byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;

      return a.product.name.compareTo(b.product.name);
    });

    return scored.map((item) => item.product).toList();
  }

  static int _score(Product product, String query, List<String> terms) {
    final String normalizedQuery = _normalize(query);
    final String name = _normalize(product.name);
    final String sku = _normalize(product.sku);
    final String description = _normalize(product.shortDescription);

    final String fullText = '$name $sku $description';

    int score = 0;

    if (sku.isNotEmpty && sku == normalizedQuery) score += 500;
    if (sku.isNotEmpty && sku.contains(normalizedQuery)) score += 300;

    if (name == normalizedQuery) score += 260;
    if (name.startsWith(normalizedQuery)) score += 210;
    if (name.contains(normalizedQuery)) score += 170;

    for (final brand in _knownBrands) {
      final String normalizedBrand = _normalize(brand);

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
    final String normalized = _normalize(query);

    final Set<String> terms = {};

    for (final raw in normalized.split(' ')) {
      final term = raw.trim();
      if (term.length >= 2) {
        terms.add(term);
      }
    }

    _synonyms.forEach((key, values) {
      final String normalizedKey = _normalize(key);

      if (normalized.contains(normalizedKey) ||
          values.any((v) => normalized.contains(_normalize(v)))) {
        for (final value in values) {
          final normalizedValue = _normalize(value);

          for (final part in normalizedValue.split(' ')) {
            if (part.trim().length >= 2) {
              terms.add(part.trim());
            }
          }
        }
      }
    });

    for (final brand in _knownBrands) {
      final String normalizedBrand = _normalize(brand);

      if (normalized.contains(normalizedBrand)) {
        for (final part in normalizedBrand.split(' ')) {
          if (part.trim().length >= 2) {
            terms.add(part.trim());
          }
        }
      }
    }

    return terms.toList();
  }

  static List<String> detectedReadableTerms(String query) {
    final String normalized = _normalize(query);
    final List<String> detected = [];

    for (final brand in _knownBrands) {
      if (normalized.contains(_normalize(brand))) {
        detected.add(_brandLabel(brand));
      }
    }

    if (_containsAny(normalized, [
      'camara',
      'camaras',
      'cctv',
      'turret',
      'bullet',
      'domo',
      'ptz',
    ])) {
      detected.add('CCTV / Cámaras');
    }

    if (_containsAny(normalized, ['nvr', 'xvr', 'dvr', 'grabador'])) {
      detected.add('Grabadores');
    }

    if (_containsAny(normalized, [
      'alarma',
      'intrusion',
      'hub',
      'detector',
      'sirena',
    ])) {
      detected.add('Intrusión');
    }

    if (_containsAny(normalized, ['incendio', 'fuego', 'en54', 'humo'])) {
      detected.add('Incendio');
    }

    if (_containsAny(normalized, [
      'poe',
      'switch',
      'router',
      'wifi',
      'networking',
      'red',
    ])) {
      detected.add('Networking');
    }

    if (_containsAny(normalized, ['4g', 'lte', 'sim', 'm2m', 'iot'])) {
      detected.add('IoT / M2M');
    }

    return detected.toSet().take(6).toList();
  }

  static List<String> suggestionsFor(String query) {
    final String normalized = _normalize(query);

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

    const Map<String, String> replacements = {
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

    replacements.forEach((from, to) {
      text = text.replaceAll(from, to);
    });

    text = text.replaceAll(RegExp(r'\s+'), ' ');

    return text.trim();
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

// ------------------------------------------------------------
// TILE PRODUCTO RESULTADO BÚSQUEDA
// ------------------------------------------------------------

class ProductTileBusqueda extends ConsumerStatefulWidget {
  final Product p;
  final FirebaseService firebase;

  const ProductTileBusqueda({
    super.key,
    required this.p,
    required this.firebase,
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
    if (value <= 0) return 'Bajo consulta';

    return '${value.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  Future<String?> _getCurrentUserEmail() async {
    final appUser = ref.read(currentUserProvider).value;

    if (appUser != null && appUser.email.trim().isNotEmpty) {
      return appUser.email.trim();
    }

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return null;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists && userDoc.data() != null) {
        final email = userDoc.data()?['email']?.toString();

        if (email != null && email.trim().isNotEmpty) {
          return email.trim();
        }
      }
    } catch (e) {
      debugPrint('Error al leer email de Firestore: $e');
    }

    if (user.email != null && user.email!.trim().isNotEmpty) {
      return user.email!.trim();
    }

    if (user.providerData.isNotEmpty) {
      final providerEmail = user.providerData.first.email;

      if (providerEmail != null && providerEmail.trim().isNotEmpty) {
        return providerEmail.trim();
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final Product p = widget.p;
    final double precio = _precioDouble(p);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProductDetailScreen(product: p),
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
                      Text(
                        p.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        p.isInstock ? '● Disponible' : '○ Sin stock',
                        style: TextStyle(
                          fontSize: 11,
                          color: p.isInstock ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (p.shortDescription.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          p.shortDescription,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            height: 1.25,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          _formatearPrecio(precio),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primary,
                            fontFamily: 'Oswald',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: ElevatedButton(
                    onPressed: p.isInstock
                        ? () {
                      ref
                          .read(cartProvider.notifier)
                          .addProduct(p, cantidad);

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CartPage(),
                        ),
                      );
                    }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: p.isInstock
                          ? AppColors.primary
                          : Colors.grey.shade400,
                      foregroundColor: Colors.white,
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                    child: Text(
                      p.isInstock ? 'COMPRAR YA' : 'SIN STOCK',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Opacity(
                  opacity: p.isInstock ? 1 : 0.5,
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _qtyBtn(
                          Icons.remove,
                          enabled: p.isInstock,
                          onTap: () {
                            if (cantidad > 1) {
                              setState(() {
                                cantidad--;
                              });
                            }
                          },
                        ),
                        Text(
                          '$cantidad',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: p.isInstock ? Colors.black : Colors.grey,
                          ),
                        ),
                        _qtyBtn(
                          Icons.add,
                          enabled: p.isInstock,
                          isPrimary: p.isInstock,
                          onTap: () {
                            if (p.isInstock) {
                              setState(() {
                                cantidad++;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: OutlinedButton(
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
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: p.isInstock
                            ? AppColors.primary
                            : Colors.grey.shade400,
                        width: 1.3,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                    child: Text(
                      p.isInstock ? 'AÑADIR CARRITO' : 'SIN STOCK',
                      style: TextStyle(
                        fontSize: 10,
                        color:
                        p.isInstock ? AppColors.primary : Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: OutlinedButton.icon(
                    onPressed: _isAddingToQuote ? null : () => _addToQuote(p),
                    icon: _isAddingToQuote
                        ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.orange,
                      ),
                    )
                        : Icon(
                      Icons.description_outlined,
                      size: 14,
                      color: Colors.orange.shade700,
                    ),
                    label: Text(
                      _isAddingToQuote ? '...' : 'PRESUPUESTO',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade700,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange.shade700,
                      side: BorderSide(
                        color: Colors.orange.shade700,
                        width: 1.3,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                  ),
                ),
              ),
            ],
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
      child: Container(
        width: 30,
        height: 36,
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 16,
          color: enabled
              ? (isPrimary ? AppColors.primary : Colors.black87)
              : Colors.grey.shade400,
        ),
      ),
    );
  }

  Future<void> _addToQuote(Product product) async {
    if (_isAddingToQuote) return;

    setState(() {
      _isAddingToQuote = true;
    });

    try {
      final api = ApiService();
      final email = await _getCurrentUserEmail();

      if (email == null || email.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Debes iniciar sesión para crear presupuestos'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }

        return;
      }

      if (product.id == 0) {
        throw Exception('ID de producto no válido');
      }

      final precio =
          double.tryParse(product.price.replaceAll(',', '.').trim()) ?? 0.0;

      final ok = await api.crearPresupuesto(
        email: email,
        productId: product.id,
        productName: product.name,
        price: precio,
        quantity: cantidad,
      );

      if (!mounted) return;

      if (!ok) {
        throw Exception('No se pudo añadir el producto al presupuesto.');
      }

      ref.invalidate(quotesProvider);

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$cantidad x ${product.name} añadido al presupuesto'),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'VER',
            textColor: Colors.white,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const QuotesPage()),
              );
            },
          ),
        ),
      );
    } catch (e) {
      debugPrint('❌ Error en _addToQuote búsqueda: $e');

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
        setState(() {
          _isAddingToQuote = false;
        });
      }
    }
  }
}

class ProductImageBusqueda extends StatelessWidget {
  final Product p;

  const ProductImageBusqueda({super.key, required this.p});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: p.imageUrl,
          fit: BoxFit.contain,
          placeholder: (context, url) => Container(color: Colors.grey[100]),
          errorWidget: (context, url, error) =>
          const Icon(Icons.broken_image, color: Colors.grey),
        ),
      ),
    );
  }
}
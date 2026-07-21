// ARCHIVO: lib/features/catalog/presentation/pages/producto_detalles_page.dart
// Sustituye el archivo completo por este contenido.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/features/cart/presentation/providers/cart_provider.dart';
import 'package:mundicam/features/catalog/data/models/producto.dart';
import 'package:mundicam/features/quotes/data/models/local_quote_model.dart';
import 'package:mundicam/features/quotes/presentation/providers/local_quote_provider.dart';
import 'package:mundicam/features/quotes/presentation/widgets/quote_selection_dialog.dart';
import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/shared/widgets/professional_page_app_bar.dart';


final _canViewStockDetailsProvider = FutureProvider<bool>((ref) async {
  try {
    // La sesión de negocio válida es WordPress/MundiCam App API.
    // No dependemos de Firebase para decidir permisos de stock.
    final canViewFromAppSession = await ApiService().currentSessionCanViewStockDetails();
    if (canViewFromAppSession) return true;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final wordpressId = await _resolveWordPressIdForCurrentUser(user);
    if (wordpressId == null || wordpressId <= 0) {
      return false;
    }

    return ApiService().canCustomerViewStockDetails(wordpressId);
  } catch (e) {
    if (kDebugMode) {
      debugPrint('Error resolviendo permiso de stock interno: $e');
    }
    return false;
  }
});

Future<int?> _resolveWordPressIdForCurrentUser(User user) async {
  final firestore = FirebaseFirestore.instance;

  try {
    final doc = await firestore.collection('users').doc(user.uid).get();
    final fromDoc = _wordPressIdFromUserData(doc.data());
    if (fromDoc != null && fromDoc > 0) {
      return fromDoc;
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('No se pudo leer users/${user.uid}: $e');
    }
  }

  final email = user.email?.trim().toLowerCase();
  if (email != null && email.isNotEmpty) {
    try {
      final query = await firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final fromEmailDoc = _wordPressIdFromUserData(query.docs.first.data());
        if (fromEmailDoc != null && fromEmailDoc > 0) {
          return fromEmailDoc;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('No se pudo buscar usuario por email para stock: $e');
      }
    }
  }

  return _wordPressIdFromDynamic(user.uid);
}

int? _wordPressIdFromUserData(Map<String, dynamic>? data) {
  if (data == null || data.isEmpty) return null;

  const keys = <String>[
    'wordpress_id',
    'wordpressId',
    'woocommerce_id',
    'woocommerceId',
    'customer_id',
    'customerId',
    'wp_user_id',
    'wpUserId',
    'woo_customer_id',
    'wooCustomerId',
    'uid',
  ];

  for (final key in keys) {
    final id = _wordPressIdFromDynamic(data[key]);
    if (id != null && id > 0) return id;
  }

  return null;
}

int? _wordPressIdFromDynamic(dynamic value) {
  if (value == null) return null;

  if (value is int && value > 0) return value;
  if (value is num && value > 0) return value.toInt();

  final raw = value.toString().trim();
  if (raw.isEmpty) return null;

  final direct = int.tryParse(raw);
  if (direct != null && direct > 0) return direct;

  final match = RegExp(r'wp[_-]?(\d+)', caseSensitive: false).firstMatch(raw);
  if (match != null) {
    final parsed = int.tryParse(match.group(1) ?? '');
    if (parsed != null && parsed > 0) return parsed;
  }

  return null;
}

class ProductDetailScreen extends ConsumerStatefulWidget {
  final Product product;
  final VoidCallback? onGoCart;
  final VoidCallback? onGoQuotes;
  final String? contextCategoryName;

  const ProductDetailScreen({
    super.key,
    required this.product,
    this.onGoCart,
    this.onGoQuotes,
    this.contextCategoryName,
  });

  @override
  ConsumerState<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  int _cantidad = 1;
  bool _isAddingToCart = false;
  bool _isAddingToQuote = false;
  bool _descriptionExpanded = true;
  bool _cargandoRecomendados = true;
  bool _isRefreshingProduct = false;
  Product? _productWithFreshStock;
  List<Product> _recomendados = [];

  static const Color _dark = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _softBg = Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _cargarStockDetalladoSiHaceFalta();
    _cargarRecomendados();
  }

  Future<void> _cargarStockDetalladoSiHaceFalta() async {
    if (widget.product.hasStockLocationDetails) return;

    try {
      final canViewStock = await ApiService().currentSessionCanViewStockDetails();
      if (!canViewStock) return;

      final fullProduct = await ApiService().getProductoById(widget.product.id);
      if (!mounted || fullProduct == null || !fullProduct.hasStockLocationDetails) {
        return;
      }

      setState(() {
        // Solo refrescamos stock y permisos comerciales. No tocamos el precio
        // recibido en el listado/búsqueda para evitar cambiar el rol efectivo.
        _productWithFreshStock = widget.product.copyWithStockFrom(fullProduct);
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('No se pudo refrescar stock interno del producto: $e');
      }
    }
  }

  Future<void> _refreshProductDetail() async {
    if (_isRefreshingProduct) return;

    setState(() {
      _isRefreshingProduct = true;
    });

    try {
      final fullProduct = await ApiService().getProductoById(widget.product.id);
      if (!mounted) return;

      if (fullProduct != null) {
        setState(() {
          _productWithFreshStock = fullProduct;
        });
      }

      ref.invalidate(_canViewStockDetailsProvider);
      await _cargarRecomendados();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('No se pudo recargar el producto: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo actualizar el producto'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingProduct = false;
        });
      }
    }
  }

  Future<void> _cargarRecomendados() async {
    try {
      final api = ApiService();
      final product = widget.product;
      String? marca;
      for (final attr in product.attributes) {
        if (attr.name.toLowerCase().contains('marca') && attr.options.isNotEmpty) {
          marca = attr.options.first;
          break;
        }
      }

      List<Product> todos = [];
      if (marca != null && marca.isNotEmpty) {
        todos.addAll(await api.getProductos(brand: marca, perPage: 20));
      }
      if (todos.length < 10) {
        todos.addAll(await api.getProductos(perPage: 50));
      }

      final seen = <int>{};
      todos = todos.where((p) => seen.add(p.id)).toList();

      final precioActual = double.tryParse(product.price.replaceAll(',', '.').trim()) ?? 0;
      final recomendados = todos
          .where((p) => p.id != product.id && p.canAddToCart)
          .map((p) {
        int score = 0;
        if (marca != null) {
          for (final a in p.attributes) {
            if (a.name.toLowerCase().contains('marca') &&
                a.options.any(
                      (o) => o.toLowerCase() == marca!.toLowerCase(),
                )) {
              score += 100;
            }
          }
        }
        final pp = double.tryParse(p.price.replaceAll(',', '.').trim()) ?? 0;
        if (precioActual > 0 && pp > 0) {
          final diff = (pp - precioActual).abs() / precioActual;
          if (diff < 0.15) {
            score += 50;
          } else if (diff < 0.30) {
            score += 30;
          } else if (diff < 0.50) {
            score += 10;
          }
        }
        return MapEntry(p, score);
      })
          .where((e) => e.value > 0)
          .toList();

      recomendados.sort((a, b) => b.value.compareTo(a.value));
      List<Product> finales = recomendados.map((e) => e.key).take(8).toList();

      if (finales.length < 4) {
        finales.addAll(
          todos
              .where(
                (p) =>
            p.id != product.id &&
                p.canAddToCart &&
                !finales.any((f) => f.id == p.id),
          )
              .take(8 - finales.length),
        );
      }

      if (!mounted) return;
      setState(() {
        _recomendados = finales;
        _cargandoRecomendados = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _cargandoRecomendados = false;
        });
      }
    }
  }

  String _limpiarHtml(String t) {
    // Conserva la estructura de tablas/listas antes de borrar HTML.
    // Si se eliminan las etiquetas de una tabla sin saltos de línea, la ficha
    // queda ilegible: ESPECIFICACIONESParámetroValorVoltaje...
    return t
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</(p|div|section|article|h[1-6])\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<(p|div|section|article|h[1-6])[^>]*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '\n• ')
        .replaceAll(RegExp(r'</li\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<tr[^>]*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</tr\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<t[dh][^>]*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</t[dh]\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</?(table|thead|tbody|tfoot)[^>]*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#034;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&#8211;', '-')
        .replaceAll('&ndash;', '-')
        .replaceAll('&mdash;', '-')
        .replaceAll(RegExp(r'[ \t\r\f\v]+'), ' ')
        .replaceAll(RegExp(r' *\n *'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _bestDetailImageUrl(Product p) {
    final original = p.imageUrl.trim();
    if (original.isEmpty || original.toLowerCase() == 'null') {
      return 'https://via.placeholder.com/1200x1200.png?text=MundiCam';
    }

    return _upgradeWordPressImageUrl(original);
  }

  String _fallbackDetailImageUrl(Product p) {
    final original = p.imageUrl.trim();
    if (original.isEmpty || original.toLowerCase() == 'null') {
      return 'https://via.placeholder.com/1200x1200.png?text=MundiCam';
    }
    return _decodeUrl(original);
  }

  String _decodeUrl(String value) {
    return value
        .trim()
        .replaceAll('&amp;', '&')
        .replaceAll('&#038;', '&')
        .replaceAll('&quot;', '"');
  }

  String _upgradeWordPressImageUrl(String value) {
    final clean = _decodeUrl(value);
    if (clean.isEmpty) return clean;

    final uriParts = clean.split('?');
    final base = uriParts.first;

    final upgraded = base.replaceFirst(
      RegExp(r'-\d+x\d+(?=\.[a-zA-Z0-9]+(?:\.[a-zA-Z0-9]+)?$)'),
      '',
    );

    return upgraded;
  }

  void _openImagePreview(Product p) {
    final fullImage = _bestDetailImageUrl(p);
    final fallbackImage = _fallbackDetailImageUrl(p);

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.88),
      builder: (dialogContext) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4,
                    child: CachedNetworkImage(
                      imageUrl: fullImage,
                      fit: BoxFit.contain,
                      memCacheWidth: 1800,
                      maxWidthDiskCache: 2400,
                      placeholder: (context, url) => const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      errorWidget: (context, url, error) => CachedNetworkImage(
                        imageUrl: fallbackImage,
                        fit: BoxFit.contain,
                        memCacheWidth: 1400,
                        maxWidthDiskCache: 1800,
                        errorWidget: (context, url, error) => const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white54,
                          size: 70,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.14),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  double _precioDouble(Product p) {
    return double.tryParse(p.price.replaceAll(',', '.').trim()) ?? 0;
  }

  double _precioRegularDouble(Product p) {
    return double.tryParse(p.regularPrice.replaceAll(',', '.').trim()) ?? 0;
  }

  String _formatearPrecio(double v) {
    if (v <= 0) return 'Bajo consulta';
    return '${v.toStringAsFixed(2).replaceAll('.', ',')} €';
  }


  int _safeQuantity(Product p) {
    if (!p.canAddToCart) return 0;
    final maxPurchaseQty = p.maxPurchaseQty;
    if (maxPurchaseQty <= 0) return _cantidad;
    return _cantidad.clamp(1, maxPurchaseQty).toInt();
  }

  int _safeQuoteQuantity(Product p) {
    if (!p.canRequestQuote) return 0;

    final maxQty = p.hasMundicamInternalStock
        ? p.generalStockQuantity + p.murciaStockQuantity
        : (p.stockQuantity > 0 ? p.stockQuantity : 999);

    if (maxQty <= 0) return 0;
    return _cantidad.clamp(1, maxQty).toInt();
  }

  bool _canIncreaseQuantity(Product p) {
    if (!p.canAddToCart) return false;
    final maxPurchaseQty = p.maxPurchaseQty;
    return maxPurchaseQty <= 0 || _cantidad < maxPurchaseQty;
  }

  String? _resolveVisualCategory(Product p) {
    final fromContext = widget.contextCategoryName?.trim();
    if (fromContext != null && fromContext.isNotEmpty) return fromContext;
    final short = _limpiarHtml(p.shortDescription);
    if (short.isNotEmpty) {
      final firstLine = short.split('\n').map((e) => e.trim()).firstWhere(
            (e) => e.isNotEmpty,
        orElse: () => '',
      );
      if (firstLine.isNotEmpty && firstLine.length <= 40) return firstLine;
    }
    return null;
  }

  String _normalizeMultilineText(String text) {
    final expanded = _expandCollapsedTechnicalText(text);
    final lines = expanded
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return lines.join('\n');
  }

  String _expandCollapsedTechnicalText(String text) {
    var out = text
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[ \t\f\v]+'), ' ')
        .replaceAll(RegExp(r' *\n *'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    if (out.isEmpty) return out;

    out = out.replaceAllMapped(
      RegExp(r'(ESPECIFICACIONES\s+T[ÉE]CNICAS)\s*(Par[áa]metro)', caseSensitive: false),
          (m) => '${m.group(1)}\n${m.group(2)}',
    );
    out = out.replaceAllMapped(
      RegExp(r'(Par[áa]metro)\s*(Valor)', caseSensitive: false),
          (m) => '${m.group(1)}\n${m.group(2)}',
    );

    // Algunos productos llegan desde WooCommerce con la tabla técnica ya sin
    // etiquetas HTML y sin separadores. Insertamos saltos antes/después de los
    // campos técnicos habituales para recuperar formato de tabla.
    final technicalLabels = <String>[
      'Temperatura de funcionamiento',
      'Temperatura de almacenamiento',
      'Humedad de funcionamiento',
      'Humedad de almacenamiento',
      'Protección de sobrecarga',
      'Protección de sobretensión',
      'Corriente de interrupción',
      'Resistencia de aislamiento',
      'Rango de ajuste de voltaje',
      'Tolerancia de voltaje',
      'Corriente de entrada',
      'Corriente de salida',
      'Corriente residual',
      'Aislamiento (I/P-FG)',
      'Aislamiento (I/P–FG)',
      'Aislamiento (O/P-FG)',
      'Aislamiento (O/P–FG)',
      'Potencia nominal',
      'Tiempo de subida',
      'Carga de entrada',
      'Voltaje de salida',
      'Onda y ruido',
      'Certificaciones',
      'Dimensiones',
    ];

    for (final label in technicalLabels) {
      final escaped = RegExp.escape(label);
      out = out.replaceAllMapped(RegExp(escaped, caseSensitive: false), (match) {
        final found = match.group(0) ?? label;
        final before = match.start > 0 ? out.substring(match.start - 1, match.start) : '\n';
        final after = match.end < out.length ? out.substring(match.end, match.end + 1) : '\n';
        final prefix = before == '\n' ? '' : '\n';
        final suffix = after == '\n' ? '' : '\n';
        return '$prefix$found$suffix';
      });
    }

    out = out.replaceAllMapped(
      RegExp(r'([a-záéíóúñ0-9\)])\.([A-ZÁÉÍÓÚÑ])'),
          (m) => '${m.group(1)}.\n${m.group(2)}',
    );
    out = out.replaceAllMapped(
      RegExp(r'(Protecciones avanzadas:)\s*', caseSensitive: false),
          (m) => '\n${m.group(1)} ',
    );
    out = out.replaceAllMapped(
      RegExp(r'(Funcionamiento robusto:)\s*', caseSensitive: false),
          (m) => '\n${m.group(1)} ',
    );

    return out
        .replaceAll(RegExp(r' *\n *'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  bool _isTechnicalHeading(String value) {
    final clean = value
        .toLowerCase()
        .replaceAll(':', '')
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .trim();

    return clean == 'especificaciones tecnicas' ||
        clean == 'ficha tecnica' ||
        clean == 'caracteristicas tecnicas' ||
        clean == 'parametro' ||
        clean == 'valor';
  }

  List<MapEntry<String, String>> _parseKeyValueRows(String text) {
    final normalized = _normalizeMultilineText(text);
    final lines = normalized
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .where((e) => !_isTechnicalHeading(e))
        .toList();

    if (lines.length < 4) return <MapEntry<String, String>>[];

    final rows = <MapEntry<String, String>>[];
    for (var i = 0; i < lines.length - 1; i += 2) {
      final key = lines[i].trim().replaceAll(RegExp(r'[:\-–—]+$'), '').trim();
      final value = lines[i + 1].trim();
      if (key.isEmpty || value.isEmpty) continue;
      if (key.length > 58) return <MapEntry<String, String>>[];
      rows.add(MapEntry(key, value));
    }

    return rows.length >= 2 ? rows : <MapEntry<String, String>>[];
  }


  List<MapEntry<String, String>> _attributeRows(Product p) {
    final rows = <MapEntry<String, String>>[];

    for (final attr in p.attributes) {
      final name = attr.name.trim();
      final value = attr.options
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .join(', ');

      if (name.isEmpty || value.isEmpty) continue;

      final normalized = name
          .toLowerCase()
          .replaceAll('pa_', '')
          .replaceAll('-', ' ')
          .replaceAll('_', ' ')
          .trim();

      if (normalized == 'marca' ||
          normalized == 'marcas' ||
          normalized == 'brand' ||
          normalized == 'fabricante') {
        continue;
      }

      rows.add(MapEntry(_prettyAttributeName(name), value));
    }

    return rows.take(14).toList();
  }

  String _prettyAttributeName(String value) {
    final clean = value
        .replaceAll('pa_', '')
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .trim();

    if (clean.isEmpty) return value;

    return clean
        .split(RegExp(r'\s+'))
        .map((word) {
      if (word.isEmpty) return word;
      if (word.length <= 3 && word == word.toUpperCase()) return word;
      return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
    })
        .join(' ');
  }

  List<String> _descriptionLines(String text) {
    final expanded = _expandCollapsedTechnicalText(text);
    final result = <String>[];

    for (final raw in expanded.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || _isTechnicalHeading(line)) continue;
      result.addAll(_splitReadableDescriptionLine(line));
    }

    return result.where((e) => e.trim().isNotEmpty).toList();
  }

  List<String> _splitReadableDescriptionLine(String line) {
    final clean = line.trim();
    if (clean.length <= 150 || clean.startsWith('•')) {
      return <String>[clean];
    }

    var working = clean
        .replaceAllMapped(
          RegExp(r'([a-záéíóúñ0-9\)])\.([A-ZÁÉÍÓÚÑ])'),
              (m) => '${m.group(1)}.\n${m.group(2)}',
        )
        .replaceAllMapped(
          RegExp(r'(Protecciones avanzadas:)\s*', caseSensitive: false),
              (m) => '\n${m.group(1)} ',
        )
        .replaceAllMapped(
          RegExp(r'(Funcionamiento robusto:)\s*', caseSensitive: false),
              (m) => '\n${m.group(1)} ',
        );

    final parts = working
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (parts.length <= 1) return <String>[clean];
    return parts;
  }

  void _closeProductStackAndGo(VoidCallback callback) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      callback();
    });
  }

  void _goToQuotesKeepingTabs() {
    final goQuotes = widget.onGoQuotes;
    if (goQuotes != null) {
      _closeProductStackAndGo(goQuotes);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Producto añadido al presupuesto'),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _productWithFreshStock ?? widget.product;
    final precio = _precioDouble(p);
    final precioRegular = _precioRegularDouble(p);
    // La app no muestra precios tachados. El backend debe devolver en price el
    // precio real del cliente/rol; regularPrice queda solo como referencia interna.
    const tieneDescuento = false;
    const descuento = 0;
    const ahorro = 0.0;
    final enStock = p.hasStock;
    final bajoConsulta = p.isUnderConsultation;
    final canViewStockDetails = ref.watch(_canViewStockDetailsProvider).maybeWhen(
      data: (value) => value,
      orElse: () => false,
    );
    final descCorta = _normalizeMultilineText(_limpiarHtml(p.shortDescription));
    final descLimpia = _normalizeMultilineText(_limpiarHtml(p.description));
    final descripcionCompletaRows = _parseKeyValueRows(descLimpia);
    final attributeRows = _attributeRows(p);
    final categoriaVisual = _resolveVisualCategory(p);

    String? marca;
    for (final a in p.attributes) {
      if (a.name.toLowerCase().contains('marca') && a.options.isNotEmpty) {
        marca = a.options.first;
        break;
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: ProfessionalPageAppBar(
        title: categoriaVisual ?? 'DETALLE PRODUCTO',
        subtitle: '',
        icon: Icons.inventory_2_outlined,
        onBack: () => Navigator.pop(context),
      ),
      bottomNavigationBar: _bottomActions(p, enStock),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _refreshProductDetail,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 22),
          children: [
            _imageCard(p),
            const SizedBox(height: 14),
            _productHeader(
              p: p,
              marca: marca,
              precio: precio,
              precioRegular: precioRegular,
              tieneDescuento: tieneDescuento,
              descuento: descuento,
              ahorro: ahorro,
              enStock: enStock,
              bajoConsulta: bajoConsulta,
              canViewStockDetails: canViewStockDetails,
            ),
            const SizedBox(height: 16),
            _trustBlock(),
            const SizedBox(height: 18),
            _buildSectionTitle('INFORMACIÓN TÉCNICA'),
            const SizedBox(height: 12),
            if (descCorta.isNotEmpty) ...[
              _buildShortDescriptionCard(
                descCorta,
                title: 'Características principales',
                icon: Icons.tune_rounded,
              ),
              const SizedBox(height: 12),
            ],
            if (attributeRows.isNotEmpty) ...[
              _buildAttributesCard(attributeRows),
              const SizedBox(height: 12),
            ],
            if (descLimpia.isNotEmpty &&
                descLimpia != 'Sin descripción detallada' &&
                descLimpia != descCorta) ...[
              if (descripcionCompletaRows.isNotEmpty)
                _buildExpandableKeyValueCard(
                  title: 'Ficha técnica detallada',
                  icon: Icons.table_chart_outlined,
                  rows: descripcionCompletaRows,
                )
              else
                _buildExpandableDescription(
                  title: 'Descripción técnica',
                  icon: Icons.article_outlined,
                  text: descLimpia,
                ),
              const SizedBox(height: 18),
            ],
            if (!_cargandoRecomendados && _recomendados.isNotEmpty) ...[
              _buildRecommendedSection(marca),
              const SizedBox(height: 20),
            ],
          ],
        ),
      ),
    );
  }

  Widget _imageCard(Product p) {
    final fullImage = _bestDetailImageUrl(p);
    final fallbackImage = _fallbackDetailImageUrl(p);
    final hasRealImage = p.imageUrl.trim().isNotEmpty &&
        !p.imageUrl.toLowerCase().contains('placeholder');

    return Container(
      width: double.infinity,
      height: 340,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Hero(
              tag: 'prod_${p.id}',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: hasRealImage ? () => _openImagePreview(p) : null,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: CachedNetworkImage(
                      imageUrl: fullImage,
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                      memCacheWidth: 1800,
                      maxWidthDiskCache: 2400,
                      fadeInDuration: const Duration(milliseconds: 120),
                      placeholder: (context, url) => const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      ),
                      errorWidget: (context, url, error) {
                        if (fallbackImage != fullImage && fallbackImage.isNotEmpty) {
                          return CachedNetworkImage(
                            imageUrl: fallbackImage,
                            fit: BoxFit.contain,
                            memCacheWidth: 1200,
                            maxWidthDiskCache: 1800,
                            errorWidget: (context, url, error) => const Icon(
                              Icons.broken_image,
                              size: 60,
                              color: _border,
                            ),
                          );
                        }

                        return const Icon(
                          Icons.broken_image,
                          size: 60,
                          color: _border,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (hasRealImage)
            Positioned(
              right: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.62),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.zoom_out_map_rounded,
                      color: Colors.white,
                      size: 15,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Ampliar',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _productHeader({
    required Product p,
    required String? marca,
    required double precio,
    required double precioRegular,
    required bool tieneDescuento,
    required int descuento,
    required double ahorro,
    required bool enStock,
    required bool bajoConsulta,
    required bool canViewStockDetails,
  }) {
    final marcaText = marca?.trim();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _stockBadge(enStock, bajoConsulta),
              if (marcaText != null && marcaText.isNotEmpty) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _brandTopLabel(marcaText),
                  ),
                ),
              ] else const Spacer(),
            ],
          ),
          if (canViewStockDetails) ...[
            const SizedBox(height: 10),
            _StockDetailsText(
              product: p,
              hasStock: enStock,
            ),
          ],
          if (p.sku.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'REF: ${p.sku}',
              style: const TextStyle(
                fontSize: 12.5,
                color: _muted,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            p.name,
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w900,
              height: 1.12,
              color: _dark,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (tieneDescuento) ...[
                      Text(
                        _formatearPrecio(precioRegular),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF9CA3AF),
                          decoration: TextDecoration.lineThrough,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      _formatearPrecio(precio),
                      style: TextStyle(
                        fontSize: precio > 0 ? 31 : 23,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                        fontFamily: 'Oswald',
                        height: 1,
                      ),
                    ),
                    if (tieneDescuento) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '-$descuento%',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Ahorras ${_formatearPrecio(ahorro)}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF047857),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (p.canAddToCart) _quantityControl(p),
            ],
          ),
        ],
      ),
    );
  }

  Widget _brandTopLabel(String marca) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.verified_outlined,
          size: 16,
          color: AppColors.primary,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: RichText(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              children: [
                const TextSpan(
                  text: 'Marca: ',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: _muted,
                  ),
                ),
                TextSpan(
                  text: marca.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    color: _dark,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _stockBadge(bool enStock, bool bajoConsulta) {
    final bg = bajoConsulta
        ? const Color(0xFFFFF7ED)
        : enStock
        ? const Color(0xFFEAF7EE)
        : const Color(0xFFFDECEC);
    final fg = bajoConsulta
        ? const Color(0xFFC2410C)
        : enStock
        ? const Color(0xFF218047)
        : const Color(0xFFC62828);
    final label = bajoConsulta ? 'Bajo consulta' : enStock ? 'En stock' : 'Sin stock';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: fg,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _quantityControl(Product p) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: _softBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _qtyBtn(Icons.remove_rounded, _cantidad > 1, () {
            if (_cantidad > 1) {
              HapticFeedback.selectionClick();
              setState(() => _cantidad--);
            }
          }),
          SizedBox(
            width: 34,
            child: Text(
              '$_cantidad',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: _dark,
              ),
            ),
          ),
          _qtyBtn(Icons.add_rounded, _canIncreaseQuantity(p), () {
            if (_canIncreaseQuantity(p)) {
              HapticFeedback.selectionClick();
              setState(() => _cantidad++);
            }
          }),
        ],
      ),
    );
  }

  Widget _trustBlock() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _trustItem(Icons.local_shipping_outlined, 'Envío 24-48h'),
          _trustItem(Icons.verified_user_outlined, 'Garantía'),
          _trustItem(Icons.support_agent_rounded, 'Soporte técnico'),
          _trustItem(Icons.business_center_outlined, 'B2B'),
        ],
      ),
    );
  }

  Widget _bottomActions(Product p, bool enStock) {
    final canAddToCart = p.canAddToCart;
    final canAddToQuote = p.canRequestQuote;
    final bajoConsulta = p.isUnderConsultation;

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 18,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: canAddToCart && !_isAddingToCart ? _addToCart : null,
                  icon: _isAddingToCart
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : Icon(
                    canAddToCart ? Icons.shopping_cart_outlined : Icons.block,
                    size: 18,
                  ),
                  label: Text(
                    bajoConsulta
                        ? 'Bajo consulta'
                        : canAddToCart
                        ? 'Añadir carrito'
                        : 'Sin stock',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canAddToCart ? AppColors.primary : Colors.grey.shade400,
                    disabledBackgroundColor: Colors.grey.shade300,
                    disabledForegroundColor: Colors.grey.shade600,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: canAddToQuote && !_isAddingToQuote ? _addToQuote : null,
                  icon: _isAddingToQuote
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : Icon(
                    canAddToQuote ? Icons.description_outlined : Icons.block,
                    size: 18,
                  ),
                  label: Text(
                    _isAddingToQuote
                        ? 'Añadiendo...'
                        : bajoConsulta
                        ? 'No presupuestar'
                        : canAddToQuote
                        ? 'Presupuesto'
                        : 'No presupuestar',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: canAddToQuote ? AppColors.textPrimary : Colors.grey,
                    side: BorderSide(
                      color: canAddToQuote ? const Color(0xFFD9DEE7) : Colors.grey.shade300,
                      width: 1.2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addToCart() async {
    if (!widget.product.canAddToCart || _isAddingToCart) return;
    final qty = _safeQuantity(widget.product);
    if (qty <= 0) return;

    setState(() => _isAddingToCart = true);
    ref.read(cartProvider.notifier).addProduct(widget.product, qty);
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$qty x ${widget.product.name} añadido al carrito'),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
      ),
    );
    if (mounted) setState(() => _isAddingToCart = false);
  }

  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 24,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontFamily: 'Oswald',
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
              color: _dark,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildShortDescriptionCard(
      String text, {
        required String title,
        required IconData icon,
      }) {
    final lines = _descriptionLines(text);
    if (lines.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                    color: _dark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...List.generate(lines.length > 10 ? 10 : lines.length, (index) {
            final rawLine = lines[index];
            final line = rawLine.replaceFirst(RegExp(r'^[•\-–—]+\s*'), '').trim();

            return Padding(
              padding: EdgeInsets.only(
                bottom: index == lines.length - 1 ? 0 : 9,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.only(top: 7),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      line,
                      style: const TextStyle(
                        fontSize: 13.8,
                        color: _dark,
                        height: 1.42,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAttributesCard(List<MapEntry<String, String>> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(Icons.fact_check_outlined, color: AppColors.primary, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Datos técnicos destacados',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14.5,
                      color: _dark,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _border),
              ),
              child: Column(
                children: List.generate(rows.length, (index) {
                  final row = rows[index];
                  final isLast = index == rows.length - 1;

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    decoration: BoxDecoration(
                      color: index.isEven ? Colors.white : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.vertical(
                        top: index == 0 ? const Radius.circular(14) : Radius.zero,
                        bottom: isLast ? const Radius.circular(14) : Radius.zero,
                      ),
                      border: isLast
                          ? null
                          : const Border(
                        bottom: BorderSide(color: _border, width: 1),
                      ),
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 118,
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: Text(
                                row.key,
                                style: const TextStyle(
                                  fontSize: 12.2,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF334155),
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(width: 1, color: _border),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: Text(
                                row.value,
                                style: const TextStyle(
                                  fontSize: 12.8,
                                  fontWeight: FontWeight.w600,
                                  color: _dark,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandableKeyValueCard({
    required String title,
    required IconData icon,
    required List<MapEntry<String, String>> rows,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => setState(() => _descriptionExpanded = !_descriptionExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(icon, color: AppColors.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: _dark,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 200),
                    turns: _descriptionExpanded ? 0.5 : 0,
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: _muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  children: List.generate(rows.length, (index) {
                    final row = rows[index];
                    final isLast = index == rows.length - 1;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: index.isEven ? Colors.white : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.vertical(
                          top: index == 0 ? const Radius.circular(14) : Radius.zero,
                          bottom: isLast ? const Radius.circular(14) : Radius.zero,
                        ),
                        border: isLast
                            ? null
                            : const Border(
                          bottom: BorderSide(color: _border, width: 1),
                        ),
                      ),
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: 118,
                              child: Align(
                                alignment: Alignment.topLeft,
                                child: Text(
                                  row.key,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF334155),
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(width: 1, color: _border),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Align(
                                alignment: Alignment.topLeft,
                                child: Text(
                                  row.value,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: _dark,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
            crossFadeState: _descriptionExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
            sizeCurve: Curves.easeOut,
          ),
        ],
      ),
    );
  }

  Widget _buildExpandableDescription({
    required String title,
    required IconData icon,
    required String text,
  }) {
    final lines = _descriptionLines(text);
    if (lines.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => setState(() => _descriptionExpanded = !_descriptionExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(icon, color: AppColors.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                        color: _dark,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 200),
                    turns: _descriptionExpanded ? 0.5 : 0,
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: _muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(lines.length, (index) {
                  final line = lines[index];
                  final looksLikeBullet =
                      line.startsWith('•') ||
                          line.startsWith('-') ||
                          line.startsWith('–') ||
                          line.startsWith('—');

                  if (looksLikeBullet) {
                    final cleanLine = line
                        .replaceFirst(RegExp(r'^[•\-–—]+\s*'), '')
                        .trim();

                    return Padding(
                      padding: EdgeInsets.only(bottom: index == lines.length - 1 ? 0 : 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            margin: const EdgeInsets.only(top: 8),
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              cleanLine,
                              style: const TextStyle(
                                fontSize: 13.5,
                                color: _dark,
                                height: 1.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final isHeading = line.length <= 42 &&
                      !line.contains('.') &&
                      !line.contains(':') &&
                      index != lines.length - 1;

                  return Padding(
                    padding: EdgeInsets.only(bottom: index == lines.length - 1 ? 0 : 10),
                    child: Text(
                      line,
                      style: TextStyle(
                        fontSize: isHeading ? 14.2 : 13.5,
                        color: isHeading ? _dark : _muted,
                        height: isHeading ? 1.25 : 1.55,
                        fontWeight: isHeading ? FontWeight.w900 : FontWeight.w500,
                      ),
                    ),
                  );
                }),
              ),
            ),
            crossFadeState: _descriptionExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
            sizeCurve: Curves.easeOut,
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendedSection(String? marca) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Productos relacionados',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: _dark,
                ),
              ),
            ),
            Text(
              '${_recomendados.length} productos',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 240,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _recomendados.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final rp = _recomendados[i];
              final precioRp = _precioDouble(rp);
              return SizedBox(
                width: 160,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProductDetailScreen(
                            product: rp,
                            onGoCart: widget.onGoCart,
                            onGoQuotes: widget.onGoQuotes,
                            contextCategoryName: widget.contextCategoryName,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(16),
                            ),
                            child: SizedBox(
                              height: 100,
                              width: double.infinity,
                              child: CachedNetworkImage(
                                imageUrl: rp.imageUrl,
                                fit: BoxFit.contain,
                                memCacheWidth: 500,
                                maxWidthDiskCache: 800,
                                fadeInDuration: const Duration(milliseconds: 120),
                                placeholder: (context, url) => Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primary.withOpacity(0.3),
                                  ),
                                ),
                                errorWidget: (context, url, error) => const Icon(
                                  Icons.broken_image,
                                  size: 40,
                                  color: _border,
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  rp.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    height: 1.2,
                                    fontWeight: FontWeight.w800,
                                    color: _dark,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _formatearPrecio(precioRp),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.primary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  height: 32,
                                  child: ElevatedButton(
                                    onPressed: rp.canAddToCart
                                        ? () {
                                      ref
                                          .read(cartProvider.notifier)
                                          .addProduct(rp, 1);
                                      HapticFeedback.mediumImpact();
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text('${rp.name} añadido'),
                                          backgroundColor: AppColors.primary,
                                          behavior: SnackBarBehavior.floating,
                                          duration: const Duration(seconds: 1),
                                        ),
                                      );
                                    }
                                        : null,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: rp.canAddToCart
                                          ? AppColors.primary
                                          : Colors.grey.shade300,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      padding: EdgeInsets.zero,
                                      disabledBackgroundColor: Colors.grey.shade300,
                                    ),
                                    child: Text(
                                      rp.canAddToCart ? 'Añadir' : (rp.isUnderConsultation ? 'Consulta' : 'Sin stock'),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _trustItem(IconData icon, String label) {
    return Column(
      children: [
        Icon(icon, size: 20, color: _dark),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: _dark,
            height: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _qtyBtn(IconData icon, bool enabled, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: enabled ? onTap : null,
      child: SizedBox(
        width: 36,
        height: 40,
        child: Icon(
          icon,
          size: 18,
          color: enabled ? _dark : const Color(0xFF9CA3AF),
        ),
      ),
    );
  }

  Future<void> _addToQuote() async {
    if (_isAddingToQuote) return;

    final prod = widget.product;
    if (prod.id == 0) return;

    if (!prod.canRequestQuote) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            prod.isUnderConsultation
                ? '"${prod.name}" está bajo consulta y no puede añadirse al presupuesto.'
                : 'No se puede añadir "${prod.name}" al presupuesto porque no hay stock.',
          ),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final qty = _safeQuoteQuantity(prod);
    if (qty <= 0) return;

    final precio = _precioDouble(prod);

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => QuoteSelectionDialog(
        productName: prod.name,
        productId: prod.id,
        price: precio,
        quantity: qty,
      ),
    );

    if (result == null || !mounted) return;

    setState(() => _isAddingToQuote = true);

    try {
      final action = result['action']?.toString() ?? '';
      final notifier = ref.read(localQuotesProvider.notifier);
      String mensaje = '';

      if (action == 'crear_y_anadir') {
        final nombre = result['nombre']?.toString().trim() ?? '';
        final orderId = DateTime.now().millisecondsSinceEpoch.toString();
        final nombreFinal = nombre.isNotEmpty ? nombre : 'Presupuesto #$orderId';

        await notifier.crearPresupuesto(
          orderId: orderId,
          nombre: nombreFinal,
        );

        await notifier.anadirItem(
          orderId: orderId,
          item: LocalQuoteItem(
            productId: prod.id,
            productName: prod.name,
            quantity: qty,
            price: precio,
          ),
        );

        mensaje = '$qty x ${prod.name} añadido a "$nombreFinal"';
      } else if (action == 'anadir_existente') {
        final orderId = result['orderId']?.toString() ?? '';
        final nombre = result['nombre']?.toString() ?? 'presupuesto';

        if (orderId.isEmpty) {
          throw Exception('No se pudo identificar el presupuesto seleccionado.');
        }

        await notifier.anadirItem(
          orderId: orderId,
          item: LocalQuoteItem(
            productId: prod.id,
            productName: prod.name,
            quantity: qty,
            price: precio,
          ),
        );

        mensaje = '$qty x ${prod.name} añadido a "$nombre"';
      }

      if (!mounted) return;

      if (mensaje.isNotEmpty) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(mensaje),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            action: SnackBarAction(
              label: 'VER',
              textColor: Colors.white,
              onPressed: _goToQuotesKeepingTabs,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error en _addToQuote: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAddingToQuote = false);
    }
  }

}

class _StockDetailsText extends StatelessWidget {
  final Product product;
  final bool hasStock;

  const _StockDetailsText({
    required this.product,
    required this.hasStock,
  });

  @override
  Widget build(BuildContext context) {
    final cleanDetails = product.stockDetailsText?.trim();
    if (cleanDetails == null || cleanDetails.isEmpty) {
      return const SizedBox.shrink();
    }

    const textColor = Color(0xFF1565C0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE1E4EA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 15,
            color: textColor,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'Stock: $cleanDetails',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: textColor,
                fontWeight: FontWeight.w900,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}



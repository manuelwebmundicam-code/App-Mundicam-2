import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/producto.dart';
import '../providers/cart_provider.dart';
import '../providers/quote_provider.dart';
import '../services/api_service.dart';
import '../theme.dart';
import 'cart_page.dart';
import 'quotes_page.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  final Product product;
  const ProductDetailScreen({super.key, required this.product});

  @override
  ConsumerState<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  int _cantidad = 1;
  bool _isAddingToCart = false;
  bool _isAddingToQuote = false;
  bool _specsExpanded = true;
  bool _descriptionExpanded = true;
  bool _cargandoRecomendados = true;
  List<Product> _recomendados = [];

  static const Color _dark = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _softBg = Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _cargarRecomendados();
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
          .where((p) => p.id != product.id && p.hasStock)
          .map((p) {
        int score = 0;
        if (marca != null) {
          for (final a in p.attributes) {
            if (a.name.toLowerCase().contains('marca') && a.options.any((o) => o.toLowerCase() == marca!.toLowerCase())) score += 100;
          }
        }
        final pp = double.tryParse(p.price.replaceAll(',', '.').trim()) ?? 0;
        if (precioActual > 0 && pp > 0) {
          final diff = (pp - precioActual).abs() / precioActual;
          if (diff < 0.15) score += 50; else if (diff < 0.30) score += 30; else if (diff < 0.50) score += 10;
        }
        return MapEntry(p, score);
      })
          .where((e) => e.value > 0)
          .toList();
      recomendados.sort((a, b) => b.value.compareTo(a.value));
      List<Product> finales = recomendados.map((e) => e.key).take(8).toList();
      if (finales.length < 4) {
        finales.addAll(todos.where((p) => p.id != product.id && p.hasStock && !finales.any((f) => f.id == p.id)).take(8 - finales.length));
      }
      if (mounted) setState(() { _recomendados = finales; _cargandoRecomendados = false; });
    } catch (e) {
      if (mounted) setState(() => _cargandoRecomendados = false);
    }
  }

  String _limpiarHtml(String t) => t
      .replaceAll(RegExp(r'<br\s*/?>'), '\n')
      .replaceAll(RegExp(r'</?p[^>]*>'), '\n')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  double _precioDouble(Product p) => double.tryParse(p.price.replaceAll(',', '.').trim()) ?? 0;
  double _precioRegularDouble(Product p) => double.tryParse(p.regularPrice.replaceAll(',', '.').trim()) ?? 0;
  String _formatearPrecio(double v) => '${v.toStringAsFixed(2)} €';

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final precio = _precioDouble(p);
    final precioRegular = _precioRegularDouble(p);
    final tieneDescuento = precioRegular > precio && precio > 0;
    final descuento = tieneDescuento ? ((precioRegular - precio) / precioRegular * 100).round() : 0;
    final ahorro = tieneDescuento ? precioRegular - precio : 0.0;
    final enStock = p.hasStock; // ← USA EL GETTER DEL MODELO

    String descLimpia = _limpiarHtml(p.description);

    String? marca;
    for (final a in p.attributes) {
      if (a.name.toLowerCase().contains('marca') && a.options.isNotEmpty) { marca = a.options.first; break; }
    }

    final specRows = <MapEntry<String, String>>[];
    if (marca != null) specRows.add(MapEntry('Marca', marca));
    if (p.sku.isNotEmpty) specRows.add(MapEntry('SKU', p.sku));
    specRows.add(MapEntry('Disponibilidad', enStock ? 'En stock' : 'Sin stock'));
    final tieneEspecificaciones = specRows.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(p.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white), overflow: TextOverflow.ellipsis),
        centerTitle: true,
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          Container(
            width: double.infinity, height: 300,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: _border)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Hero(
                tag: 'prod_${p.id}',
                child: CachedNetworkImage(
                  imageUrl: p.imageUrl, fit: BoxFit.contain,
                  placeholder: (_, __) => const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                  errorWidget: (_, __, ___) => const Icon(Icons.broken_image, size: 60, color: _border),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: (enStock ? Colors.green : Colors.red).withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
              child: Text(enStock ? '● En stock' : '○ Sin stock', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: enStock ? Colors.green.shade700 : Colors.red.shade700)),
            ),
            if (p.sku.isNotEmpty) Text('REF: ${p.sku}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ]),
          const SizedBox(height: 12),
          Text(p.name, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, height: 1.15, color: _dark)),
          if (marca != null) ...[
            const SizedBox(height: 4),
            Text(marca.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[500], letterSpacing: 0.8)),
          ],
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (tieneDescuento) ...[
                  Text(_formatearPrecio(precioRegular), style: const TextStyle(fontSize: 14, color: Color(0xFF9CA3AF), decoration: TextDecoration.lineThrough, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                ],
                Text(_formatearPrecio(precio), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: AppColors.primary, height: 1)),
                if (tieneDescuento) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(4)), child: Text('-$descuento%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.primary))),
                    const SizedBox(width: 8),
                    Text('Ahorras ${_formatearPrecio(ahorro)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF047857))),
                  ]),
                ],
              ]),
            ),
            if (p.hasStock) // ← USA EL GETTER DEL MODELO
              Container(
                height: 40,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999), border: Border.all(color: _border)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _qtyBtn(Icons.remove_rounded, _cantidad > 1, () { if (_cantidad > 1) { HapticFeedback.selectionClick(); setState(() => _cantidad--); } }),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Text('$_cantidad', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: _dark))),
                  _qtyBtn(Icons.add_rounded, _cantidad < p.maxPurchaseQty, () { if (_cantidad < p.maxPurchaseQty) { HapticFeedback.selectionClick(); setState(() => _cantidad++); } }),
                ]),
              ),
          ]),

          // AVISO SIN STOCK
          if (!enStock) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade200)),
              child: Row(children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                const Expanded(child: Text('Producto sin stock. Puedes añadirlo al presupuesto para que te avisemos cuando esté disponible.', style: TextStyle(fontSize: 12, color: Colors.red, height: 1.3))),
              ]),
            ),
          ],
          const SizedBox(height: 16),

          // BOTÓN COMPRAR YA
          SizedBox(
            width: double.infinity, height: 48,
            child: ElevatedButton(
              onPressed: enStock ? () { ref.read(cartProvider.notifier).addProduct(p, _cantidad); Navigator.push(context, MaterialPageRoute(builder: (_) => const CartPage())); } : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: enStock ? AppColors.primary : Colors.grey.shade300,
                foregroundColor: Colors.white, elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                disabledBackgroundColor: Colors.grey.shade300,
              ),
              child: Text(enStock ? 'COMPRAR YA' : 'SIN STOCK', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
            ),
          ),
          const SizedBox(height: 10),

          // AÑADIR AL CARRITO + PRESUPUESTO
          Row(children: [
            Expanded(
              child: SizedBox(height: 44, child: OutlinedButton.icon(
                onPressed: enStock && !_isAddingToCart ? () async {
                  setState(() => _isAddingToCart = true);
                  ref.read(cartProvider.notifier).addProduct(p, _cantidad);
                  HapticFeedback.mediumImpact();
                  if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$_cantidad x ${p.name} añadido al carrito'), backgroundColor: AppColors.primary, behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 1))); setState(() => _isAddingToCart = false); }
                } : null,
                icon: _isAddingToCart ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)) : Icon(enStock ? Icons.shopping_cart_outlined : Icons.block, size: 16),
                label: Text(enStock ? 'AÑADIR AL CARRITO' : 'SIN STOCK', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: enStock ? AppColors.primary : Colors.grey,
                  side: BorderSide(color: enStock ? AppColors.primary : Colors.grey.shade300, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  disabledForegroundColor: Colors.grey,
                ),
              )),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(height: 44, child: OutlinedButton.icon(
                onPressed: _isAddingToQuote ? null : _addToQuote,
                icon: _isAddingToQuote ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)) : const Icon(Icons.description_outlined, size: 16),
                label: Text(_isAddingToQuote ? 'Añadiendo...' : 'PRESUPUESTO', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary, side: BorderSide(color: AppColors.primary.withOpacity(0.5), width: 1.5), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              )),
            ),
          ]),
          const SizedBox(height: 20),

          // CONFIANZA
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            decoration: BoxDecoration(color: _softBg, borderRadius: BorderRadius.circular(16)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _trustItem(Icons.local_shipping_outlined, 'Envío 24-48h'),
              _trustItem(Icons.verified_user_outlined, '2 años garantía'),
              _trustItem(Icons.undo_rounded, '30 días devolución'),
              _trustItem(Icons.lock_outline, 'Pago seguro'),
            ]),
          ),
          const SizedBox(height: 20),

          // ESPECIFICACIONES
          if (tieneEspecificaciones) ...[
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
              child: Column(children: [
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => setState(() => _specsExpanded = !_specsExpanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(children: [
                      Icon(Icons.tune_rounded, color: AppColors.primary, size: 20),
                      const SizedBox(width: 10),
                      const Expanded(child: Text('Especificaciones técnicas', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: _dark))),
                      AnimatedRotation(duration: const Duration(milliseconds: 200), turns: _specsExpanded ? 0.5 : 0, child: const Icon(Icons.keyboard_arrow_down_rounded, color: _muted)),
                    ]),
                  ),
                ),
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        decoration: BoxDecoration(border: Border.all(color: _border), borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          children: List.generate(specRows.length, (i) {
                            final row = specRows[i];
                            return Container(
                              color: i.isEven ? _softBg : Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                SizedBox(width: 105, child: Text(row.key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF475569), height: 1.3))),
                                const SizedBox(width: 8),
                                Expanded(child: Text(row.value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _dark, height: 1.35))),
                              ]),
                            );
                          }),
                        ),
                      ),
                    ),
                  ),
                  crossFadeState: _specsExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 220),
                  sizeCurve: Curves.easeOut,
                ),
              ]),
            ),
            const SizedBox(height: 12),
          ],

          // DESCRIPCIÓN
          if (descLimpia.isNotEmpty && descLimpia != 'Sin descripción detallada') ...[
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
              child: Column(children: [
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => setState(() => _descriptionExpanded = !_descriptionExpanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(children: [
                      Icon(Icons.article_outlined, color: AppColors.primary, size: 20),
                      const SizedBox(width: 10),
                      const Expanded(child: Text('Descripción del producto', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: _dark))),
                      AnimatedRotation(duration: const Duration(milliseconds: 200), turns: _descriptionExpanded ? 0.5 : 0, child: const Icon(Icons.keyboard_arrow_down_rounded, color: _muted)),
                    ]),
                  ),
                ),
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: Text(descLimpia, style: const TextStyle(fontSize: 13.5, color: _muted, height: 1.55))),
                  crossFadeState: _descriptionExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 220),
                  sizeCurve: Curves.easeOut,
                ),
              ]),
            ),
            const SizedBox(height: 18),
          ],

          // RECOMENDADOS
          if (!_cargandoRecomendados && _recomendados.isNotEmpty) ...[
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 4, height: 20, decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(999))),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  marca != null && _recomendados.any((pr) { for (final a in pr.attributes) { if (a.name.toLowerCase().contains('marca') && a.options.any((o) => o.toLowerCase() == marca!.toLowerCase())) return true; } return false; }) ? 'Más de $marca' : 'También te puede interesar',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _dark),
                )),
                Text('${_recomendados.length} productos', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _muted)),
              ]),
              const SizedBox(height: 12),
              SizedBox(height: 240, child: ListView.separated(scrollDirection: Axis.horizontal, physics: const BouncingScrollPhysics(), itemCount: _recomendados.length, separatorBuilder: (_, __) => const SizedBox(width: 10), itemBuilder: (_, i) {
                final rp = _recomendados[i];
                final precioRp = _precioDouble(rp);
                return SizedBox(width: 160, child: Material(color: Colors.transparent, child: InkWell(borderRadius: BorderRadius.circular(16), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(product: rp))), child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Stack(children: [ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(16)), child: SizedBox(height: 100, width: double.infinity, child: CachedNetworkImage(imageUrl: rp.imageUrl, fit: BoxFit.contain, placeholder: (_, __) => Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary.withOpacity(0.3))), errorWidget: (_, __, ___) => const Icon(Icons.broken_image, size: 40, color: _border))))]),
                  Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(rp.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, height: 1.2, fontWeight: FontWeight.w700, color: _dark)),
                    const SizedBox(height: 6),
                    Text(_formatearPrecio(precioRp), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.primary)),
                    const SizedBox(height: 8),
                    SizedBox(width: double.infinity, height: 32, child: ElevatedButton(
                      onPressed: rp.hasStock ? () { ref.read(cartProvider.notifier).addProduct(rp, 1); HapticFeedback.mediumImpact(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${rp.name} añadido'), backgroundColor: AppColors.primary, behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 1))); } : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: rp.hasStock ? AppColors.primary : Colors.grey.shade300,
                        foregroundColor: Colors.white, elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), padding: EdgeInsets.zero,
                        disabledBackgroundColor: Colors.grey.shade300,
                      ),
                      child: Text(rp.hasStock ? 'Añadir' : 'Sin stock', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    )),
                  ])),
                ])))),
                );})),
            ]),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }

  Widget _trustItem(IconData icon, String label) {
    return Column(children: [
      Icon(icon, size: 20, color: _dark),
      const SizedBox(height: 6),
      Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _dark, height: 1.2)),
    ]);
  }

  Widget _qtyBtn(IconData icon, bool enabled, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: enabled ? onTap : null,
      child: SizedBox(width: 36, height: 40, child: Icon(icon, size: 18, color: enabled ? _dark : const Color(0xFF9CA3AF))),
    );
  }

  Future<void> _addToQuote() async {
    setState(() => _isAddingToQuote = true);
    try {
      final api = ref.read(apiServiceProvider);
      final user = FirebaseAuth.instance.currentUser;

      String? email;
      if (user != null) {
        try {
          final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
          if (userDoc.exists && userDoc.data() != null) { email = userDoc.get('email') as String?; }
        } catch (e) { debugPrint('Error al leer email de Firestore: $e'); }
      }
      email ??= user?.email;
      email ??= user?.providerData.firstOrNull?.email;

      if (email == null || email.isEmpty) {
        if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No se pudo obtener tu email."), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating, duration: Duration(seconds: 3))); }
        return;
      }

      final prod = widget.product;
      final precio = _precioDouble(prod);
      if (prod.id == 0) throw Exception("ID inválido");
      await api.crearPresupuesto(email: email, productId: prod.id, productName: prod.name, price: precio, quantity: _cantidad);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("$_cantidad x ${prod.name} añadido al presupuesto"),
          backgroundColor: AppColors.primary, behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2),
          action: SnackBarAction(label: 'VER', textColor: Colors.white, onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QuotesPage()))),
        ));
      }
      ref.invalidate(quotesProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _isAddingToQuote = false);
    }
  }
}
import 'dart:async';

import 'package:mundicam/pages/producto_detalles_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/catalog/data/models/producto.dart';
import '../providers/products_paginated_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/quote_provider.dart';
import '../providers/filter_provider.dart';
import '../services/firebase_service.dart';
import '../services/image_cache_service.dart';
import '../widgets/filtro_selector.dart';
import '../theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'cart_page.dart';

class ProductosPorCategoriaScreen extends ConsumerStatefulWidget {
  final int categoryId;
  final String categoryName;

  const ProductosPorCategoriaScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
  });

  @override
  ConsumerState<ProductosPorCategoriaScreen> createState() =>
      _ProductosPorCategoriaScreenState();
}

class _ProductosPorCategoriaScreenState
    extends ConsumerState<ProductosPorCategoriaScreen> {
  final FirebaseService _firebase = FirebaseService();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();

  Timer? _scrollTimer;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScrollThrottled);
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScrollThrottled() {
    if (_scrollTimer?.isActive ?? false) return;

    _scrollTimer = Timer(const Duration(milliseconds: 100), () {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 300) {
        final notifier = ref.read(
          productsPaginatedProvider(widget.categoryId).notifier,
        );
        if (!notifier.isLoading && notifier.hasMore && !_isLoadingMore) {
          _isLoadingMore = true;
          notifier.loadNextPage().then((_) {
            _isLoadingMore = false;
          });
        }
      }
    });
  }

  void _onFiltersChanged() {
    ref.read(productsPaginatedProvider(widget.categoryId).notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(productFilterProvider, (previous, next) {
      if (previous != next) {
        _onFiltersChanged();
      }
    });

    final productosState = ref.watch(
      productsPaginatedProvider(widget.categoryId),
    );
    final notifier = ref.watch(
      productsPaginatedProvider(widget.categoryId).notifier,
    );

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF2F2F2),
      endDrawer: FiltroSelector(
        parentCategoryId: widget.categoryId,
        categoryName: widget.categoryName,
        productosEnPantalla: productosState,
      ),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.categoryName),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_alt_outlined),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
        ],
      ),
      body: RepaintBoundary(
        child: productosState.isEmpty && !notifier.isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.search_off, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      'No hay productos con estos filtros',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () =>
                          ref.read(productFilterProvider.notifier).reset(),
                      icon: const Icon(Icons.refresh),
                      label: const Text("Limpiar filtros"),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: productosState.length + (notifier.hasMore ? 1 : 0),
                addAutomaticKeepAlives: true,
                addRepaintBoundaries: true,
                itemBuilder: (context, index) {
                  if (index == productosState.length) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(
                        child: SizedBox(
                          height: 30,
                          width: 30,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    );
                  }

                  return ProductTile(
                    key: ValueKey(productosState[index].id),
                    p: productosState[index],
                    firebase: _firebase,
                  );
                },
              ),
      ),
    );
  }
}

class ProductTile extends ConsumerStatefulWidget {
  final Product p;
  final FirebaseService firebase;

  const ProductTile({super.key, required this.p, required this.firebase});

  @override
  ConsumerState<ProductTile> createState() => _ProductTileState();
}

class _ProductTileState extends ConsumerState<ProductTile> {
  int cantidad = 1;
  bool _isAddingToQuote = false;

  double _precioDouble(Product p) =>
      double.tryParse(p.price.replaceAll(',', '.').trim()) ?? 0;

  String _formatearPrecioCompleto(double precio) {
    final parts = precio.toStringAsFixed(2).split('.');
    final enteros = parts[0];
    final decimales = parts.length > 1 ? parts[1] : '00';
    final buffer = StringBuffer();
    for (int i = 0; i < enteros.length; i++) {
      if (i > 0 && (enteros.length - i) % 3 == 0) buffer.write('.');
      buffer.write(enteros[i]);
    }
    return '${buffer.toString()},$decimales €';
  }

  @override
  void initState() {
    super.initState();
  }

  // ================================================================
  // LÓGICA DE STOCK (SOLO BINARIO)
  // ================================================================
  bool get _tieneStock => widget.p.isInstock;
  bool get _puedeComprar => _tieneStock && cantidad > 0;

  void _aumentarCantidad() {
    if (!_tieneStock) return;
    setState(() => cantidad++);
  }

  @override
  Widget build(BuildContext context) {
    final precio = _precioDouble(widget.p);

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        color: Colors.white,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        ProductDetailScreen(product: widget.p),
                  ),
                );
              },
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Hero(
                    tag: 'prod_${widget.p.id}',
                    child: ProductImage(p: widget.p, firebase: widget.firebase),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.p.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              _tieneStock ? "● Disponible" : "○ Sin stock",
                              style: TextStyle(
                                fontSize: 11,
                                color: _tieneStock ? Colors.green : Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.p.shortDescription ??
                              "Sin descripción disponible",
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            _formatearPrecioCompleto(precio),
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

            // COMPRAR YA + Selector cantidad
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: ElevatedButton(
                      onPressed: _puedeComprar
                          ? () {
                              ref
                                  .read(cartProvider.notifier)
                                  .addProduct(widget.p, cantidad);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const CartPage(),
                                ),
                              );
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _tieneStock
                            ? AppColors.primary
                            : Colors.grey.shade400,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 0),
                      ),
                      child: Text(
                        _tieneStock ? "COMPRAR YA" : "SIN STOCK",
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
                    opacity: _tieneStock ? 1.0 : 0.5,
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _qtyBtn(Icons.remove, _tieneStock, () {
                            if (cantidad > 1) setState(() => cantidad--);
                          }),
                          Text(
                            "$cantidad",
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: _tieneStock ? Colors.black : Colors.grey,
                            ),
                          ),
                          _qtyBtn(
                            Icons.add,
                            _tieneStock,
                            _aumentarCantidad,
                            isPrimary: _tieneStock,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // AÑADIR AL CARRITO + PRESUPUESTO
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: OutlinedButton(
                      onPressed: _puedeComprar
                          ? () {
                              ref
                                  .read(cartProvider.notifier)
                                  .addProduct(widget.p, cantidad);
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    "${widget.p.name} añadido al carrito",
                                  ),
                                  backgroundColor: AppColors.primary,
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            }
                          : null,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: _tieneStock
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
                        _tieneStock ? "AÑADIR AL CARRITO" : "SIN STOCK",
                        style: TextStyle(
                          fontSize: 10,
                          color: _tieneStock
                              ? AppColors.primary
                              : Colors.grey.shade400,
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
                      onPressed: (_tieneStock && !_isAddingToQuote)
                          ? () => _addToQuote(widget.p)
                          : null,
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
                              color: _tieneStock
                                  ? Colors.orange.shade700
                                  : Colors.grey.shade400,
                            ),
                      label: Text(
                        _isAddingToQuote
                            ? "..."
                            : (_tieneStock ? "PRESUPUESTO" : "SIN STOCK"),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _tieneStock
                              ? Colors.orange.shade700
                              : Colors.grey.shade400,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _tieneStock
                            ? Colors.orange.shade700
                            : Colors.grey.shade400,
                        side: BorderSide(
                          color: _tieneStock
                              ? Colors.orange.shade700
                              : Colors.grey.shade400,
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
      ),
    );
  }

  Widget _qtyBtn(
    IconData icon,
    bool enabled,
    VoidCallback onTap, {
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
    setState(() => _isAddingToQuote = true);
    try {
      final apiService = ref.read(apiServiceProvider);
      final user = FirebaseAuth.instance.currentUser;

      String? email;
      if (user != null) {
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
          if (userDoc.exists && userDoc.data() != null) {
            email = userDoc.get('email') as String?;
          }
        } catch (e) {
          debugPrint('Error al leer email de Firestore: $e');
        }
      }
      email ??= user?.email ?? user?.providerData.firstOrNull?.email;

      if (email == null || email.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "No se pudo obtener tu email. Contacta con soporte.",
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      final precioDouble =
          double.tryParse(product.price.replaceAll(',', '.').trim()) ?? 0.0;
      if (product.id == 0) throw Exception("ID de producto no válido");

      await apiService.crearPresupuesto(
        email: email,
        productId: product.id,
        productName: product.name,
        price: precioDouble,
        quantity: cantidad,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("$cantidad x ${product.name} añadido al presupuesto"),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      ref.invalidate(quotesProvider);
    } catch (e) {
      debugPrint('❌ Error en _addToQuote: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: $e"),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAddingToQuote = false);
    }
  }
}

class ProductImage extends StatelessWidget {
  final Product p;
  final FirebaseService firebase;

  const ProductImage({super.key, required this.p, required this.firebase});

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
          cacheManager: ImageCacheService.cacheManager,
          memCacheWidth: 160,
          memCacheHeight: 160,
          cacheKey: p.imageUrl,
          placeholder: (_, __) => Container(color: Colors.grey[100]),
          errorWidget: (_, __, ___) =>
              const Icon(Icons.broken_image, color: Colors.grey, size: 30),
          fadeOutDuration: const Duration(milliseconds: 150),
          fadeInDuration: const Duration(milliseconds: 150),
        ),
      ),
    );
  }
}

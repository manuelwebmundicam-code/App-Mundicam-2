import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mundicam/core/cache/image_cache_service.dart';
import 'package:mundicam/core/firebase/firebase_service.dart';
import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/features/cart/presentation/providers/cart_provider.dart';
import 'package:mundicam/features/catalog/data/models/producto.dart';
import 'package:mundicam/features/catalog/presentation/pages/producto_detalles_page.dart';
import 'package:mundicam/features/catalog/presentation/providers/filter_provider.dart';
import 'package:mundicam/features/catalog/presentation/providers/products_paginated_provider.dart';
import 'package:mundicam/features/catalog/presentation/widgets/filtro_selector.dart';
import 'package:mundicam/features/quotes/presentation/providers/quote_provider.dart';
import 'package:mundicam/shared/theme/app_theme.dart';

class ProductosPorCategoriaScreen extends ConsumerStatefulWidget {
  final int categoryId;
  final String categoryName;
  final VoidCallback? onGoCart;
  final VoidCallback? onGoQuotes;

  const ProductosPorCategoriaScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
    this.onGoCart,
    this.onGoQuotes,
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
      if (!_scrollController.hasClients) return;

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
              const Icon(
                Icons.search_off,
                size: 64,
                color: Colors.grey,
              ),
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
                label: const Text('Limpiar filtros'),
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
              onGoCart: widget.onGoCart,
              onGoQuotes: widget.onGoQuotes,
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
  final VoidCallback? onGoCart;
  final VoidCallback? onGoQuotes;

  const ProductTile({
    super.key,
    required this.p,
    required this.firebase,
    this.onGoCart,
    this.onGoQuotes,
  });

  @override
  ConsumerState<ProductTile> createState() => _ProductTileState();
}

class _ProductTileState extends ConsumerState<ProductTile> {
  int cantidad = 1;
  bool _isAddingToQuote = false;

  double _precioDouble(Product p) {
    return double.tryParse(p.price.replaceAll(',', '.').trim()) ?? 0;
  }

  String _formatearPrecioCompleto(double precio) {
    if (precio <= 0) {
      return 'Bajo consulta';
    }

    final parts = precio.toStringAsFixed(2).split('.');
    final enteros = parts[0];
    final decimales = parts.length > 1 ? parts[1] : '00';

    final buffer = StringBuffer();

    for (int i = 0; i < enteros.length; i++) {
      if (i > 0 && (enteros.length - i) % 3 == 0) {
        buffer.write('.');
      }

      buffer.write(enteros[i]);
    }

    return '${buffer.toString()},$decimales €';
  }

  bool get _tieneStock => widget.p.isInstock;
  bool get _puedeComprar => _tieneStock && cantidad > 0;

  void _aumentarCantidad() {
    if (!_tieneStock) return;

    setState(() {
      cantidad++;
    });
  }

  void _goToCartKeepingTabs() {
    if (widget.onGoCart != null) {
      debugPrint('✅ onGoCart recibido en ProductTile. Cambiando a Carrito...');
      widget.onGoCart!();
      return;
    }

    debugPrint('❌ onGoCart es NULL en ProductTile');

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$cantidad x ${widget.p.name} añadido al carrito'),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _goToQuotesKeepingTabs() {
    if (widget.onGoQuotes != null) {
      debugPrint('✅ onGoQuotes recibido en ProductTile. Cambiando a Presupuestos...');
      widget.onGoQuotes!();
      return;
    }

    debugPrint('❌ onGoQuotes es NULL en ProductTile');

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Producto añadido al presupuesto'),
        backgroundColor: AppColors.primary,
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<String?> _getCurrentUserEmail() async {
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
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => ProductDetailScreen(
                      product: widget.p,
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
                    tag: 'prod_${widget.p.id}',
                    child: ProductImage(
                      p: widget.p,
                      firebase: widget.firebase,
                    ),
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
                        Text(
                          _tieneStock ? '● Disponible' : '○ Sin stock',
                          style: TextStyle(
                            fontSize: 11,
                            color: _tieneStock ? Colors.green : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.p.shortDescription.isNotEmpty
                              ? widget.p.shortDescription
                              : 'Sin descripción disponible',
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

                        _goToCartKeepingTabs();
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
                        _tieneStock ? 'COMPRAR YA' : 'SIN STOCK',
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
                            if (cantidad > 1) {
                              setState(() {
                                cantidad--;
                              });
                            }
                          }),
                          Text(
                            '$cantidad',
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
                              '$cantidad x ${widget.p.name} añadido al carrito',
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
                        _tieneStock ? 'AÑADIR AL CARRITO' : 'SIN STOCK',
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
                      onPressed: _isAddingToQuote
                          ? null
                          : () => _addToQuote(widget.p),
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
    if (_isAddingToQuote) return;

    setState(() {
      _isAddingToQuote = true;
    });

    try {
      final apiService = ApiService();
      final email = await _getCurrentUserEmail();

      if (email == null || email.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudo obtener tu email.'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }

        return;
      }

      if (product.id == 0) {
        throw Exception('ID de producto no válido.');
      }

      final precioDouble =
          double.tryParse(product.price.replaceAll(',', '.').trim()) ?? 0.0;

      final ok = await apiService.crearPresupuesto(
        email: email,
        productId: product.id,
        productName: product.name,
        price: precioDouble,
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
          content: Text(
            '$cantidad x ${product.name} añadido al presupuesto',
          ),
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
    } catch (e) {
      debugPrint('❌ Error en _addToQuote: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
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

class ProductImage extends StatelessWidget {
  final Product p;
  final FirebaseService firebase;

  const ProductImage({
    super.key,
    required this.p,
    required this.firebase,
  });

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
          errorWidget: (_, __, ___) => const Icon(
            Icons.broken_image,
            color: Colors.grey,
            size: 30,
          ),
          fadeOutDuration: const Duration(milliseconds: 150),
          fadeInDuration: const Duration(milliseconds: 150),
        ),
      ),
    );
  }
}
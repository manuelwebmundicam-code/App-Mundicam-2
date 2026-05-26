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
  ConsumerState<ProductosPorCategoriaScreen> createState() => _ProductosPorCategoriaScreenState();
}

class _ProductosPorCategoriaScreenState extends ConsumerState<ProductosPorCategoriaScreen> {
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
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 300) {
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
      backgroundColor: const Color(0xFFF5F6F8),
      endDrawer: FiltroSelector(
        parentCategoryId: widget.categoryId,
        categoryName: widget.categoryName,
        productosEnPantalla: productosState,
      ),
      appBar: _CatalogCategoryAppBar(
        title: widget.categoryName,
        onBack: () => Navigator.of(context).pop(),
        onFilters: () => _scaffoldKey.currentState?.openEndDrawer(),
      ),
      body: RepaintBoundary(
        child: productosState.isEmpty && !notifier.isLoading
            ? _EmptyProductsState(
          onReset: () => ref.read(productFilterProvider.notifier).reset(),
        )
            : ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
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
              categoryName: widget.categoryName,
              onGoCart: widget.onGoCart,
              onGoQuotes: widget.onGoQuotes,
            );
          },
        ),
      ),
    );
  }
}

class _CatalogCategoryAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback onBack;
  final VoidCallback onFilters;

  const _CatalogCategoryAppBar({
    required this.title,
    required this.onBack,
    required this.onFilters,
  });

  @override
  Size get preferredSize => const Size.fromHeight(86);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(30),
            bottomRight: Radius.circular(30),
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 86,
            child: Row(
              children: [
                const SizedBox(width: 4),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: onBack,
                    tooltip: 'Volver',
                    splashRadius: 22,
                  ),
                ),
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      letterSpacing: 1.05,
                      color: Colors.white,
                      fontFamily: 'Oswald',
                      height: 1.05,
                    ),
                  ),
                ),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton(
                    icon: const Icon(
                      Icons.tune_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    onPressed: onFilters,
                    tooltip: 'Filtros',
                    splashRadius: 22,
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyProductsState extends StatelessWidget {
  final VoidCallback onReset;

  const _EmptyProductsState({required this.onReset});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 112,
              height: 112,
              decoration: const BoxDecoration(
                color: Color(0xFFF8EAEA),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.search_off_rounded,
                size: 54,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'No hay productos con estos filtros',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Oswald',
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Prueba a limpiar la selección o cambiar la marca aplicada.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Limpiar filtros'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProductTile extends ConsumerStatefulWidget {
  final Product p;
  final FirebaseService firebase;
  final String? categoryName;
  final VoidCallback? onGoCart;
  final VoidCallback? onGoQuotes;

  const ProductTile({
    super.key,
    required this.p,
    required this.firebase,
    this.categoryName,
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
    if (precio <= 0) return 'Bajo consulta';
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

  void _goToQuotesKeepingTabs() {
    if (widget.onGoQuotes != null) {
      widget.onGoQuotes!();
      return;
    }
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
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => ProductDetailScreen(
                        product: widget.p,
                        onGoCart: widget.onGoCart,
                        onGoQuotes: widget.onGoQuotes,
                        contextCategoryName: widget.categoryName,
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
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  widget.p.name,
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
                              _stockChip(),
                            ],
                          ),
                          if (widget.p.shortDescription.trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              widget.p.shortDescription,
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
                            _formatearPrecioCompleto(precio),
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
                  _quantitySelector(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: ElevatedButton.icon(
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
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                            : null,
                        icon: Icon(
                          _tieneStock ? Icons.shopping_cart_outlined : Icons.block_rounded,
                          size: 17,
                          color: Colors.white,
                        ),
                        label: Text(
                          _tieneStock ? 'AÑADIR CARRITO' : 'SIN STOCK',
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
                          backgroundColor: _tieneStock ? AppColors.primary : Colors.grey.shade400,
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
                  onPressed: _isAddingToQuote ? null : () => _addToQuote(widget.p),
                  icon: _isAddingToQuote
                      ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                      : const Icon(Icons.description_outlined, size: 17),
                  label: Text(
                    _isAddingToQuote ? 'AÑADIENDO...' : 'AÑADIR AL PRESUPUESTO',
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
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.textPrimary,
                    disabledForegroundColor: Colors.grey.shade500,
                    side: const BorderSide(
                      color: Color(0xFFD9DEE7),
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
      ),
    );
  }

  Widget _quantitySelector() {
    return Opacity(
      opacity: _tieneStock ? 1.0 : 0.55,
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
            _qtyBtn(Icons.remove, _tieneStock, () {
              if (cantidad > 1) {
                setState(() => cantidad--);
              }
            }),
            SizedBox(
              width: 34,
              child: Text(
                '$cantidad',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: _tieneStock ? AppColors.textPrimary : Colors.grey,
                ),
              ),
            ),
            _qtyBtn(
              Icons.add,
              _tieneStock,
                  () => setState(() => cantidad++),
              isPrimary: _tieneStock,
            ),
          ],
        ),
      ),
    );
  }

  Widget _stockChip() {
    final Color bgColor = _tieneStock ? const Color(0xFFEAF7EE) : const Color(0xFFFDECEC);
    final Color textColor = _tieneStock ? const Color(0xFF218047) : const Color(0xFFC62828);
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
            _tieneStock ? 'En stock' : 'Sin stock',
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
      IconData icon,
      bool enabled,
      VoidCallback onTap, {
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

      final precioDouble = double.tryParse(product.price.replaceAll(',', '.').trim()) ?? 0.0;

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
          cacheManager: ImageCacheService.cacheManager,
          memCacheWidth: 192,
          memCacheHeight: 192,
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
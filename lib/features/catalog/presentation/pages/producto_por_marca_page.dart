import 'package:flutter/material.dart';

import 'package:mundicam/core/firebase/firebase_service.dart';
import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/features/catalog/data/models/producto.dart';
import 'package:mundicam/features/catalog/presentation/pages/productos_por_categoria.dart';
import 'package:mundicam/shared/theme/app_theme.dart';
import 'package:mundicam/shared/widgets/professional_page_app_bar.dart';

class ProductoPorMarca extends StatefulWidget {
  final String brandName;
  final VoidCallback? onGoCart;
  final VoidCallback? onGoQuotes;

  const ProductoPorMarca({
    super.key,
    required this.brandName,
    this.onGoCart,
    this.onGoQuotes,
  });

  @override
  State<ProductoPorMarca> createState() => _ProductoPorMarcaState();
}

class _ProductoPorMarcaState extends State<ProductoPorMarca> {
  final ApiService _apiService = ApiService();
  final FirebaseService _firebase = FirebaseService();

  static const int _pageSize = 15;
  final ScrollController _scrollController = ScrollController();
  late Future<CatalogProductsResult> _productosFuture;
  final List<Product> _productos = <Product>[];
  int? _brandId;
  int _generation = 0;
  int _currentPage = 1;
  bool _hasMore = false;
  bool _loadingMore = false;


  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _productosFuture = _loadProductosMarca(_generation);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loadingMore || !_hasMore) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 250) {
      _loadNextPage();
    }
  }

  Future<CatalogProductsResult> _loadProductosMarca(int generation) async {
    final brandId = await _apiService.getMarcaIdPorNombre(widget.brandName);
    final result = await _apiService.getProductosCatalogoFiltrado(
      brandId: brandId,
      brandName: widget.brandName,
      page: 1,
      perPage: _pageSize,
    );
    if (mounted && generation == _generation) {
      _brandId = brandId;
      _productos
        ..clear()
        ..addAll(result.products);
      _currentPage = result.currentPage;
      _hasMore = result.hasNextPage && result.products.isNotEmpty;
    }
    return result;
  }

  Future<void> _loadNextPage() async {
    if (_loadingMore || !_hasMore) return;
    final generation = _generation;
    final nextPage = _currentPage + 1;
    setState(() => _loadingMore = true);
    try {
      final result = await _apiService.getProductosCatalogoFiltrado(
        brandId: _brandId,
        brandName: widget.brandName,
        page: nextPage,
        perPage: _pageSize,
      );
      if (!mounted || generation != _generation) return;
      final ids = _productos.map((product) => product.id).toSet();
      setState(() {
        for (final product in result.products) {
          if (ids.add(product.id)) _productos.add(product);
        }
        _currentPage = nextPage;
        _hasMore = result.hasNextPage && result.products.isNotEmpty;
      });
    } catch (_) {
      // Conservamos lo ya mostrado y permitimos reintentar desde el pie de lista.
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Future<void> _refreshProductos() async {
    setState(() {
      _generation++;
      _brandId = null;
      _currentPage = 1;
      _hasMore = false;
      _loadingMore = false;
      _productos.clear();
      _productosFuture = _loadProductosMarca(_generation);
    });
    await _productosFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: ProfessionalPageAppBar(
        title: widget.brandName.toUpperCase(),
        subtitle: '',
        icon: Icons.local_offer_outlined,
        onBack: () => Navigator.of(context).pop(),
        onRefresh: _refreshProductos,
      ),
      body: FutureBuilder<CatalogProductsResult>(
        future: _productosFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 56,
                      color: Colors.redAccent,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Error al cargar la marca',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 18),
                    OutlinedButton.icon(
                      onPressed: _refreshProductos,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Reintentar'),
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

          final productos = _productos;

          if (productos.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.search_off_rounded,
                      size: 64,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No hay productos disponibles de ${widget.brandName}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _refreshProductos,
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: productos.length + (_hasMore || _loadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == productos.length) {
                  return Center(
                    child: _loadingMore
                        ? const Padding(
                            padding: EdgeInsets.all(18),
                            child: CircularProgressIndicator(color: AppColors.primary),
                          )
                        : TextButton(
                            onPressed: _loadNextPage,
                            child: const Text('Cargar más productos'),
                          ),
                  );
                }
                return ProductTile(
                  key: ValueKey(productos[index].id),
                  p: productos[index],
                  firebase: _firebase,
                  categoryName: widget.brandName,
                  onGoCart: widget.onGoCart,
                  onGoQuotes: widget.onGoQuotes,
                );
              },
            ),
          );
        },
      ),
    );
  }
}
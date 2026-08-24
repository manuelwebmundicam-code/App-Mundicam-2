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

  late Future<List<Product>> _productosFuture;

  @override
  void initState() {
    super.initState();
    _productosFuture = _loadProductosMarca();
  }

  Future<List<Product>> _loadProductosMarca() async {
    final brandId = await _apiService.getMarcaIdPorNombre(widget.brandName);
    final result = await _apiService.getProductosCatalogoFiltrado(
      brandId: brandId,
      brandName: widget.brandName,
      page: 1,
      perPage: 50,
    );
    return result.products;
  }

  Future<void> _refreshProductos() async {
    setState(() {
      _productosFuture = _loadProductosMarca();
    });
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
      body: FutureBuilder<List<Product>>(
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

          final productos = snapshot.data ?? <Product>[];

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
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: productos.length,
              itemBuilder: (context, index) {
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
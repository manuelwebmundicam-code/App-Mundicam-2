import 'package:mundicam/features/catalog/presentation/pages/productos_por_categoria.dart';
import 'package:flutter/material.dart';
import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/features/catalog/data/models/producto.dart';
import 'package:mundicam/core/firebase/firebase_service.dart';

class ProductoPorMarca extends StatefulWidget {
  final String brandName;

  const ProductoPorMarca({super.key, required this.brandName});

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
    // Utilizamos tu buscador existente pasando el nombre de la marca
    _productosFuture = _apiService.buscarProductos(widget.brandName);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      appBar: AppBar(
        title: Text(widget.brandName.toUpperCase()),
        centerTitle: true,
      ),
      body: FutureBuilder<List<Product>>(
        future: _productosFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: theme.primaryColor),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text("Error al cargar la marca: ${snapshot.error}"),
            );
          }

          final productos = snapshot.data ?? [];

          if (productos.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.search_off, size: 60, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    "No hay productos disponibles de ${widget.brandName}",
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: productos.length,
            itemBuilder: (context, index) {
              // Reutilizamos tu ProductTile público
              return ProductTile(p: productos[index], firebase: _firebase);
            },
          );
        },
      ),
    );
  }
}

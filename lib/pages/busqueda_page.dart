import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/producto.dart';
import '../providers/products_provider.dart';
import '../services/firebase_service.dart';
import 'productos_por_categoria.dart'; // Asegúrate de que este import es correcto
import '../theme.dart';

class BusquedaResultadosPage extends ConsumerWidget {
  final String query;

  const BusquedaResultadosPage({super.key, required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchAsync = ref.watch(searchProductsProvider(query));
    final FirebaseService firebase = FirebaseService();

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Resultados: "$query"',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
      ),
      body: searchAsync.when(
        loading: () => const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppColors.primary),
              SizedBox(height: 16),
              Text("Buscando productos...", style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 60, color: Colors.red),
                const SizedBox(height: 16),
                Text('Error en la búsqueda:\n$error', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref.invalidate(searchProductsProvider(query)),
                  child: const Text("Reintentar"),
                ),
              ],
            ),
          ),
        ),
        data: (productos) {
          if (productos.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.search_off_rounded, size: 90, color: Colors.grey[350]),
                    const SizedBox(height: 20),
                    Text(
                      'No encontramos "$query"',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Prueba con:\n• Palabras más generales\n• Sinónimos o marcas\n• Revisa la ortografía',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.grey, height: 1.5),
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text("Volver a buscar"),
                    ),
                  ],
                ),
              ),
            );
          }

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                color: Colors.white,
                child: Row(
                  children: [
                    Icon(Icons.search_rounded, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Text(
                      '${productos.length} producto${productos.length != 1 ? 's' : ''} encontrados',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey[700]),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: productos.length,
                  itemBuilder: (context, index) {
                    return ProductTile(
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
}
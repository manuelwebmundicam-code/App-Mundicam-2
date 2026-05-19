import 'package:flutter/material.dart';
import '../theme.dart';

// ---------------------------------------------------------
// MODELO: SUBCATEGORÍA CCTV
// ---------------------------------------------------------
class SubcategoriaCCTV {
  final String titulo;
  final List<String> items;

  const SubcategoriaCCTV({required this.titulo, required this.items});
}

// ---------------------------------------------------------
// DATOS DE EJEMPLO (ESTÁTICOS)
// ---------------------------------------------------------
class DataCCTV {
  static const List<SubcategoriaCCTV> categorias = [
    SubcategoriaCCTV(
      titulo: "Cámaras HD",
      items: [
        "Cámaras Minidomo HD",
        "Cámaras Turret HD",
        "Cámaras Bullet HD",
        "Domos Motorizados PTZ HD",
        "Cámaras Camufladas HD",
        "Cámaras Fisheye 360º",
        "Cámaras Panorámicas",
        "Cámaras Miniatura HD",
        "Cámaras Térmicas HD",
      ],
    ),
    SubcategoriaCCTV(
      titulo: "Kits CCTV",
      items: [
        "KITS CCTV BASIC 4CH-8CH-16CH",
        "KITS CCTV MASTER 4CH-8CH-16CH",
        "KITS CCTV ELITE 4CH-8CH-16CH",
      ],
    ),
    SubcategoriaCCTV(
      titulo: "Grabadores HD",
      items: [
        "Grabadores XVR HD 4CH",
        "Grabadores XVR HD 8CH",
        "Grabadores XVR HD 16CH",
        "Grabadores XVR HD 32CH",
        "Grabadores XVR HD 64CH",
        "Grabadores XVR HD 128CH",
        "Grabadores XVR HD Vehículos",
      ],
    ),
    SubcategoriaCCTV(
      titulo: "Accesorios CCTV",
      items: [
        "Alimentación",
        "Conectores",
        "Video por UTP",
        "Cable",
        "Discos Duros",
        "Teclados PTZ",
        "Cajas",
        "Soportes",
        "Resto Accesorios",
      ],
    ),
  ];
}

// ---------------------------------------------------------
// PÁGINA: SUBCATEGORÍAS CCTV
// ---------------------------------------------------------
class SubCategoriasCCTVPage extends StatelessWidget {
  const SubCategoriasCCTVPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Subcategorías CCTV"),
        backgroundColor: AppColors.primary,
        centerTitle: true,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: DataCCTV.categorias.length,
        separatorBuilder: (_, __) => const SizedBox(height: 20),
        itemBuilder: (context, index) =>
            _buildCategoryCard(DataCCTV.categorias[index]),
      ),
    );
  }

  /// Construye la tarjeta de cada grupo de subcategorías
  Widget _buildCategoryCard(SubcategoriaCCTV subCat) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subCat.titulo,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            ...subCat.items.map((item) => _buildItemRow(item)).toList(),
          ],
        ),
      ),
    );
  }

  /// Construye cada fila de item dentro de la tarjeta
  Widget _buildItemRow(String item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.arrow_right, size: 20, color: AppColors.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              item,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

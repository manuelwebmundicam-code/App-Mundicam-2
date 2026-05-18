import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../pages/producto_por_marca_page.dart';

class BrandsBanner extends StatefulWidget {
  const BrandsBanner({super.key});

  @override
  State<BrandsBanner> createState() => _BrandsBannerState();
}

class _BrandsBannerState extends State<BrandsBanner> {
  final ScrollController _scrollController = ScrollController();
  Timer? _timer;
  bool _isUserInteracting = false;

  final List<Map<String, String>> _logos = [
    {"img": "assets/brands/AJAX.png", "name": "Ajax"},
    {"img": "assets/brands/ANVIZ.png", "name": "Anviz"},
    {"img": "assets/brands/ASSAABLOY.png", "name": "Assa Abloy"},
    {"img": "assets/brands/DAHUA.png", "name": "Dahua"},
    {"img": "assets/brands/DJI.png", "name": "DJI"},
    {"img": "assets/brands/EVOLVE.png", "name": "Evolve"},
    {"img": "assets/brands/EZVIZ.png", "name": "Ezviz"},
    {"img": "assets/brands/HIKVISION.png", "name": "Hikvision"},
    {"img": "assets/brands/MCI.png", "name": "MCI"},
    {"img": "assets/brands/MOBOTIX.png", "name": "Mobotix"},
    {"img": "assets/brands/OPTEX.png", "name": "Optex"},
    {"img": "assets/brands/PARADOX.png", "name": "Paradox"},
    {"img": "assets/brands/POWER-SAFE.png", "name": "Power-Safe"},
    {"img": "assets/brands/SATEL.png", "name": "Satel"},
    {"img": "assets/brands/SECURITY360.png", "name": "Security360"},
    {"img": "assets/brands/TPLINK.png", "name": "Tp-Link"},
    {"img": "assets/brands/TRIKDIS.png", "name": "Trikdis"},
    {"img": "assets/brands/Yale.png", "name": "Yale"},
    {"img": "assets/brands/ZKTECO.png", "name": "Zkteco"},
  ];

  late List<Map<String, String>> _infiniteLogos;

  @override
  void initState() {
    super.initState();
    _infiniteLogos = [..._logos, ..._logos, ..._logos];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent / 2);
        _startAutoScroll();
      }
    });
  }

  void _startAutoScroll() {
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (_scrollController.hasClients && !_isUserInteracting) {
        double next = _scrollController.offset + 0.4;
        if (next >= _scrollController.position.maxScrollExtent) {
          _scrollController.jumpTo(_scrollController.position.minScrollExtent);
        } else {
          _scrollController.jumpTo(next);
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 1. Usamos Padding para el desplazamiento hacia arriba (evita errores de Container)
    return Padding(
      padding: const EdgeInsets.only(top: 0), // Cambia a -10 si quieres probar subirlo
      child: SizedBox(
        height: 70,
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollStartNotification) _isUserInteracting = true;
            if (notification is ScrollEndNotification) _isUserInteracting = false;
            return false;
          },
          child: ListView.builder(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _infiniteLogos.length,
            itemBuilder: (context, index) {
              final brand = _infiniteLogos[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                child: GestureDetector( // GestureDetector es más ligero que InkWell
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ProductoPorMarca(brandName: brand['name']!),
                      ),
                    );
                  },
                  child: Container(
                    width: 90,
                    // 2. IMPORTANTE: No pongas 'color' fuera de decoration
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: const [
                        BoxShadow(
                            color: Colors.black12,
                            blurRadius: 2,
                            offset: Offset(0, 1)
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Image.asset(
                        brand['img']!,
                        fit: BoxFit.contain,
                        // Añadimos esto por si alguna imagen falla
                        errorBuilder: (context, error, stackTrace) => const Icon(Icons.business, color: Colors.grey),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
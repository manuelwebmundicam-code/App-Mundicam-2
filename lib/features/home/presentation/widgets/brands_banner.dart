import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mundicam/features/catalog/presentation/pages/producto_por_marca_page.dart';

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

  late final List<Map<String, String>> _infiniteLogos;

  @override
  void initState() {
    super.initState();

    _infiniteLogos = [..._logos, ..._logos, ..._logos];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(
          _scrollController.position.maxScrollExtent / 2,
        );
        _startAutoScroll();
      }
    });
  }

  void _startAutoScroll() {
    _timer?.cancel();

    _timer = Timer.periodic(const Duration(milliseconds: 18), (_) {
      if (!_scrollController.hasClients || _isUserInteracting) return;

      final next = _scrollController.offset + 0.35;

      if (next >= _scrollController.position.maxScrollExtent) {
        _scrollController.jumpTo(_scrollController.position.minScrollExtent);
      } else {
        _scrollController.jumpTo(next);
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
    return SizedBox(
      height: 94,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollStartNotification) {
            _isUserInteracting = true;
          }

          if (notification is ScrollEndNotification) {
            _isUserInteracting = false;
          }

          return false;
        },
        child: ListView.builder(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          itemCount: _infiniteLogos.length,
          itemBuilder: (context, index) {
            final brand = _infiniteLogos[index];

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          ProductoPorMarca(brandName: brand['name']!),
                    ),
                  );
                },
                child: Container(
                  width: 118,
                  height: 78,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFFE1E7EF),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.055),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Image.asset(
                      brand['img']!,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.business, color: Colors.grey),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
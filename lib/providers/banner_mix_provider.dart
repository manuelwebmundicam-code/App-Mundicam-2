import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/banner_mix.dart';
import '../services/api_service.dart';
import '../models/banner.dart';

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());
final bannerMixProvider = FutureProvider<List<BannerMixModel>>((ref) async {
  final api = ref.watch(apiServiceProvider);

  // Banners que SIEMPRE quieres ver (Locales)
  final List<BannerMixModel> misBanners = [
    const BannerMixModel(
      title: "OFERTAS FLASH",
      subtitle: "Descuentos exclusivos esta semana",
      image: "assets/banners/banner1.png",
      link: "ofertas",
      type: BannerMixType.oferta,
    ),
    const BannerMixModel(
      title: "ÚLTIMAS UNIDADES",
      subtitle: "Liquidación total de stock",
      image: "assets/banners/banner2.png",
      link: "ultimas-unidades",
      type: BannerMixType.local,
    ),
  ];

  try {
    // Esto es lo que está dando el 404 según tu log
    final List<BannerModel> webBanners = await api.getBanners();

    final List<BannerMixModel> webMix = webBanners.map((b) {
      return BannerMixModel(
        title: "NOVEDAD",
        subtitle: "Ver más",
        image: b.image,
        link: b.link,
        type: BannerMixType.web,
      );
    }).toList();

    return [...misBanners, ...webMix];
  } catch (e) {
    // Como el log dice que hay un 404, entra aquí:
    debugPrint("La API de banners no responde (404). Usando locales.");
    return misBanners;
  }
});
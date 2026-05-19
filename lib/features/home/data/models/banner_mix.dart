enum BannerMixType { web, producto, curso, oferta, local, novedad, tendencia }

class BannerMixModel {
  final String image;
  final String link;
  final BannerMixType type;
  final String? id;
  final String? title;
  final String? subtitle;

  const BannerMixModel({
    required this.image,
    required this.link,
    this.type = BannerMixType.web,
    this.id,
    this.title,
    this.subtitle,
  });

  factory BannerMixModel.fromJson(Map<String, dynamic> json) {
    return BannerMixModel(
      image: json['image']?.toString() ?? '',
      link: json['link']?.toString() ?? '',
      type: _parseType(json['type']),
      id: json['id']?.toString(),
    );
  }

  static BannerMixType _parseType(dynamic type) {
    switch (type?.toString().toLowerCase()) {
      case 'product':
        return BannerMixType.producto;
      case 'course':
        return BannerMixType.curso;
      case 'offer':
        return BannerMixType.oferta;
      default:
        return BannerMixType.web;
    }
  }
}

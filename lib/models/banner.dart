class BannerModel {
  final String image;
  final String link;

  const BannerModel({
    required this.image,
    required this.link,
  });

  factory BannerModel.fromJson(Map<String, dynamic> json) {
    return BannerModel(
      image: json['image']?.toString() ?? '',
      link: json['link']?.toString() ?? '',
    );
  }
}
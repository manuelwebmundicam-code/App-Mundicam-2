class CategoryModel {
  final int id;
  final String name;
  final String slug;
  final String imageUrl;
  final int parent;
  final int count;
  final int menuOrder;

  const CategoryModel({
    required this.id,
    required this.name,
    required this.slug,
    required this.imageUrl,
    required this.parent,
    required this.count,
    required this.menuOrder,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    final image = json['image'];

    return CategoryModel(
      id: json['id'] as int? ?? 0,
      name: json['name']?.toString() ?? 'Sin nombre',
      slug: json['slug']?.toString() ?? '',
      imageUrl: image != null ? (image['src']?.toString() ?? '') : '',
      parent: json['parent'] as int? ?? 0,
      count: json['count'] as int? ?? 0,
      menuOrder: json['menu_order'] as int? ?? 0,
    );
  }
}

class MundicamNewsItem {
  final int id;
  final String title;
  final String publishedDate;
  final String imageUrl;
  final String excerpt;
  final String content;
  final String sourceUrl;

  const MundicamNewsItem({
    required this.id,
    required this.title,
    required this.publishedDate,
    required this.imageUrl,
    required this.excerpt,
    required this.content,
    required this.sourceUrl,
  });

  factory MundicamNewsItem.fromCanonicalJson(Map<String, dynamic> json) {
    return MundicamNewsItem(
      id: _asInt(json['id']),
      title: _asText(json['title']),
      publishedDate: _asText(json['date']),
      imageUrl: _asText(json['image_url']),
      excerpt: _asText(json['excerpt']),
      content: _asText(json['content']),
      sourceUrl: _asText(json['url']),
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _asText(dynamic value) {
    return value?.toString().trim() ?? '';
  }
}

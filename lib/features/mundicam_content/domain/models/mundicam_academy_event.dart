class MundicamAcademyEvent {
  final int id;
  final String title;
  final DateTime? eventDate;
  final String startTime;
  final String presenter;
  final String description;
  final String imageUrl;
  final String registrationUrl;

  const MundicamAcademyEvent({
    required this.id,
    required this.title,
    required this.eventDate,
    required this.startTime,
    required this.presenter,
    required this.description,
    required this.imageUrl,
    required this.registrationUrl,
  });

  factory MundicamAcademyEvent.fromCanonicalJson(
    Map<String, dynamic> json,
  ) {
    return MundicamAcademyEvent(
      id: _asInt(json['id']),
      title: _asText(json['title']),
      eventDate: _asDate(json['event_date']),
      startTime: _asText(json['start_time']),
      presenter: _asText(json['presenter']),
      description: _asText(json['description']),
      imageUrl: _asText(json['image_url']),
      registrationUrl: _asText(json['registration_url']),
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _asText(dynamic value) {
    return value?.toString().trim() ?? '';
  }

  static DateTime? _asDate(dynamic value) {
    if (value == null) return null;

    if (value is DateTime) {
      return DateTime(value.year, value.month, value.day);
    }

    final raw = value.toString().trim();
    if (raw.isEmpty) return null;

    final iso = DateTime.tryParse(raw);
    if (iso != null) {
      return DateTime(iso.year, iso.month, iso.day);
    }

    final match = RegExp(
      r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$',
    ).firstMatch(raw);

    if (match == null) return null;

    return DateTime(
      int.parse(match.group(3)!),
      int.parse(match.group(2)!),
      int.parse(match.group(1)!),
    );
  }
}

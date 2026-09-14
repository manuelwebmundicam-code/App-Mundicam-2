import 'package:mundicam/features/mundicam_content/domain/models/mundicam_academy_event.dart';
import 'package:mundicam/features/mundicam_content/domain/models/mundicam_news_item.dart';
import 'package:mundicam/features/mundicam_content/domain/repositories/mundicam_content_repository.dart';

typedef MundicamContentItemsLoader =
    Future<List<Map<String, dynamic>>> Function();

class PhpContentRepository implements MundicamContentRepository {
  const PhpContentRepository({
    required this.loadNewsItems,
    required this.loadAcademyItems,
  });

  final MundicamContentItemsLoader loadNewsItems;
  final MundicamContentItemsLoader loadAcademyItems;

  @override
  Future<List<MundicamNewsItem>> getNews() async {
    final raw = await loadNewsItems();

    return raw
        .map(MundicamNewsItem.fromCanonicalJson)
        .where((item) => item.id > 0 && item.title.isNotEmpty)
        .toList();
  }

  @override
  Future<List<MundicamAcademyEvent>> getAcademyEvents() async {
    final raw = await loadAcademyItems();

    final events = raw
        .map(MundicamAcademyEvent.fromCanonicalJson)
        .where((item) => item.id > 0 && item.title.isNotEmpty)
        .toList();

    events.sort((a, b) {
      final aDate = a.eventDate;
      final bDate = b.eventDate;

      if (aDate != null && bDate != null) {
        return aDate.compareTo(bDate);
      }
      if (aDate != null) return -1;
      if (bDate != null) return 1;
      return a.title.compareTo(b.title);
    });

    return events;
  }
}

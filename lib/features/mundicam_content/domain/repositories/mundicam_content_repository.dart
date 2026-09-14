import 'package:mundicam/features/mundicam_content/domain/models/mundicam_academy_event.dart';
import 'package:mundicam/features/mundicam_content/domain/models/mundicam_news_item.dart';

abstract class MundicamContentRepository {
  Future<List<MundicamNewsItem>> getNews();
  Future<List<MundicamAcademyEvent>> getAcademyEvents();
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mundicam/features/mundicam_content/data/repositories/wordpress_rest_content_repository.dart';
import 'package:mundicam/features/mundicam_content/domain/models/mundicam_academy_event.dart';
import 'package:mundicam/features/mundicam_content/domain/models/mundicam_news_item.dart';
import 'package:mundicam/features/mundicam_content/domain/repositories/mundicam_content_repository.dart';

/// ÚNICO PUNTO DE CONEXIÓN.
///
/// Mientras el PHP de MundiCam App API no exponga el contrato definitivo,
/// se usa WordPress REST público.
///
/// Cuando llegue el PHP real, NO hay que tocar las pantallas:
/// solo se sustituye esta implementación por PhpContentRepository
/// y se conectan sus dos loaders a las rutas reales del plugin.
final mundicamContentRepositoryProvider =
    Provider<MundicamContentRepository>((ref) {
  return WordPressRestContentRepository();
});

final mundicamNewsProvider =
    FutureProvider<List<MundicamNewsItem>>((ref) async {
  return ref.watch(mundicamContentRepositoryProvider).getNews();
});

final mundicamAcademyProvider =
    FutureProvider<List<MundicamAcademyEvent>>((ref) async {
  return ref.watch(mundicamContentRepositoryProvider).getAcademyEvents();
});

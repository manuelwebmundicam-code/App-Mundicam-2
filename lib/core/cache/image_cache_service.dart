// services/image_cache_service.dart
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class ImageCacheService {
  static final ImageCacheService _instance = ImageCacheService._();
  factory ImageCacheService() => _instance;
  ImageCacheService._();

  static final CacheManager _cacheManager = CacheManager(
    Config(
      'mundicam_images',
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 1000,
      repo: JsonCacheInfoRepository(databaseName: 'mundicam_images'),
      fileSystem: IOFileSystem('mundicam_images'),
      fileService: HttpFileService(),
    ),
  );

  static CacheManager get cacheManager => _cacheManager;
}

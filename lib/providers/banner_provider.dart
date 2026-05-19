import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/home/data/models/banner.dart';
import '../services/api_service.dart';

final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});

final bannerProvider = FutureProvider<List<BannerModel>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  return api.getBanners();
});

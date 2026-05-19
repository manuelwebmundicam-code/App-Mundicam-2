import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mundicam/features/home/data/models/noticia.dart';
import 'package:mundicam/core/network/api_service.dart';

final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});

final noticiasProvider = FutureProvider<List<Noticia>>((ref) async {
  final apiService = ref.watch(apiServiceProvider);
  return apiService.getNoticias();
});

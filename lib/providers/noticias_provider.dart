import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/noticia.dart';
import '../services/api_service.dart';

final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});

final noticiasProvider = FutureProvider<List<Noticia>>((ref) async {
  final apiService = ref.watch(apiServiceProvider);
  return apiService.getNoticias();
});
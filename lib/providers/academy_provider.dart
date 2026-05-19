import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../features/training/data/models/cursos_model.dart';

final academyProvider = FutureProvider<List<CourseModel>>((ref) async {
  // Solo se llama a la API la primera vez o si refrescas
  return await ApiService().getAcademyCourses();
});

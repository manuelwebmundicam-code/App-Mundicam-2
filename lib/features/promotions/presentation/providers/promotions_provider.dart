import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mundicam/core/network/api_service.dart';
import 'package:mundicam/features/promotions/data/models/promotion_model.dart';

final promotionsProvider = FutureProvider<List<PromotionModel>>((ref) async {
  return ApiService().getPromotions();
});

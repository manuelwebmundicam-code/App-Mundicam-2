import 'package:flutter_riverpod/flutter_riverpod.dart';

// Modelo de datos para los filtros
class MundiFilters {
  final String brand;
  final String orderBy;

  MundiFilters({this.brand = "", this.orderBy = "date"});

  MundiFilters copyWith({String? brand, String? orderBy}) {
    return MundiFilters(
      // Si el nuevo valor es null, mantenemos el que ya existía en el estado
      brand: brand ?? this.brand,
      orderBy: orderBy ?? this.orderBy,
    );
  }
}

class FilterNotifier extends StateNotifier<MundiFilters> {
  FilterNotifier() : super(MundiFilters());

  // ACTUALIZACIÓN: Ahora preserva los valores anteriores si no se pasan como argumento
  void update({String? brand, String? orderBy}) {
    state = state.copyWith(brand: brand, orderBy: orderBy);
  }

  void reset() {
    state = MundiFilters();
  }
}

final productFilterProvider =
    StateNotifierProvider<FilterNotifier, MundiFilters>((ref) {
      return FilterNotifier();
    });

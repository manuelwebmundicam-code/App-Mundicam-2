import 'package:flutter_riverpod/flutter_riverpod.dart';

class MundiFilters {
  final String brand;
  final int? brandId;
  final String search;
  final String orderBy;

  const MundiFilters({
    this.brand = '',
    this.brandId,
    this.search = '',
    this.orderBy = '',
  });

  bool get hasBrand => brand.trim().isNotEmpty || brandId != null;
  bool get hasSearch => search.trim().isNotEmpty;
  bool get hasOrder => orderBy.trim().isNotEmpty;
  bool get hasActiveFilters => hasBrand || hasSearch || hasOrder;

  MundiFilters copyWith({
    String? brand,
    int? brandId,
    bool clearBrandId = false,
    String? search,
    String? orderBy,
  }) {
    return MundiFilters(
      brand: brand ?? this.brand,
      brandId: clearBrandId ? null : brandId ?? this.brandId,
      search: search ?? this.search,
      orderBy: orderBy ?? this.orderBy,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MundiFilters &&
        other.brand == brand &&
        other.brandId == brandId &&
        other.search == search &&
        other.orderBy == orderBy;
  }

  @override
  int get hashCode => Object.hash(
    brand,
    brandId,
    search,
    orderBy,
  );
}

class FilterNotifier extends StateNotifier<MundiFilters> {
  FilterNotifier() : super(const MundiFilters());

  void update({
    String? brand,
    int? brandId,
    String? search,
    String? orderBy,
  }) {
    final clearBrandIdBecauseBrandChanged = brand != null && brandId == null;
    state = state.copyWith(
      brand: brand,
      brandId: brandId,
      clearBrandId: clearBrandIdBecauseBrandChanged,
      search: search,
      orderBy: orderBy,
    );
  }

  void setBrand({
    required String name,
    required int id,
  }) {
    state = state.copyWith(
      brand: name.trim(),
      brandId: id,
    );
  }

  void clearBrand() {
    state = state.copyWith(
      brand: '',
      clearBrandId: true,
    );
  }

  void setSearch(String value) {
    state = state.copyWith(
      search: value.trim(),
    );
  }

  void clearSearch() {
    state = state.copyWith(
      search: '',
    );
  }

  void setOrderBy(String value) {
    state = state.copyWith(
      orderBy: value.trim(),
    );
  }

  void clearOrderBy() {
    state = state.copyWith(
      orderBy: '',
    );
  }

  void reset() {
    state = const MundiFilters();
  }
}

final productFilterProvider = StateNotifierProvider<FilterNotifier, MundiFilters>((ref) {
  return FilterNotifier();
});
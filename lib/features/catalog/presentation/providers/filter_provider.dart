import 'package:flutter_riverpod/flutter_riverpod.dart';

class MundiFilters {
  final String brand;
  final int? brandId;
  final String search;
  final String orderBy;
  final Map<String, int> attributeTermIds;
  final Map<String, String> attributeLabels;
  final Map<String, String> attributeGroupLabels;

  const MundiFilters({
    this.brand = '',
    this.brandId,
    this.search = '',
    this.orderBy = '',
    this.attributeTermIds = const <String, int>{},
    this.attributeLabels = const <String, String>{},
    this.attributeGroupLabels = const <String, String>{},
  });

  bool get hasBrand => brand.trim().isNotEmpty || brandId != null;
  bool get hasSearch => search.trim().isNotEmpty;
  bool get hasOrder => orderBy.trim().isNotEmpty;
  bool get hasAttributes => attributeTermIds.isNotEmpty;
  bool get hasActiveFilters => hasBrand || hasSearch || hasOrder || hasAttributes;

  MundiFilters copyWith({
    String? brand,
    int? brandId,
    bool clearBrandId = false,
    String? search,
    String? orderBy,
    Map<String, int>? attributeTermIds,
    Map<String, String>? attributeLabels,
    Map<String, String>? attributeGroupLabels,
  }) {
    return MundiFilters(
      brand: brand ?? this.brand,
      brandId: clearBrandId ? null : brandId ?? this.brandId,
      search: search ?? this.search,
      orderBy: orderBy ?? this.orderBy,
      attributeTermIds: attributeTermIds ?? this.attributeTermIds,
      attributeLabels: attributeLabels ?? this.attributeLabels,
      attributeGroupLabels: attributeGroupLabels ?? this.attributeGroupLabels,
    );
  }

  String attributeLabelFor(String taxonomy) {
    return attributeLabels[taxonomy]?.trim() ?? '';
  }

  String attributeGroupLabelFor(String taxonomy) {
    return attributeGroupLabels[taxonomy]?.trim() ?? taxonomy;
  }

  @override
  bool operator ==(Object other) {
    return other is MundiFilters &&
        other.brand == brand &&
        other.brandId == brandId &&
        other.search == search &&
        other.orderBy == orderBy &&
        _mapIntEquals(other.attributeTermIds, attributeTermIds) &&
        _mapStringEquals(other.attributeLabels, attributeLabels) &&
        _mapStringEquals(other.attributeGroupLabels, attributeGroupLabels);
  }

  @override
  int get hashCode => Object.hash(
    brand,
    brandId,
    search,
    orderBy,
    Object.hashAll(
      attributeTermIds.entries.map((entry) => '${entry.key}:${entry.value}'),
    ),
    Object.hashAll(
      attributeLabels.entries.map((entry) => '${entry.key}:${entry.value}'),
    ),
    Object.hashAll(
      attributeGroupLabels.entries.map((entry) => '${entry.key}:${entry.value}'),
    ),
  );

  static bool _mapIntEquals(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  static bool _mapStringEquals(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}

class FilterNotifier extends StateNotifier<MundiFilters> {
  FilterNotifier() : super(const MundiFilters());

  void update({
    String? brand,
    int? brandId,
    String? search,
    String? orderBy,
    Map<String, int>? attributeTermIds,
    Map<String, String>? attributeLabels,
    Map<String, String>? attributeGroupLabels,
  }) {
    final clearBrandIdBecauseBrandChanged = brand != null && brandId == null;
    state = state.copyWith(
      brand: brand,
      brandId: brandId,
      clearBrandId: clearBrandIdBecauseBrandChanged,
      search: search,
      orderBy: orderBy,
      attributeTermIds: attributeTermIds,
      attributeLabels: attributeLabels,
      attributeGroupLabels: attributeGroupLabels,
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
    state = state.copyWith(search: value.trim());
  }

  void clearSearch() {
    state = state.copyWith(search: '');
  }

  void setOrderBy(String value) {
    state = state.copyWith(orderBy: value.trim());
  }

  void clearOrderBy() {
    state = state.copyWith(orderBy: '');
  }

  void toggleAttributeTerm({
    required String taxonomy,
    required int termId,
    required String label,
    required String groupLabel,
  }) {
    final cleanTaxonomy = taxonomy.trim();
    final cleanLabel = label.trim();
    final cleanGroupLabel = groupLabel.trim();

    if (cleanTaxonomy.isEmpty || termId <= 0 || cleanLabel.isEmpty) {
      return;
    }

    final currentTermId = state.attributeTermIds[cleanTaxonomy];

    if (currentTermId == termId) {
      clearAttributeTerm(cleanTaxonomy);
      return;
    }

    final nextTerms = Map<String, int>.from(state.attributeTermIds)
      ..[cleanTaxonomy] = termId;
    final nextLabels = Map<String, String>.from(state.attributeLabels)
      ..[cleanTaxonomy] = cleanLabel;
    final nextGroupLabels = Map<String, String>.from(state.attributeGroupLabels)
      ..[cleanTaxonomy] = cleanGroupLabel.isEmpty ? cleanTaxonomy : cleanGroupLabel;

    state = state.copyWith(
      attributeTermIds: nextTerms,
      attributeLabels: nextLabels,
      attributeGroupLabels: nextGroupLabels,
    );
  }

  void clearAttributeTerm(String taxonomy) {
    final cleanTaxonomy = taxonomy.trim();
    if (cleanTaxonomy.isEmpty) return;

    final nextTerms = Map<String, int>.from(state.attributeTermIds)
      ..remove(cleanTaxonomy);
    final nextLabels = Map<String, String>.from(state.attributeLabels)
      ..remove(cleanTaxonomy);
    final nextGroupLabels = Map<String, String>.from(state.attributeGroupLabels)
      ..remove(cleanTaxonomy);

    state = state.copyWith(
      attributeTermIds: nextTerms,
      attributeLabels: nextLabels,
      attributeGroupLabels: nextGroupLabels,
    );
  }

  void clearAttributes() {
    state = state.copyWith(
      attributeTermIds: const <String, int>{},
      attributeLabels: const <String, String>{},
      attributeGroupLabels: const <String, String>{},
    );
  }

  void reset() {
    state = const MundiFilters();
  }
}

final productFilterProvider =
StateNotifierProvider<FilterNotifier, MundiFilters>((ref) {
  return FilterNotifier();
});

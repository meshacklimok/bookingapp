import 'service.dart';

enum ServiceSort {
  newest('Newest'),
  priceLow('Price: low to high'),
  priceHigh('Price: high to low'),
  soonest('Soonest event');

  const ServiceSort(this.label);

  final String label;
}

class ServiceFilters {
  const ServiceFilters({
    this.query = '',
    this.category,
    this.mode,
    this.maxPriceCents,
    this.sort = ServiceSort.newest,
  });

  final String query;
  final String? category;
  final BookingMode? mode;
  final int? maxPriceCents;
  final ServiceSort sort;

  /// Filters chosen in the filter sheet (the search box and category chips are not counted).
  int get activeCount => (mode != null ? 1 : 0) + (maxPriceCents != null ? 1 : 0) + (sort != ServiceSort.newest ? 1 : 0);

  ServiceFilters copyWith({
    String? query,
    Object? category = _keep,
    Object? mode = _keep,
    Object? maxPriceCents = _keep,
    ServiceSort? sort,
  }) =>
      ServiceFilters(
        query: query ?? this.query,
        category: identical(category, _keep) ? this.category : category as String?,
        mode: identical(mode, _keep) ? this.mode : mode as BookingMode?,
        maxPriceCents: identical(maxPriceCents, _keep) ? this.maxPriceCents : maxPriceCents as int?,
        sort: sort ?? this.sort,
      );

  @override
  bool operator ==(Object other) =>
      other is ServiceFilters &&
      other.query == query &&
      other.category == category &&
      other.mode == mode &&
      other.maxPriceCents == maxPriceCents &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(query, category, mode, maxPriceCents, sort);
}

const _keep = Object();

/// Turns user input into an `ilike` pattern, dropping characters that have meaning inside a PostgREST filter.
/// Returns null when nothing searchable is left.
String? searchPattern(String input) {
  final safe = input.replaceAll(RegExp(r'[%_,()*\\"]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return safe.isEmpty ? null : '%$safe%';
}

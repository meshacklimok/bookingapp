import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/service.dart';
import '../domain/service_filters.dart';

class ServiceRepository {
  ServiceRepository(this._client);

  final SupabaseClient _client;

  static const pageSize = 20;

  Future<List<Service>> list(ServiceFilters filters, {int limit = pageSize}) async {
    var request = _client.from('services').select('*, organizations(name)').eq('is_active', true);
    final pattern = searchPattern(filters.query);
    if (pattern != null) request = request.or('title.ilike.$pattern,description.ilike.$pattern');
    if (filters.category != null) request = request.eq('category', filters.category!);
    if (filters.mode != null) request = request.eq('booking_mode', filters.mode!.name);
    if (filters.maxPriceCents != null) request = request.lte('price_cents', filters.maxPriceCents!);
    // Events that already started are not bookable; appointments have no event date.
    request = request.or('event_starts_at.is.null,event_starts_at.gte.${DateTime.now().toUtc().toIso8601String()}');

    final ordered = switch (filters.sort) {
      ServiceSort.newest => request.order('created_at', ascending: false),
      ServiceSort.priceLow => request.order('price_cents', ascending: true),
      ServiceSort.priceHigh => request.order('price_cents', ascending: false),
      ServiceSort.soonest => request.order('event_starts_at', ascending: true, nullsFirst: false),
    };
    final rows = await ordered.limit(limit);
    return rows.map(Service.fromMap).toList();
  }

  Future<List<StaffMember>> staff(String serviceId) async {
    final rows = await _client.rpc('get_service_staff', params: {'p_service_id': serviceId}) as List<dynamic>;
    return rows.map((r) => StaffMember.fromMap(r as Map<String, dynamic>)).toList();
  }

  Future<Service> get(String id) async {
    final row = await _client.from('services').select('*, organizations(name)').eq('id', id).single();
    return Service.fromMap(row);
  }

  Future<List<TicketTier>> tiers(String serviceId) async {
    final rows = await _client.from('ticket_tiers').select().eq('service_id', serviceId).order('price_cents');
    return rows.map(TicketTier.fromMap).toList();
  }
}

final serviceRepositoryProvider = Provider((ref) => ServiceRepository(ref.watch(supabaseProvider)));

final serviceFiltersProvider = StateProvider<ServiceFilters>((ref) => const ServiceFilters());

/// How many results to fetch; "Load more" raises it, and any filter change resets it.
final resultLimitProvider = StateProvider<int>((ref) {
  ref.watch(serviceFiltersProvider);
  return ServiceRepository.pageSize;
});

final serviceListProvider = FutureProvider.autoDispose<List<Service>>((ref) {
  final filters = ref.watch(serviceFiltersProvider);
  final limit = ref.watch(resultLimitProvider);
  return ref.watch(serviceRepositoryProvider).list(filters, limit: limit);
});

final staffProvider = FutureProvider.autoDispose.family<List<StaffMember>, String>(
  (ref, serviceId) => ref.watch(serviceRepositoryProvider).staff(serviceId),
);

final serviceProvider = FutureProvider.autoDispose.family<Service, String>(
  (ref, id) => ref.watch(serviceRepositoryProvider).get(id),
);

final tiersProvider = FutureProvider.autoDispose.family<List<TicketTier>, String>(
  (ref, serviceId) => ref.watch(serviceRepositoryProvider).tiers(serviceId),
);

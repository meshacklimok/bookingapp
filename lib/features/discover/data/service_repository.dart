import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/service.dart';

class ServiceRepository {
  ServiceRepository(this._client);

  final SupabaseClient _client;

  Future<List<Service>> list({String query = '', String? category}) async {
    var request = _client.from('services').select('*, organizations(name)').eq('is_active', true);
    if (query.trim().isNotEmpty) {
      // strip characters that have meaning inside a PostgREST filter value
      final safe = query.trim().replaceAll(RegExp(r'[%,()*]'), ' ');
      request = request.ilike('title', '%$safe%');
    }
    if (category != null) request = request.eq('category', category);
    final rows = await request.order('created_at', ascending: false).limit(50);
    return rows.map(Service.fromMap).toList();
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

final searchQueryProvider = StateProvider<String>((ref) => '');
final categoryProvider = StateProvider<String?>((ref) => null);

final serviceListProvider = FutureProvider.autoDispose<List<Service>>((ref) {
  final query = ref.watch(searchQueryProvider);
  final category = ref.watch(categoryProvider);
  return ref.watch(serviceRepositoryProvider).list(query: query, category: category);
});

final serviceProvider = FutureProvider.autoDispose.family<Service, String>(
  (ref, id) => ref.watch(serviceRepositoryProvider).get(id),
);

final tiersProvider = FutureProvider.autoDispose.family<List<TicketTier>, String>(
  (ref, serviceId) => ref.watch(serviceRepositoryProvider).tiers(serviceId),
);

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/profile.dart';

class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

  /// The signed-in user's row in `profiles` (created by the `on_auth_user_created` trigger).
  Future<Profile?> me() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final row = await _client
        .from('profiles')
        .select('id, full_name, phone, avatar_url, is_platform_admin')
        .eq('id', userId)
        .maybeSingle();
    return row == null ? null : Profile.fromMap(row);
  }

  Future<void> update({required String fullName, required String? phone}) async {
    final userId = _client.auth.currentUser!.id;
    await _client.from('profiles').update({'full_name': fullName, 'phone': phone}).eq('id', userId);
  }
}

final profileRepositoryProvider = Provider((ref) => ProfileRepository(ref.watch(supabaseProvider)));

final myProfileProvider = FutureProvider.autoDispose<Profile?>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(profileRepositoryProvider).me();
});

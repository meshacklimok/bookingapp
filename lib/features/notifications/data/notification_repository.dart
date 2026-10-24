import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/app_notification.dart';

class NotificationRepository {
  NotificationRepository(this._client);

  final SupabaseClient _client;

  /// The latest 50, newest first, kept live by realtime so the unread badge updates without a refresh.
  Stream<List<AppNotification>> watch(String userId) => _client
      .from('notifications')
      .stream(primaryKey: ['id'])
      .eq('user_id', userId)
      .order('created_at', ascending: false)
      .limit(50)
      .map((rows) => rows.map(AppNotification.fromMap).toList());

  /// Marks the given notifications read, or every unread one when [ids] is null.
  Future<void> markRead([List<String>? ids]) => _client.rpc('mark_notifications_read', params: {'p_ids': ids});
}

final notificationRepositoryProvider = Provider((ref) => NotificationRepository(ref.watch(supabaseProvider)));

final notificationsProvider = StreamProvider.autoDispose<List<AppNotification>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(const []);
  return ref.watch(notificationRepositoryProvider).watch(userId);
});

final unreadNotificationsProvider = Provider.autoDispose<int>((ref) => unreadCount(ref.watch(notificationsProvider).valueOrNull ?? const []));

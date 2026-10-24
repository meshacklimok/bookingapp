import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/async_body.dart';
import '../data/notification_repository.dart';
import '../domain/app_notification.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  Future<void> _markRead(BuildContext context, WidgetRef ref, [List<String>? ids]) async {
    try {
      await ref.read(notificationRepositoryProvider).markRead(ids);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadNotificationsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (unread > 0) TextButton(onPressed: () => _markRead(context, ref), child: const Text('Mark all read')),
        ],
      ),
      body: AsyncBody<List<AppNotification>>(
        value: items,
        onRetry: () => ref.invalidate(notificationsProvider),
        data: (list) {
          if (list.isEmpty) return const EmptyState(icon: Icons.notifications_none, message: 'Nothing here yet.');
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final n = list[i];
              return ListTile(
                leading: Icon(n.isUnread ? Icons.circle : Icons.circle_outlined, size: 12, color: n.isUnread ? Theme.of(context).colorScheme.primary : null),
                title: Text(n.title, style: TextStyle(fontWeight: n.isUnread ? FontWeight.w700 : FontWeight.w400)),
                subtitle: Text([if (n.body != null) n.body!, formatRelative(n.createdAt, DateTime.now())].join('\n')),
                isThreeLine: n.body != null,
                onTap: () {
                  if (n.isUnread) _markRead(context, ref, [n.id]);
                  if (n.route != null) context.push(n.route!);
                },
              );
            },
          );
        },
      ),
    );
  }
}

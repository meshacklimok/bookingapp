import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/async_body.dart';
import '../data/ticket_repository.dart';

class TicketsScreen extends ConsumerWidget {
  const TicketsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tickets = ref.watch(myTicketsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My tickets')),
      body: AsyncBody<List<TicketInfo>>(
        value: tickets,
        onRetry: () => ref.invalidate(myTicketsProvider),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyState(icon: Icons.confirmation_number_outlined, message: 'Your tickets will appear here.');
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myTicketsProvider),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final t = items[i];
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: const Icon(Icons.qr_code_2, size: 36),
                    title: Text(t.serviceTitle ?? 'Ticket'),
                    subtitle: Text([
                      if (t.startsAt != null) formatDateTime(t.startsAt!),
                      if (t.status != 'valid') t.status,
                    ].join(' · ')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/ticket/${t.id}'),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

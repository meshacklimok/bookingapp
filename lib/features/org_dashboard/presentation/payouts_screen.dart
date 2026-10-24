import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/async_body.dart';
import '../data/org_repository.dart';
import '../domain/payouts.dart';

class PayoutsScreen extends ConsumerWidget {
  const PayoutsScreen({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(orgBalanceProvider(orgId));
    final payouts = ref.watch(orgPayoutsProvider(orgId));
    void refresh() {
      ref.invalidate(orgBalanceProvider(orgId));
      ref.invalidate(orgPayoutsProvider(orgId));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Payouts')),
      body: AsyncBody<OrgBalance>(
        value: balance,
        onRetry: refresh,
        data: (b) => RefreshIndicator(
          onRefresh: () async => refresh(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Owed to you', style: Theme.of(context).textTheme.labelLarge),
                      Text(formatKes(b.payableCents), style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 12),
                      _line('Already paid out', formatKes(b.paidOutCents)),
                      _line('Coming from upcoming bookings', formatKes(b.upcomingCents)),
                      const SizedBox(height: 8),
                      Text(
                        'Earnings become payable once the booking has taken place. Upcoming bookings can still be cancelled and refunded. '
                        'Payouts are sent by the platform team and appear below.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('History', style: Theme.of(context).textTheme.titleMedium),
              ...payouts.when(
                data: (items) => [
                  if (items.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No payouts yet.')),
                  for (final p in items)
                    Card(
                      child: ListTile(
                        title: Text(formatKes(p.amountCents)),
                        subtitle: Text([
                          formatDay(p.createdAt.toLocal()),
                          p.method.label,
                          if (p.reference != null) p.reference!,
                          if (p.note != null) p.note!,
                        ].join(' · ')),
                      ),
                    ),
                ],
                loading: () => const [Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))],
                error: (_, __) => const [Padding(padding: EdgeInsets.all(24), child: Text('Could not load payout history.'))],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [Expanded(child: Text(label)), Text(value)]),
      );
}

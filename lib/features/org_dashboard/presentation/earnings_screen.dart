import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/async_body.dart';
import '../data/org_repository.dart';
import '../domain/earnings.dart';

class EarningsScreen extends ConsumerStatefulWidget {
  const EarningsScreen({super.key, required this.orgId});

  final String orgId;

  @override
  ConsumerState<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends ConsumerState<EarningsScreen> {
  EarningsPeriod _period = EarningsPeriod.thisMonth;

  @override
  Widget build(BuildContext context) {
    final key = (widget.orgId, _period);
    final summary = ref.watch(earningsSummaryProvider(key));
    final rows = ref.watch(earningsRowsProvider(key));
    void refresh() {
      ref.invalidate(earningsSummaryProvider(key));
      ref.invalidate(earningsRowsProvider(key));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Earnings')),
      body: AsyncBody<EarningsSummary>(
        value: summary,
        onRetry: refresh,
        data: (total) => RefreshIndicator(
          onRefresh: () async => refresh(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 8,
                children: [
                  for (final p in EarningsPeriod.values)
                    ChoiceChip(label: Text(p.label), selected: p == _period, onSelected: (_) => setState(() => _period = p)),
                ],
              ),
              const SizedBox(height: 12),
              _SummaryCard(summary: total),
              const SizedBox(height: 16),
              Text('Bookings', style: Theme.of(context).textTheme.titleMedium),
              ...rows.when(
                data: (items) => [
                  if (items.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No paid bookings in this period.')),
                  for (final r in items) _EarningsTile(row: r),
                  if (items.length < total.count)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text('Showing the latest ${items.length} of ${total.count} bookings. Totals above include all of them.'),
                    ),
                ],
                loading: () => const [Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))],
                error: (_, __) => [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(children: [
                      const Expanded(child: Text('Could not load the booking list.')),
                      TextButton(onPressed: () => ref.invalidate(earningsRowsProvider(key)), child: const Text('Retry')),
                    ]),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final EarningsSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('You keep', style: theme.textTheme.labelLarge),
            Text(formatKes(summary.netCents), style: theme.textTheme.headlineMedium),
            const SizedBox(height: 12),
            _line('Kept from customers (${summary.count} ${summary.count == 1 ? 'booking' : 'bookings'})', formatKes(summary.grossCents)),
            _line('Platform commission', '− ${formatKes(summary.commissionCents)}'),
            if (summary.refundedCents > 0) _line('Already refunded (not counted above)', formatKes(summary.refundedCents)),
          ],
        ),
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [Expanded(child: Text(label)), Text(value)]),
      );
}

class _EarningsTile extends StatelessWidget {
  const _EarningsTile({required this.row});

  final EarningsRow row;

  @override
  Widget build(BuildContext context) {
    final pct = row.commissionPct;
    return Card(
      child: ListTile(
        title: Text(row.serviceTitle ?? 'Booking'),
        subtitle: Text([
          if (row.customerName != null) row.customerName!,
          formatDateTime(row.startsAt),
          '${formatKes(row.grossCents)} − ${formatKes(row.commissionCents)}${pct == null ? '' : ' (${formatPct(pct)})'}',
          if (row.refundCents > 0) 'after ${formatKes(row.refundCents)} refunded',
        ].join(' · ')),
        trailing: Text(formatKes(row.netCents), style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}

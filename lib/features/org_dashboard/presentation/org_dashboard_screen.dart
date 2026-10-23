import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/async_body.dart';
import '../data/org_repository.dart';

class OrgDashboardScreen extends ConsumerWidget {
  const OrgDashboardScreen({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(orgBookingsProvider(orgId));

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: AsyncBody<List<OrgBooking>>(
        value: bookings,
        onRetry: () => ref.invalidate(orgBookingsProvider(orgId)),
        data: (items) {
          final earned = items
              .where((b) => b.status == 'confirmed' || b.status == 'completed')
              .fold<int>(0, (sum, b) => sum + (b.earningsCents ?? 0));
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(orgBookingsProvider(orgId)),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    title: const Text('Earnings (after commission)'),
                    subtitle: Text(formatKes(earned), style: Theme.of(context).textTheme.headlineSmall),
                  ),
                ),
                const SizedBox(height: 8),
                Text('Bookings', style: Theme.of(context).textTheme.titleMedium),
                if (items.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No bookings yet.')),
                for (final b in items) _OrgBookingTile(booking: b, orgId: orgId),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _OrgBookingTile extends ConsumerWidget {
  const _OrgBookingTile({required this.booking, required this.orgId});

  final OrgBooking booking;
  final String orgId;

  Future<void> _mark(BuildContext context, WidgetRef ref, String status) async {
    try {
      await ref.read(orgRepositoryProvider).setOutcome(booking.id, status);
      ref.invalidate(orgBookingsProvider(orgId));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        title: Text(booking.serviceTitle ?? 'Booking'),
        subtitle: Text([
          if (booking.customerName != null) booking.customerName!,
          formatDateTime(booking.startsAt),
          booking.status.replaceAll('_', ' '),
        ].join(' · ')),
        trailing: Text(formatKes(booking.totalCents)),
        onLongPress: booking.status == 'confirmed'
            ? () => showModalBottomSheet<void>(
                  context: context,
                  builder: (sheet) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.check),
                          title: const Text('Mark completed'),
                          onTap: () {
                            Navigator.pop(sheet);
                            _mark(context, ref, 'completed');
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.person_off),
                          title: const Text('Mark no-show'),
                          onTap: () {
                            Navigator.pop(sheet);
                            _mark(context, ref, 'no_show');
                          },
                        ),
                      ],
                    ),
                  ),
                )
            : null,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/async_body.dart';
import '../../booking/presentation/cancel_booking_dialog.dart';
import '../data/org_repository.dart';
import '../domain/earnings.dart';
import '../domain/organization.dart';

class OrgDashboardScreen extends ConsumerWidget {
  const OrgDashboardScreen({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(orgBookingsProvider(orgId));
    final org = ref.watch(organizationProvider(orgId)).valueOrNull;
    final role = ref.watch(membershipsProvider).valueOrNull?.where((m) => m.orgId == orgId).firstOrNull?.role;
    // RLS only lets owners and admins write services, so staff do not get the entry point.
    final canManage = role == 'owner' || role == 'admin';

    return Scaffold(
      appBar: AppBar(title: Text(org?.name ?? 'Dashboard')),
      body: AsyncBody<List<OrgBooking>>(
        value: bookings,
        onRetry: () => ref.invalidate(orgBookingsProvider(orgId)),
        data: (items) {
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(orgBookingsProvider(orgId)),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (org != null) OrgStatusBanner(status: org.status),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.person_add_alt_outlined),
                    title: const Text('Add a booking'),
                    subtitle: const Text('Walk-ins and phone bookings, paid at the venue'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final added = await context.push<bool>('/org/$orgId/walk-in');
                      if (added == true) ref.invalidate(orgBookingsProvider(orgId));
                    },
                  ),
                ),
                if (canManage)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.design_services_outlined),
                      title: const Text('Services'),
                      subtitle: const Text('Appointments, events and spaces'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/org/$orgId/services'),
                    ),
                  ),
                if (canManage)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.groups_outlined),
                      title: const Text('Staff and hours'),
                      subtitle: const Text('Who takes appointments, and when'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/org/$orgId/staff'),
                    ),
                  ),
                if (canManage)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.sell_outlined),
                      title: const Text('Promo codes'),
                      subtitle: const Text('Discounts customers enter at checkout'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/org/$orgId/promos'),
                    ),
                  ),
                if (canManage) _EarningsCard(orgId: orgId),
                if (canManage)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.account_balance_wallet_outlined),
                      title: const Text('Payouts'),
                      subtitle: const Text('What you are owed and what was paid'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/org/$orgId/payouts'),
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

/// All-time net earnings. The figures come from the database, so they are not capped by the bookings list below.
class _EarningsCard extends ConsumerWidget {
  const _EarningsCard({required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(earningsSummaryProvider((orgId, EarningsPeriod.allTime)));
    return Card(
      child: ListTile(
        title: const Text('Earnings (after commission)'),
        subtitle: Text(
          summary.when(data: (s) => formatKes(s.netCents), loading: () => '…', error: (_, __) => 'Could not load'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/org/$orgId/earnings'),
      ),
    );
  }
}

class OrgStatusBanner extends StatelessWidget {
  const OrgStatusBanner({super.key, required this.status});

  final OrgStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, background, foreground) = switch (status) {
      OrgStatus.approved => (Icons.verified_outlined, scheme.primaryContainer, scheme.onPrimaryContainer),
      OrgStatus.pending => (Icons.hourglass_top, scheme.tertiaryContainer, scheme.onTertiaryContainer),
      OrgStatus.suspended => (Icons.block, scheme.errorContainer, scheme.onErrorContainer),
    };
    return Card(
      color: background,
      child: ListTile(
        leading: Icon(icon, color: foreground),
        title: Text(status.label, style: TextStyle(color: foreground, fontWeight: FontWeight.w600)),
        subtitle: Text(status.explanation, style: TextStyle(color: foreground)),
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
      final repo = ref.read(orgRepositoryProvider);
      if (status == 'balance') {
        await repo.markBalancePaid(booking.id);
      } else {
        await repo.setOutcome(booking.id, status);
      }
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
          if (booking.isWalkIn) 'walk-in',
          if (booking.balanceDue && booking.status != 'cancelled') '${formatKes(booking.balanceCents)} due at venue',
        ].join(' · ')),
        trailing: Text(formatKes(booking.totalCents)),
        onLongPress: booking.status == 'confirmed'
            ? () => showModalBottomSheet<void>(
                  context: context,
                  builder: (sheet) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (booking.balanceDue)
                          ListTile(
                            leading: const Icon(Icons.payments_outlined),
                            title: Text('Balance ${formatKes(booking.balanceCents)} collected'),
                            onTap: () {
                              Navigator.pop(sheet);
                              _mark(context, ref, 'balance');
                            },
                          ),
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
                        if (booking.startsAt.isAfter(DateTime.now()))
                          ListTile(
                            leading: const Icon(Icons.event_busy),
                            title: const Text('Cancel and refund in full'),
                            onTap: () async {
                              Navigator.pop(sheet);
                              final done = await confirmCancelBooking(context, ref,
                                  bookingId: booking.id, title: booking.serviceTitle ?? 'this booking');
                              if (done) ref.invalidate(orgBookingsProvider(orgId));
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

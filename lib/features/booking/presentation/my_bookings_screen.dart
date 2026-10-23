import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/async_body.dart';
import '../data/booking_repository.dart';
import '../domain/booking.dart';

class MyBookingsScreen extends ConsumerWidget {
  const MyBookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(myBookingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My bookings')),
      body: AsyncBody<List<Booking>>(
        value: bookings,
        onRetry: () => ref.invalidate(myBookingsProvider),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyState(icon: Icons.event_note, message: 'No bookings yet.');
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myBookingsProvider),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: items.length,
              itemBuilder: (context, i) => _BookingCard(booking: items[i]),
            ),
          );
        },
      ),
    );
  }
}

class _BookingCard extends ConsumerWidget {
  const _BookingCard({required this.booking});

  final Booking booking;

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(bookingRepositoryProvider).cancel(booking.id);
      ref.invalidate(myBookingsProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expired = booking.isUnpaid && booking.expiresAt != null && booking.expiresAt!.isBefore(DateTime.now());
    final label = expired ? 'expired' : booking.status.replaceAll('_', ' ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(booking.serviceTitle ?? 'Booking', style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Chip(label: Text(label), visualDensity: VisualDensity.compact),
              ],
            ),
            Text(formatDateTime(booking.startsAt)),
            Text(formatKes(booking.totalCents)),
            if (booking.isUnpaid && !expired)
              Row(
                children: [
                  TextButton(onPressed: () => context.push('/checkout/${booking.id}'), child: const Text('Pay now')),
                  TextButton(onPressed: () => _cancel(context, ref), child: const Text('Cancel')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

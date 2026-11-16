import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/async_body.dart';
import '../../discover/data/service_repository.dart';
import '../../discover/domain/service.dart';
import '../data/booking_repository.dart';
import '../domain/booking.dart';

class BookingScreen extends ConsumerWidget {
  const BookingScreen({super.key, required this.serviceId});

  final String serviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(serviceProvider(serviceId));
    return Scaffold(
      appBar: AppBar(title: const Text('Choose your booking')),
      body: AsyncBody<Service>(
        value: service,
        onRetry: () => ref.invalidate(serviceProvider(serviceId)),
        data: (s) => switch (s.mode) {
          BookingMode.appointment => _SlotPicker(service: s),
          BookingMode.resource => _SlotPicker(service: s, resource: true),
          BookingMode.event => _TierPicker(service: s),
        },
      ),
    );
  }
}

void _showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(error))));
}

/// Picks a new time for a paid booking. Same calendar as booking, but choosing a slot moves the booking.
class RescheduleScreen extends ConsumerWidget {
  const RescheduleScreen({super.key, required this.bookingId, required this.serviceId});

  final String bookingId;
  final String serviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(serviceProvider(serviceId));
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a new time')),
      body: AsyncBody<Service>(
        value: service,
        onRetry: () => ref.invalidate(serviceProvider(serviceId)),
        data: (s) => _SlotPicker(
          service: s,
          resource: s.mode == BookingMode.resource,
          onPick: (slot) async {
            await ref.read(bookingRepositoryProvider).reschedule(bookingId, slot);
            ref.invalidate(myBookingsProvider);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Moved to ${formatDateTime(slot.start)}.')));
              context.pop();
            }
          },
        ),
      ),
    );
  }
}

class _SlotPicker extends ConsumerStatefulWidget {
  const _SlotPicker({required this.service, this.resource = false, this.onPick});

  final Service service;

  /// Replaces the default "hold the slot and go to checkout" when the slot is for something else (rescheduling).
  final Future<void> Function(Slot slot)? onPick;

  /// A room or court: one shared calendar, no choice of staff.
  final bool resource;

  @override
  ConsumerState<_SlotPicker> createState() => _SlotPickerState();
}

class _SlotPickerState extends ConsumerState<_SlotPicker> {
  late final List<DateTime> _days;
  late DateTime _selected;
  // null means anyone free at that time
  String? _staffId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _days = [for (var i = 0; i < 14; i++) DateTime(today.year, today.month, today.day + i)];
    _selected = _days.first;
  }

  Future<void> _hold(Slot slot) async {
    setState(() => _busy = true);
    try {
      if (widget.onPick != null) {
        await widget.onPick!(slot);
      } else {
        final id = await ref.read(bookingRepositoryProvider).holdAppointment(serviceId: widget.service.id, slot: slot);
        if (mounted) context.push('/checkout/$id');
      }
    } catch (e) {
      if (mounted) {
        _showError(context, e);
        ref.invalidate(slotsProvider);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final slots = ref.watch(slotsProvider((serviceId: widget.service.id, date: _selected, staffId: _staffId, resource: widget.resource)));
    // Choosing only makes sense with more than one person; a failed load just leaves "anyone".
    final staff = widget.resource ? const <StaffMember>[] : ref.watch(staffProvider(widget.service.id)).valueOrNull ?? const [];

    return Column(
      children: [
        if (staff.length > 1)
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              children: [
                for (final (id, name) in [(null, 'Anyone'), for (final m in staff) (m.id, m.name)])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(name),
                      selected: _staffId == id,
                      onSelected: (_) => setState(() => _staffId = id),
                    ),
                  ),
              ],
            ),
          ),
        SizedBox(
          height: 72,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: _days.length,
            itemBuilder: (context, i) {
              final day = _days[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(formatDay(day)),
                  selected: day == _selected,
                  onSelected: (_) => setState(() => _selected = day),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: AsyncBody<List<Slot>>(
            value: slots,
            onRetry: () => ref.invalidate(slotsProvider),
            data: (all) {
              // Several staff can offer the same time; show each time once.
              final seen = <int>{};
              final unique = [for (final s in all) if (seen.add(s.start.millisecondsSinceEpoch)) s];
              if (unique.isEmpty) {
                return const EmptyState(icon: Icons.event_busy, message: 'No free times on this day. Try another date.');
              }
              return GridView.count(
                crossAxisCount: 3,
                padding: const EdgeInsets.all(16),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.2,
                children: [
                  for (final slot in unique)
                    OutlinedButton(
                      onPressed: _busy ? null : () => _hold(slot),
                      child: Text(formatTime(slot.start.toLocal())),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TierPicker extends ConsumerStatefulWidget {
  const _TierPicker({required this.service});

  final Service service;

  @override
  ConsumerState<_TierPicker> createState() => _TierPickerState();
}

class _TierPickerState extends ConsumerState<_TierPicker> {
  String? _tierId;
  int _quantity = 1;
  bool _busy = false;

  Future<void> _hold() async {
    setState(() => _busy = true);
    try {
      final id = await ref
          .read(bookingRepositoryProvider)
          .holdTickets(serviceId: widget.service.id, tierId: _tierId!, quantity: _quantity);
      if (mounted) context.push('/checkout/$id');
    } catch (e) {
      if (mounted) {
        _showError(context, e);
        ref.invalidate(tiersProvider(widget.service.id));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tiers = ref.watch(tiersProvider(widget.service.id));

    return AsyncBody<List<TicketTier>>(
      value: tiers,
      onRetry: () => ref.invalidate(tiersProvider(widget.service.id)),
      data: (items) {
        TicketTier? chosen;
        for (final t in items) {
          if (t.id == _tierId) chosen = t;
        }
        return RadioGroup<String>(
          groupValue: _tierId,
          onChanged: (v) => setState(() => _tierId = v),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final t in items)
                Card(
                  child: RadioListTile<String>(
                    value: t.id,
                    enabled: t.remaining > 0,
                    title: Text(t.name),
                    subtitle: Text(t.remaining <= 0 ? 'Sold out' : '${t.remaining} left'),
                    secondary: Text(formatKes(t.priceCents)),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Quantity'),
                  const Spacer(),
                  IconButton(
                    onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$_quantity', style: Theme.of(context).textTheme.titleMedium),
                  IconButton(
                    onPressed: _quantity < 10 ? () => setState(() => _quantity++) : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: (_tierId == null || _busy) ? null : _hold,
                child: Text(chosen == null ? 'Choose a ticket type' : 'Continue · ${formatKes(chosen.priceCents * _quantity)}'),
              ),
            ],
          ),
        );
      },
    );
  }
}

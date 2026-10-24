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
          BookingMode.event => _TierPicker(service: s),
          BookingMode.resource => const EmptyState(icon: Icons.construction, message: 'Coming soon.'),
        },
      ),
    );
  }
}

void _showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(error))));
}

class _SlotPicker extends ConsumerStatefulWidget {
  const _SlotPicker({required this.service});

  final Service service;

  @override
  ConsumerState<_SlotPicker> createState() => _SlotPickerState();
}

class _SlotPickerState extends ConsumerState<_SlotPicker> {
  late final List<DateTime> _days;
  late DateTime _selected;
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
      final id = await ref.read(bookingRepositoryProvider).holdAppointment(serviceId: widget.service.id, slot: slot);
      if (mounted) context.push('/checkout/$id');
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
    final slots = ref.watch(slotsProvider((serviceId: widget.service.id, date: _selected)));

    return Column(
      children: [
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

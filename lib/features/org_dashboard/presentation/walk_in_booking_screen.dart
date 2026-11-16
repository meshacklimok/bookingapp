import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/async_body.dart';
import '../../discover/data/service_repository.dart';
import '../../discover/domain/service.dart';
import '../data/org_repository.dart';
import '../domain/managed_service.dart';

const _paymentMethods = {
  'cash': 'Cash',
  'mpesa': 'M-Pesa (to the till)',
  'card': 'Card',
  'unpaid': 'Not paid yet',
  'other': 'Other',
};

/// A member books someone who has no account: at the counter or over the phone. Confirmed straight away, paid at the
/// venue, and kept out of earnings and payouts because the organization already has the money.
class WalkInBookingScreen extends ConsumerStatefulWidget {
  const WalkInBookingScreen({super.key, required this.orgId});

  final String orgId;

  @override
  ConsumerState<WalkInBookingScreen> createState() => _WalkInBookingScreenState();
}

class _WalkInBookingScreenState extends ConsumerState<WalkInBookingScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _amount = TextEditingController();
  final _notes = TextEditingController();

  ManagedService? _service;
  String? _staffId;
  String? _tierId;
  int _quantity = 1;
  DateTime? _startsAt;
  String _payment = 'cash';
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _startsAt ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startsAt ?? now),
    );
    if (time == null) return;
    setState(() => _startsAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    final service = _service;
    if (service == null || !_form.currentState!.validate()) return;
    final timed = service.mode != BookingMode.event;
    if (timed && _startsAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose a date and time.')));
      return;
    }
    final shillings = double.tryParse(_amount.text.trim());
    setState(() => _saving = true);
    try {
      await ref.read(orgRepositoryProvider).createWalkIn(
            serviceId: service.id,
            guestName: _name.text.trim(),
            guestPhone: _phone.text.trim(),
            startsAt: timed ? _startsAt : null,
            staffId: service.mode == BookingMode.appointment ? _staffId : null,
            tierId: service.mode == BookingMode.event ? _tierId : null,
            quantity: service.mode == BookingMode.event ? _quantity : 1,
            totalCents: shillings == null ? null : (shillings * 100).round(),
            paymentMethod: _payment,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking added.')));
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(orgServicesProvider(widget.orgId));
    return Scaffold(
      appBar: AppBar(title: const Text('Add a booking')),
      body: AsyncBody<List<ManagedService>>(
        value: services,
        onRetry: () => ref.invalidate(orgServicesProvider(widget.orgId)),
        data: (all) {
          final active = all.where((s) => s.isActive).toList();
          if (active.isEmpty) {
            return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Add a service first.')));
          }
          return Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<ManagedService>(
                  value: _service,
                  decoration: const InputDecoration(labelText: 'Service'),
                  items: [for (final s in active) DropdownMenuItem(value: s, child: Text(s.title))],
                  validator: (v) => v == null ? 'Choose a service' : null,
                  onChanged: (s) => setState(() {
                    _service = s;
                    _staffId = null;
                    _tierId = null;
                    _quantity = 1;
                    _amount.clear();
                  }),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Customer name'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone (optional)'),
                ),
                if (_service != null) ..._serviceFields(_service!),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Amount in KES (optional)',
                    helperText: _service == null ? null : 'Leave empty for the list price',
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return null;
                    final n = double.tryParse(t);
                    return n == null || n < 0 ? 'Enter a valid amount' : null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _payment,
                  decoration: const InputDecoration(labelText: 'Payment'),
                  items: [for (final e in _paymentMethods.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => setState(() => _payment = v ?? 'cash'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Add booking'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Walk-in bookings are not charged through the app, so they do not count towards earnings or payouts.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _serviceFields(ManagedService service) {
    switch (service.mode) {
      case BookingMode.event:
        final tiers = ref.watch(tiersProvider(service.id));
        return [
          const SizedBox(height: 12),
          tiers.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text(friendlyError(e)),
            data: (list) => Column(children: [
              DropdownButtonFormField<String>(
                value: _tierId,
                decoration: const InputDecoration(labelText: 'Ticket type'),
                items: [
                  for (final t in list)
                    DropdownMenuItem(
                      value: t.id,
                      enabled: t.remaining > 0,
                      child: Text('${t.name} · ${formatKes(t.priceCents)} · ${t.remaining} left'),
                    ),
                ],
                validator: (v) => v == null ? 'Choose a ticket type' : null,
                onChanged: (v) => setState(() => _tierId = v),
              ),
              const SizedBox(height: 12),
              Row(children: [
                const Text('Tickets'),
                const Spacer(),
                IconButton(
                  onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$_quantity'),
                IconButton(
                  onPressed: _quantity < 10 ? () => setState(() => _quantity++) : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ]),
            ]),
          ),
        ];
      case BookingMode.appointment:
        final staff = ref.watch(serviceStaffProvider(service.id));
        return [
          const SizedBox(height: 12),
          staff.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text(friendlyError(e)),
            data: (list) => DropdownButtonFormField<String>(
              value: _staffId,
              decoration: InputDecoration(
                labelText: 'With',
                helperText: list.isEmpty ? 'Nobody is set up for this service yet' : null,
              ),
              items: [for (final s in list) DropdownMenuItem(value: s.userId, child: Text(s.name))],
              validator: (v) => v == null ? 'Choose who the appointment is with' : null,
              onChanged: (v) => setState(() => _staffId = v),
            ),
          ),
          const SizedBox(height: 12),
          _timeTile(),
        ];
      case BookingMode.resource:
        return [const SizedBox(height: 12), _timeTile()];
    }
  }

  Widget _timeTile() => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.schedule),
        title: Text(_startsAt == null ? 'Choose date and time' : formatDateTime(_startsAt!)),
        trailing: const Icon(Icons.chevron_right),
        onTap: _pickTime,
      );
}

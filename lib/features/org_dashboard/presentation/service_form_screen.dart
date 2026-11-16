import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/async_body.dart';
import '../../booking/domain/cancellation.dart';
import '../../booking/domain/deposit.dart';
import '../../discover/domain/service.dart';
import '../data/org_repository.dart';
import '../domain/managed_service.dart';
import '../domain/organization.dart';

/// Creates a service, or edits one when [serviceId] is given.
class ServiceFormScreen extends ConsumerWidget {
  const ServiceFormScreen({super.key, required this.orgId, this.serviceId});

  final String orgId;
  final String? serviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = serviceId;
    return Scaffold(
      appBar: AppBar(title: Text(id == null ? 'New service' : 'Edit service')),
      body: id == null
          ? _ServiceForm(orgId: orgId)
          : AsyncBody<(ManagedService, List<TicketTier>)>(
              value: ref.watch(serviceEditorProvider(id)),
              onRetry: () => ref.invalidate(serviceEditorProvider(id)),
              data: (loaded) => _ServiceForm(orgId: orgId, service: loaded.$1, tiers: loaded.$2),
            ),
    );
  }
}

class _TierFields {
  _TierFields({this.id, this.sold = 0, String name = '', String price = '', String quantity = ''})
      : name = TextEditingController(text: name),
        price = TextEditingController(text: price),
        quantity = TextEditingController(text: quantity);

  final String? id;
  final int sold;
  final TextEditingController name;
  final TextEditingController price;
  final TextEditingController quantity;

  void dispose() {
    name.dispose();
    price.dispose();
    quantity.dispose();
  }

  TierDraft? toDraft() {
    final cents = parseKesToCents(price.text);
    final qty = int.tryParse(quantity.text.trim());
    if (cents == null || qty == null) return null;
    return TierDraft(id: id, name: name.text, priceCents: cents, quantity: qty);
  }
}

String _plainKes(int cents) => cents % 100 == 0 ? '${cents ~/ 100}' : (cents / 100).toStringAsFixed(2);

class _ServiceForm extends ConsumerStatefulWidget {
  const _ServiceForm({required this.orgId, this.service, this.tiers = const []});

  final String orgId;
  final ManagedService? service;
  final List<TicketTier> tiers;

  @override
  ConsumerState<_ServiceForm> createState() => _ServiceFormState();
}

class _ServiceFormState extends ConsumerState<_ServiceForm> {
  final _formKey = GlobalKey<FormState>();
  late final ManagedService? _existing = widget.service;
  late BookingMode _mode = _existing?.mode ?? BookingMode.appointment;
  late final _title = TextEditingController(text: _existing?.title);
  late final _description = TextEditingController(text: _existing?.description);
  late final _location = TextEditingController(text: _existing?.location);
  late final _price = TextEditingController(text: _existing == null ? '' : _plainKes(_existing.priceCents));
  late final _duration = TextEditingController(text: '${_existing?.durationMin ?? 60}');
  late final _buffer = TextEditingController(text: '${_existing?.bufferMin ?? 0}');
  late String? _category = _existing?.category;
  late bool _active = _existing?.isActive ?? true;
  late int _freeCancelHours = _existing?.freeCancelHours ?? 24;
  late int _lateRefundPct = _existing?.lateRefundPct ?? 0;
  late int? _depositPct = _existing?.depositPct;
  late DateTime? _starts = _existing?.eventStartsAt?.toLocal();
  late DateTime? _ends = _existing?.eventEndsAt?.toLocal();
  late String _openTime = _existing?.openTime ?? defaultOpenTime;
  late String _closeTime = _existing?.closeTime ?? defaultCloseTime;
  late final List<_TierFields> _tiers = [
    for (final t in widget.tiers)
      _TierFields(id: t.id, sold: t.sold, name: t.name, price: _plainKes(t.priceCents), quantity: '${t.quantity}'),
  ];
  // Set once the service row exists, so a retry after a failed tier write updates instead of duplicating.
  late String? _savedId = _existing?.id;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    if (_tiers.isEmpty && _mode == BookingMode.event) _tiers.add(_TierFields());
  }

  @override
  void dispose() {
    for (final c in [_title, _description, _location, _price, _duration, _buffer]) {
      c.dispose();
    }
    for (final t in _tiers) {
      t.dispose();
    }
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(DateTime? initial) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial ?? now.add(const Duration(days: 7)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial ?? DateTime(2000, 1, 1, 18)),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<String?> _pickTime(String current) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(current.substring(0, 2)), minute: int.parse(current.substring(3, 5))),
    );
    if (picked == null) return null;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(picked.hour)}:${two(picked.minute)}';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final isEvent = _mode == BookingMode.event;

    if (_mode == BookingMode.resource) {
      final hoursError = validateOpeningHours(_openTime, _closeTime, slotMinutes: int.tryParse(_duration.text.trim()) ?? 60);
      if (hoursError != null) return setState(() => _message = hoursError);
    }

    List<TierDraft> tierDrafts = const [];
    if (isEvent) {
      final started = _existing?.eventStartsAt;
      final alreadyStarted = started != null && !started.isAfter(DateTime.now());
      final windowError = validateEventWindow(_starts, _ends, requireFuture: !alreadyStarted);
      if (windowError != null) return setState(() => _message = windowError);
      tierDrafts = [for (final t in _tiers) if (t.toDraft() != null) t.toDraft()!];
      final tierError = validateTiers(tierDrafts, sold: {for (final t in widget.tiers) t.id: t.sold});
      if (tierError != null) return setState(() => _message = tierError);
      final blocked = undeletableTiers(widget.tiers, tierDrafts);
      if (blocked.isNotEmpty) {
        return setState(() => _message = '"${blocked.first}" has tickets sold, so it cannot be removed. Set its quantity to what is sold instead.');
      }
    }

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final repo = ref.read(orgRepositoryProvider);
      final draft = ServiceDraft(
        title: _title.text,
        mode: _mode,
        description: _description.text,
        category: _category,
        location: _location.text,
        priceCents: isEvent ? 0 : parseKesToCents(_price.text) ?? 0,
        durationMin: int.tryParse(_duration.text.trim()) ?? 60,
        bufferMin: int.tryParse(_buffer.text.trim()) ?? 0,
        eventStartsAt: _starts,
        eventEndsAt: _ends,
        isActive: _active,
        freeCancelHours: _freeCancelHours,
        lateRefundPct: _lateRefundPct,
        depositPct: isEvent ? null : _depositPct,
        openTime: _openTime,
        closeTime: _closeTime,
      );
      _savedId = await repo.saveService(widget.orgId, draft, serviceId: _savedId);
      if (isEvent) {
        final saved = await repo.tiers(_savedId!);
        await repo.syncTiers(_savedId!, saved, tierDrafts);
      }
      ref.invalidate(orgServicesProvider(widget.orgId));
      ref.invalidate(serviceEditorProvider(_savedId!));
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) setState(() => _message = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEvent = _mode == BookingMode.event;
    final editing = _existing != null;
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<BookingMode>(
            segments: const [
              ButtonSegment(value: BookingMode.appointment, label: Text('Appointment'), icon: Icon(Icons.event_available_outlined)),
              ButtonSegment(value: BookingMode.event, label: Text('Event'), icon: Icon(Icons.confirmation_number_outlined)),
              ButtonSegment(value: BookingMode.resource, label: Text('Space'), icon: Icon(Icons.meeting_room_outlined)),
            ],
            selected: {_mode},
            // Switching type after people booked would corrupt those bookings; the database refuses it too.
            onSelectionChanged: editing
                ? null
                : (s) => setState(() {
                      _mode = s.first;
                      if (_mode == BookingMode.event && _tiers.isEmpty) _tiers.add(_TierFields());
                    }),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
            textCapitalization: TextCapitalization.sentences,
            validator: validateServiceTitle,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _description,
            decoration: const InputDecoration(labelText: 'Description (optional)'),
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: orgCategories.contains(_category) ? _category : null,
            decoration: const InputDecoration(labelText: 'Category (optional)'),
            items: [for (final c in orgCategories) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (v) => setState(() => _category = v),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _location,
            decoration: const InputDecoration(labelText: 'Location (optional)'),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 20),
          if (!isEvent) ...[
            TextFormField(
              controller: _price,
              decoration: InputDecoration(
                labelText: _mode == BookingMode.resource ? 'Price per booking' : 'Price',
                prefixText: 'KES ',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: validatePrice,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _duration,
                    decoration: const InputDecoration(labelText: 'Duration (min)'),
                    keyboardType: TextInputType.number,
                    validator: (v) => validatePositiveInt(v, label: 'minutes'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _buffer,
                    decoration: const InputDecoration(labelText: 'Buffer after (min)'),
                    keyboardType: TextInputType.number,
                    validator: validateNonNegativeInt,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_mode == BookingMode.resource) ...[
              _TimeTile(
                label: 'Opens',
                value: _openTime,
                onPick: () async {
                  final v = await _pickTime(_openTime);
                  if (v != null) setState(() => _openTime = v);
                },
              ),
              _TimeTile(
                label: 'Closes',
                value: _closeTime,
                onPick: () async {
                  final v = await _pickTime(_closeTime);
                  if (v != null) setState(() => _closeTime = v);
                },
              ),
              Text(
                'Customers book one slot of the length above, every day between opening and closing. Each slot can be booked by one customer at a time.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else
              Text(
                'Customers can pick a time once a staff member is linked to this service and has weekly hours (Staff and hours).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
          if (isEvent) ...[
            _DateTimeTile(
              label: 'Starts',
              value: _starts,
              onPick: () async {
                final v = await _pickDateTime(_starts);
                if (v != null) setState(() => _starts = v);
              },
            ),
            _DateTimeTile(
              label: 'Ends (optional)',
              value: _ends,
              onPick: () async {
                final v = await _pickDateTime(_ends ?? _starts);
                if (v != null) setState(() => _ends = v);
              },
              onClear: _ends == null ? null : () => setState(() => _ends = null),
            ),
            const SizedBox(height: 12),
            Text('Ticket types', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (var i = 0; i < _tiers.length; i++) _tierCard(i),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _tiers.add(_TierFields())),
                icon: const Icon(Icons.add),
                label: const Text('Add ticket type'),
              ),
            ),
          ],
          if (!isEvent) ...[
            const Divider(height: 32),
            Text('Deposit', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              initialValue: _depositPct,
              decoration: const InputDecoration(labelText: 'Customers can book with a deposit of'),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('No deposit (pay in full)')),
                for (final p in {...depositOptions, if (_depositPct != null) _depositPct!}.toList()..sort()) DropdownMenuItem<int?>(value: p, child: Text('$p%')),
              ],
              onChanged: (v) => setState(() => _depositPct = v),
            ),
            const SizedBox(height: 8),
            Text(
              _depositPct == null
                  ? 'Customers pay the full price online.'
                  : 'Customers may pay $_depositPct% online and the rest to you at the venue. The platform fee is taken on the '
                      'online payment only, and cancellations refund the deposit by your cancellation policy.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const Divider(height: 32),
          Text('Cancellations', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _freeCancelHours,
            decoration: const InputDecoration(labelText: 'Free cancellation until'),
            items: [
              for (final h in {...cancelWindowOptions, _freeCancelHours}.toList()..sort())
                DropdownMenuItem(value: h, child: Text(h == 0 ? 'The start time' : cancellationWindowLabel(h))),
            ],
            onChanged: (v) => setState(() => _freeCancelHours = v ?? 24),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _lateRefundPct,
            decoration: const InputDecoration(labelText: 'Refund after that'),
            items: [
              for (final p in {...lateRefundOptions, _lateRefundPct}.toList()..sort())
                DropdownMenuItem(value: p, child: Text(p == 0 ? 'No refund' : '$p%')),
            ],
            onChanged: _freeCancelHours == 0 ? null : (v) => setState(() => _lateRefundPct = v ?? 0),
          ),
          const SizedBox(height: 8),
          Text(
            '${cancellationPolicyText(_freeCancelHours, _freeCancelHours == 0 ? 0 : _lateRefundPct)} '
            'If you cancel, the customer is always refunded in full.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (editing) ...[
            const Divider(height: 32),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              subtitle: const Text('Inactive services are hidden from customers. Existing bookings are kept.'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(editing ? 'Save changes' : 'Create service'),
          ),
        ],
      ),
    );
  }

  Widget _tierCard(int i) {
    final t = _tiers[i];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: t.name,
                    decoration: const InputDecoration(labelText: 'Name', hintText: 'General, VIP…'),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name' : null,
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _tiers.length <= 1
                      ? null
                      : () => setState(() {
                            _tiers.removeAt(i).dispose();
                          }),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: t.price,
                    decoration: const InputDecoration(labelText: 'Price', prefixText: 'KES '),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: validatePrice,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: t.quantity,
                    decoration: InputDecoration(labelText: 'Quantity', helperText: t.sold > 0 ? '${t.sold} sold' : null),
                    keyboardType: TextInputType.number,
                    validator: (v) => validatePositiveInt(v, label: 'a quantity', max: 100000),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DateTimeTile extends StatelessWidget {
  const _DateTimeTile({required this.label, required this.value, required this.onPick, this.onClear});

  final String label;
  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.schedule),
      title: Text(label),
      subtitle: Text(value == null ? 'Not set' : formatDateTime(value!)),
      trailing: onClear == null ? null : IconButton(icon: const Icon(Icons.clear), onPressed: onClear),
      onTap: onPick,
    );
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({required this.label, required this.value, required this.onPick});

  final String label;
  final String value;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.access_time),
      title: Text(label),
      trailing: Text(value, style: Theme.of(context).textTheme.titleMedium),
      onTap: onPick,
    );
  }
}

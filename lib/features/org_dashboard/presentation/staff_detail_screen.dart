import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/async_body.dart';
import '../../discover/domain/service.dart';
import '../data/org_repository.dart';
import '../domain/managed_service.dart';
import '../domain/staff.dart';

class StaffDetailScreen extends ConsumerWidget {
  const StaffDetailScreen({super.key, required this.orgId, required this.staffId});

  final String orgId;
  final String staffId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (orgId, staffId);
    final name = ref.watch(orgStaffProvider(orgId)).valueOrNull?.where((s) => s.userId == staffId).firstOrNull?.name;
    final schedule = ref.watch(staffScheduleProvider(key));
    final services = ref.watch(orgServicesProvider(orgId));

    return Scaffold(
      appBar: AppBar(title: Text(name ?? 'Staff member')),
      body: AsyncBody<StaffSchedule>(
        value: schedule,
        onRetry: () => ref.invalidate(staffScheduleProvider(key)),
        data: (s) {
          final appointments = (services.valueOrNull ?? const <ManagedService>[]).where((x) => x.mode == BookingMode.appointment).toList();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(staffScheduleProvider(key)),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Readiness(schedule: s),
                const SizedBox(height: 8),
                Text('Services they offer', style: Theme.of(context).textTheme.titleMedium),
                if (appointments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Create an appointment service first, then link it here.'),
                  ),
                for (final service in appointments)
                  _ServiceCheckbox(orgId: orgId, staffId: staffId, service: service, linked: s.serviceIds.contains(service.id)),
                const Divider(height: 32),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.schedule),
                    title: const Text('Weekly hours'),
                    subtitle: Text(summarizeHours(s.hours)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/org/$orgId/staff/$staffId/hours'),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: Text('Days off and special hours', style: Theme.of(context).textTheme.titleMedium)),
                    TextButton.icon(
                      onPressed: () => _addException(context, ref),
                      icon: const Icon(Icons.add),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                if (s.exceptions.isEmpty) const Text('None coming up.'),
                for (final e in s.exceptions)
                  Card(
                    child: ListTile(
                      title: Text(formatDay(e.date)),
                      subtitle: Text(e.isClosed ? 'Day off' : 'Open ${e.window?.label ?? ''} only'),
                      trailing: IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteException(context, ref, e),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Days off stop new bookings for that day. Bookings already made are not cancelled.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _addException(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<({DateTime date, TimeWindow? window})>(
      context: context,
      builder: (_) => const _ExceptionDialog(),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref.read(orgRepositoryProvider).saveException(orgId, staffId, result.date, window: result.window);
      ref.invalidate(staffScheduleProvider((orgId, staffId)));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _deleteException(BuildContext context, WidgetRef ref, DayException e) async {
    try {
      await ref.read(orgRepositoryProvider).deleteException(e.id);
      ref.invalidate(staffScheduleProvider((orgId, staffId)));
    } catch (err) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(err))));
    }
  }
}

/// Tells the owner why customers cannot book this person yet.
class _Readiness extends StatelessWidget {
  const _Readiness({required this.schedule});

  final StaffSchedule schedule;

  @override
  Widget build(BuildContext context) {
    final missing = [
      if (schedule.serviceIds.isEmpty) 'link at least one service',
      if (schedule.hours.isEmpty) 'set weekly hours',
    ];
    final scheme = Theme.of(context).colorScheme;
    final ready = missing.isEmpty;
    return Card(
      color: ready ? scheme.primaryContainer : scheme.tertiaryContainer,
      child: ListTile(
        leading: Icon(ready ? Icons.check_circle_outline : Icons.info_outline),
        title: Text(ready ? 'Bookable' : 'Not bookable yet'),
        subtitle: Text(ready ? 'Customers can pick times with this person.' : 'To appear in the time picker: ${missing.join(' and ')}.'),
      ),
    );
  }
}

class _ServiceCheckbox extends ConsumerStatefulWidget {
  const _ServiceCheckbox({required this.orgId, required this.staffId, required this.service, required this.linked});

  final String orgId;
  final String staffId;
  final ManagedService service;
  final bool linked;

  @override
  ConsumerState<_ServiceCheckbox> createState() => _ServiceCheckboxState();
}

class _ServiceCheckboxState extends ConsumerState<_ServiceCheckbox> {
  bool _busy = false;

  Future<void> _toggle(bool on) async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(orgRepositoryProvider);
      if (on) {
        await repo.linkService(widget.staffId, widget.service.id);
      } else {
        await repo.unlinkService(widget.staffId, widget.service.id);
      }
      ref.invalidate(staffScheduleProvider((widget.orgId, widget.staffId)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      value: widget.linked,
      onChanged: _busy ? null : (v) => _toggle(v ?? false),
      title: Text(widget.service.title),
      subtitle: Text('${widget.service.durationMin} min · ${formatKes(widget.service.priceCents)}${widget.service.isActive ? '' : ' · inactive'}'),
    );
  }
}

class _ExceptionDialog extends StatefulWidget {
  const _ExceptionDialog();

  @override
  State<_ExceptionDialog> createState() => _ExceptionDialogState();
}

class _ExceptionDialogState extends State<_ExceptionDialog> {
  DateTime? _date;
  bool _custom = false;
  int _start = 9 * 60;
  int _end = 13 * 60;
  String? _error;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? now.add(const Duration(days: 1)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime(bool start) async {
    final minutes = start ? _start : _end;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60));
    if (t != null) setState(() => start ? _start = t.hour * 60 + t.minute : _end = t.hour * 60 + t.minute);
  }

  void _submit() {
    final date = _date;
    if (date == null) return setState(() => _error = 'Choose a date');
    final window = _custom ? TimeWindow(_start, _end) : null;
    if (window != null && window.endMin <= window.startMin) return setState(() => _error = 'The end must be after the start');
    Navigator.pop(context, (date: date, window: window));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Day off or special hours'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today),
            label: Text(_date == null ? 'Choose date' : formatDay(_date!)),
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Day off')),
              ButtonSegment(value: true, label: Text('Custom hours')),
            ],
            selected: {_custom},
            onSelectionChanged: (s) => setState(() => _custom = s.first),
          ),
          if (_custom) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton(onPressed: () => _pickTime(true), child: Text(formatMinutes(_start))),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('to')),
                OutlinedButton(onPressed: () => _pickTime(false), child: Text(formatMinutes(_end))),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

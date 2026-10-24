import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/errors.dart';
import '../../../shared/widgets/async_body.dart';
import '../data/org_repository.dart';
import '../domain/staff.dart';

/// Edits one person's repeating weekly hours. Times are Nairobi local time, like the slot picker.
class StaffHoursScreen extends ConsumerWidget {
  const StaffHoursScreen({super.key, required this.orgId, required this.staffId});

  final String orgId;
  final String staffId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (orgId, staffId);
    return Scaffold(
      appBar: AppBar(title: const Text('Weekly hours')),
      body: AsyncBody<StaffSchedule>(
        value: ref.watch(staffScheduleProvider(key)),
        onRetry: () => ref.invalidate(staffScheduleProvider(key)),
        data: (s) => _HoursEditor(orgId: orgId, staffId: staffId, initial: s.hours),
      ),
    );
  }
}

class _HoursEditor extends ConsumerStatefulWidget {
  const _HoursEditor({required this.orgId, required this.staffId, required this.initial});

  final String orgId;
  final String staffId;
  final WeeklyHours initial;

  @override
  ConsumerState<_HoursEditor> createState() => _HoursEditorState();
}

class _HoursEditorState extends ConsumerState<_HoursEditor> {
  late final WeeklyHours _hours = {for (final e in widget.initial.entries) e.key: [...e.value]};
  bool _busy = false;
  String? _message;

  Future<int?> _pickMinutes(int initial) async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: initial ~/ 60, minute: initial % 60));
    return t == null ? null : t.hour * 60 + t.minute;
  }

  Future<void> _addWindow(int day) async {
    final existing = _hours[day] ?? const <TimeWindow>[];
    final start = await _pickMinutes(existing.isEmpty ? 9 * 60 : existing.last.endMin);
    if (start == null || !mounted) return;
    final end = await _pickMinutes((start + 4 * 60).clamp(0, 23 * 60 + 59));
    if (end == null) return;
    setState(() {
      (_hours[day] ??= []).add(TimeWindow(start, end));
      _hours[day]!.sort((a, b) => a.startMin.compareTo(b.startMin));
      _message = null;
    });
  }

  Future<void> _save() async {
    final problem = validateWeeklyHours(_hours);
    if (problem != null) return setState(() => _message = problem);
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref.read(orgRepositoryProvider).setHours(widget.orgId, widget.staffId, _hours);
      ref.invalidate(staffScheduleProvider((widget.orgId, widget.staffId)));
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) setState(() => _message = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () => setState(() {
                _hours
                  ..clear()
                  ..addAll(weekdayPreset());
              }),
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('Mon–Fri 09:00–17:00'),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: () => setState(_hours.clear), child: const Text('Clear')),
          ],
        ),
        const SizedBox(height: 8),
        for (final day in weekdayOrder)
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 96, child: Padding(padding: const EdgeInsets.only(top: 8), child: Text(weekdayNames[day]!))),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if ((_hours[day] ?? const []).isEmpty)
                          const Padding(padding: EdgeInsets.only(top: 8), child: Text('Off')),
                        for (final w in _hours[day] ?? const <TimeWindow>[])
                          InputChip(
                            label: Text(w.label),
                            onDeleted: () => setState(() {
                              _hours[day]!.remove(w);
                              _message = null;
                            }),
                          ),
                      ],
                    ),
                  ),
                  IconButton(tooltip: 'Add hours', icon: const Icon(Icons.add), onPressed: () => _addWindow(day)),
                ],
              ),
            ),
          ),
        if (_message != null) ...[
          const SizedBox(height: 8),
          Text(_message!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save hours'),
        ),
      ],
    );
  }
}

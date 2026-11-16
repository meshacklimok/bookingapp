import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/async_body.dart';
import '../data/org_repository.dart';
import '../domain/managed_service.dart' show parseKesToCents;
import '../domain/promo.dart';

class PromoCodesScreen extends ConsumerWidget {
  const PromoCodesScreen({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final codes = ref.watch(orgPromoCodesProvider(orgId));
    return Scaffold(
      appBar: AppBar(title: const Text('Promo codes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            builder: (_) => _NewCodeSheet(orgId: orgId),
          );
          if (created == true) ref.invalidate(orgPromoCodesProvider(orgId));
        },
        icon: const Icon(Icons.add),
        label: const Text('New code'),
      ),
      body: AsyncBody<List<PromoCode>>(
        value: codes,
        onRetry: () => ref.invalidate(orgPromoCodesProvider(orgId)),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyState(icon: Icons.sell_outlined, message: 'No promo codes yet. Customers enter them at checkout.');
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(orgPromoCodesProvider(orgId)),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
              children: [for (final c in items) _CodeTile(code: c, orgId: orgId)],
            ),
          );
        },
      ),
    );
  }
}

class _CodeTile extends ConsumerWidget {
  const _CodeTile({required this.code, required this.orgId});

  final PromoCode code;
  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final state = code.isExpired(now) ? 'expired' : (code.isUsedUp ? 'used up' : (code.isActive ? null : 'off'));
    final details = [
      code.discountLabel,
      code.maxUses == null ? '${code.uses} used' : '${code.uses} of ${code.maxUses} used',
      if (code.validUntil != null) 'until ${formatDay(code.validUntil!.toLocal())}',
      if (state != null) state,
    ].join(' · ');
    return Card(
      child: ListTile(
        title: Text(code.code, style: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 1)),
        subtitle: Text(details),
        trailing: Switch(
          value: code.isActive,
          onChanged: (v) async {
            try {
              await ref.read(orgRepositoryProvider).setPromoActive(code.id, v);
              ref.invalidate(orgPromoCodesProvider(orgId));
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
              }
            }
          },
        ),
      ),
    );
  }
}

class _NewCodeSheet extends ConsumerStatefulWidget {
  const _NewCodeSheet({required this.orgId});

  final String orgId;

  @override
  ConsumerState<_NewCodeSheet> createState() => _NewCodeSheetState();
}

class _NewCodeSheetState extends ConsumerState<_NewCodeSheet> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _value = TextEditingController();
  final _maxUses = TextEditingController();
  bool _percent = true;
  DateTime? _validUntil;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _code.dispose();
    _value.dispose();
    _maxUses.dispose();
    super.dispose();
  }

  Future<void> _pickEnd() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _validUntil ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    // valid through the end of that day
    if (date != null) setState(() => _validUntil = DateTime(date.year, date.month, date.day, 23, 59));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = _percent ? null : parseKesToCents(_value.text);
    final draft = PromoDraft(
      code: _code.text,
      percentOff: _percent ? int.parse(_value.text.trim()) : null,
      amountOffCents: amount,
      maxUses: int.tryParse(_maxUses.text.trim()),
      validUntil: _validUntil,
    );
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref.read(orgRepositoryProvider).createPromo(widget.orgId, draft);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _message = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('New promo code', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextFormField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Code', hintText: 'WELCOME10'),
                validator: validatePromoCode,
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Percent off')),
                  ButtonSegment(value: false, label: Text('Amount off')),
                ],
                selected: {_percent},
                onSelectionChanged: (s) => setState(() {
                  _percent = s.first;
                  _value.clear();
                }),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _value,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _percent ? 'Percent' : 'Amount',
                  prefixText: _percent ? null : 'KES ',
                  suffixText: _percent ? '%' : null,
                ),
                validator: _percent
                    ? validatePercentOff
                    : (v) {
                        final cents = parseKesToCents(v ?? '');
                        return (cents == null || cents <= 0) ? 'Enter an amount above zero' : null;
                      },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _maxUses,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Total uses (empty for unlimited)'),
                validator: validateMaxUses,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('Valid until'),
                subtitle: Text(_validUntil == null ? 'No end date' : formatDay(_validUntil!)),
                trailing: _validUntil == null
                    ? null
                    : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _validUntil = null)),
                onTap: _pickEnd,
              ),
              Text(
                'Each customer can use a code once. You cover the discount: commission is taken on what the customer pays.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_message != null) ...[
                const SizedBox(height: 8),
                Text(_message!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Create code'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

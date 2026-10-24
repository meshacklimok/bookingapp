import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/async_body.dart';
import '../../org_dashboard/domain/managed_service.dart';
import '../../org_dashboard/domain/earnings.dart';
import '../../org_dashboard/domain/organization.dart';
import '../../org_dashboard/domain/payouts.dart';
import '../../profile/data/profile_repository.dart';
import '../data/admin_repository.dart';
import '../domain/admin.dart';

/// Runs an action, shows the database's friendly error if it fails, and reports whether it worked.
Future<bool> _attempt(BuildContext context, Future<void> Function() action) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyAdminError(e))));
    return false;
  }
}

const _adminErrors = {
  'exceeds_balance': 'That is more than the organization is owed right now.',
  'invalid_amount': 'Enter an amount above zero.',
  'invalid_pct': 'A commission rate is between 0 and 100.',
  'invalid_scope': 'That rate cannot be set there.',
  'payouts_method_check': 'Pick how the money was sent.',
};

String friendlyAdminError(Object e) {
  final raw = e.toString();
  for (final entry in _adminErrors.entries) {
    if (raw.contains(entry.key)) return entry.value;
  }
  return friendlyError(e);
}

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Platform admin')),
      body: AsyncBody(
        value: profile,
        onRetry: () => ref.invalidate(myProfileProvider),
        data: (p) {
          // The database enforces this too; this only keeps other users from seeing empty, failing tabs.
          if (p?.isPlatformAdmin != true) {
            return const EmptyState(icon: Icons.lock_outline, message: 'This area is for platform admins.');
          }
          return const DefaultTabController(
            length: 4,
            child: Column(
              children: [
                TabBar(isScrollable: true, tabs: [
                  Tab(text: 'Organizations'),
                  Tab(text: 'Refunds'),
                  Tab(text: 'Payouts'),
                  Tab(text: 'Commission'),
                ]),
                Expanded(child: TabBarView(children: [_OrgsTab(), _RefundsTab(), _PayoutsTab(), _CommissionTab()])),
              ],
            ),
          );
        },
      ),
    );
  }
}

// Organizations -------------------------------------------------------------------------------------------------------

class _OrgsTab extends ConsumerWidget {
  const _OrgsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncBody<List<AdminOrg>>(
      value: ref.watch(adminOrgsProvider),
      onRetry: () => ref.invalidate(adminOrgsProvider),
      data: (orgs) {
        if (orgs.isEmpty) return const EmptyState(icon: Icons.storefront_outlined, message: 'No organizations yet.');
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(adminOrgsProvider),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final o in orgs)
                Card(
                  child: ListTile(
                    title: Text(o.name),
                    subtitle: Text([o.status.label, if (o.category != null) o.category!, 'registered ${formatDay(o.createdAt.toLocal())}'].join(' · ')),
                    trailing: PopupMenuButton<OrgStatus>(
                      onSelected: (status) async {
                        if (await _attempt(context, () => ref.read(adminRepositoryProvider).setOrgStatus(o.id, status.name))) {
                          ref.invalidate(adminOrgsProvider);
                        }
                      },
                      itemBuilder: (_) => [
                        for (final s in OrgStatus.values)
                          if (s != o.status)
                            PopupMenuItem(value: s, child: Text(switch (s) {
                              OrgStatus.approved => 'Approve',
                              OrgStatus.suspended => 'Suspend',
                              OrgStatus.pending => 'Set back to pending',
                            })),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// Refunds ------------------------------------------------------------------------------------------------------------

class _RefundsTab extends ConsumerWidget {
  const _RefundsTab();

  Future<void> _resolve(BuildContext context, WidgetRef ref, AdminRefund r, {required bool processed}) async {
    final ref0 = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(processed ? 'Mark ${formatKes(r.amountCents)} as sent?' : 'Mark this refund as failed?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(processed
              ? 'Send it to ${r.customerName ?? 'the customer'}${r.phone == null ? '' : ' (${r.phone})'} first, then record it here.'
              : 'The customer is not notified. You can still follow up with them.'),
          if (processed) TextField(controller: ref0, decoration: const InputDecoration(labelText: 'Transaction reference (optional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(processed ? 'Mark as sent' : 'Mark failed')),
        ],
      ),
    );
    final text = ref0.text.trim();
    ref0.dispose();
    if (ok != true || !context.mounted) return;
    if (await _attempt(context, () => ref.read(adminRepositoryProvider).resolveRefund(r.id, processed: processed, providerRef: text))) {
      ref.invalidate(adminRefundsProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncBody<List<AdminRefund>>(
      value: ref.watch(adminRefundsProvider),
      onRetry: () => ref.invalidate(adminRefundsProvider),
      data: (refunds) {
        if (refunds.isEmpty) return const EmptyState(icon: Icons.undo, message: 'No refunds.');
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(adminRefundsProvider),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final r in refunds)
                Card(
                  child: ListTile(
                    title: Text('${formatKes(r.amountCents)} · ${r.customerName ?? 'Customer'}'),
                    subtitle: Text([
                      r.status,
                      if (r.serviceTitle != null) r.serviceTitle!,
                      if (r.provider != null) r.provider!,
                      if (r.phone != null) r.phone!,
                      if (r.reason != null) r.reason!,
                      formatDay(r.createdAt.toLocal()),
                    ].join(' · ')),
                    trailing: r.isPending || r.isProcessing
                        ? PopupMenuButton<String>(
                            onSelected: (action) async {
                              if (action == 'send') {
                                if (await _attempt(context, () => ref.read(adminRepositoryProvider).sendRefund(r.id))) {
                                  ref.invalidate(adminRefundsProvider);
                                }
                              } else {
                                await _resolve(context, ref, r, processed: action == 'sent');
                              }
                            },
                            itemBuilder: (_) => [
                              if (r.canSendAutomatically) const PopupMenuItem(value: 'send', child: Text('Send via Paystack')),
                              const PopupMenuItem(value: 'sent', child: Text('Mark as sent')),
                              const PopupMenuItem(value: 'failed', child: Text('Mark as failed')),
                            ],
                          )
                        : null,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// Payouts ------------------------------------------------------------------------------------------------------------

class _PayoutsTab extends ConsumerWidget {
  const _PayoutsTab();

  Future<void> _record(BuildContext context, WidgetRef ref, AdminBalance b) async {
    final amount = TextEditingController(text: (b.balance.payableCents / 100).toStringAsFixed(b.balance.payableCents % 100 == 0 ? 0 : 2));
    final reference = TextEditingController();
    final note = TextEditingController();
    var method = PayoutMethod.mpesa;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setState) => AlertDialog(
          title: Text('Pay out ${b.orgName}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Owed: ${formatKes(b.balance.payableCents)}'),
              TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount sent (KES)')),
              DropdownButtonFormField<PayoutMethod>(
                initialValue: method,
                decoration: const InputDecoration(labelText: 'Sent by'),
                items: [for (final m in PayoutMethod.values) DropdownMenuItem(value: m, child: Text(m.label))],
                onChanged: (m) => setState(() => method = m ?? method),
              ),
              TextField(controller: reference, decoration: const InputDecoration(labelText: 'Transaction reference')),
              TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (optional)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Back')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Record payout')),
          ],
        ),
      ),
    );
    final cents = parseKesToCents(amount.text);
    final ref1 = reference.text, note1 = note.text;
    for (final c in [amount, reference, note]) {
      c.dispose();
    }
    if (ok != true || !context.mounted) return;
    if (cents == null || cents <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter an amount above zero.')));
      return;
    }
    final done = await _attempt(context, () => ref.read(adminRepositoryProvider).recordPayout(b.orgId, cents, method, reference: ref1, note: note1));
    if (done) ref.invalidate(adminBalancesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncBody<List<AdminBalance>>(
      value: ref.watch(adminBalancesProvider),
      onRetry: () => ref.invalidate(adminBalancesProvider),
      data: (items) {
        if (items.isEmpty) return const EmptyState(icon: Icons.account_balance_wallet_outlined, message: 'No organization has earnings yet.');
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(adminBalancesProvider),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final b in items)
                Card(
                  child: ListTile(
                    title: Text(b.orgName),
                    subtitle: Text('Owed ${formatKes(b.balance.payableCents)} · upcoming ${formatKes(b.balance.upcomingCents)} · paid ${formatKes(b.balance.paidOutCents)}'),
                    trailing: b.balance.payableCents > 0
                        ? TextButton(onPressed: () => _record(context, ref, b), child: const Text('Pay out'))
                        : null,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// Commission ----------------------------------------------------------------------------------------------------------

class _CommissionTab extends ConsumerWidget {
  const _CommissionTab();

  Future<void> _edit(BuildContext context, WidgetRef ref, {required String scope, String? scopeId, required String title, double? current}) async {
    final controller = TextEditingController(text: current == null ? '' : formatPct(current).replaceAll('%', ''));
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Commission (%)'),
          ),
          const SizedBox(height: 8),
          const Text('Applies to new payments only. Past bookings keep the rate they were paid with.'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save')),
        ],
      ),
    );
    final pct = parseCommissionPct(controller.text);
    controller.dispose();
    if (ok != true || !context.mounted) return;
    if (pct == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a rate between 0 and 100, e.g. 10 or 12.5.')));
      return;
    }
    if (await _attempt(context, () => ref.read(adminRepositoryProvider).setCommission(scope, scopeId, pct))) {
      ref.invalidate(adminCommissionsProvider);
    }
  }

  Future<void> _addOrgOverride(BuildContext context, WidgetRef ref) async {
    final List<AdminOrg> orgs = ref.read(adminOrgsProvider).valueOrNull ?? await ref.read(adminOrgsProvider.future);
    if (!context.mounted) return;
    final org = await showDialog<AdminOrg>(
      context: context,
      builder: (d) => SimpleDialog(
        title: const Text('Set a rate for…'),
        children: [for (final o in orgs) SimpleDialogOption(onPressed: () => Navigator.pop(d, o), child: Text(o.name))],
      ),
    );
    if (org == null || !context.mounted) return;
    await _edit(context, ref, scope: 'org', scopeId: org.id, title: 'Commission for ${org.name}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncBody<List<AdminCommission>>(
      value: ref.watch(adminCommissionsProvider),
      onRetry: () => ref.invalidate(adminCommissionsProvider),
      data: (rates) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('The most specific rate wins: a service rate, then the organization rate, then the platform default.'),
          const SizedBox(height: 8),
          for (final c in rates)
            Card(
              child: ListTile(
                title: Text(c.name ?? (c.scope == 'org' ? 'Organization' : 'Service')),
                subtitle: Text(c.isPlatform ? 'Applies to everything without a more specific rate' : c.scope == 'org' ? 'Organization rate' : 'Service rate'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(formatPct(c.pct), style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (!c.isPlatform)
                    IconButton(
                      tooltip: 'Remove override',
                      icon: const Icon(Icons.close),
                      onPressed: () async {
                        if (await _attempt(context, () => ref.read(adminRepositoryProvider).clearCommission(c.scope, c.scopeId!))) {
                          ref.invalidate(adminCommissionsProvider);
                        }
                      },
                    ),
                ]),
                onTap: () => _edit(context, ref,
                    scope: c.scope, scopeId: c.scopeId, title: 'Commission: ${c.name ?? c.scope}', current: c.pct),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _addOrgOverride(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Rate for one organization'),
          ),
        ],
      ),
    );
  }
}

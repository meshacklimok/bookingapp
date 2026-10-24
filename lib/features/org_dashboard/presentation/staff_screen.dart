import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/async_body.dart';
import '../data/org_repository.dart';
import '../domain/staff.dart';

class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staff = ref.watch(orgStaffProvider(orgId));
    final me = ref.watch(currentUserIdProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Staff')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addStaff(context, ref),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add staff'),
      ),
      body: AsyncBody<List<OrgStaff>>(
        value: staff,
        onRetry: () => ref.invalidate(orgStaffProvider(orgId)),
        data: (items) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(orgStaffProvider(orgId)),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            children: [
              for (final s in items)
                Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Text(s.name.characters.first.toUpperCase())),
                    title: Text(s.name),
                    subtitle: Text(s.role),
                    trailing: s.isOwner || s.userId == me
                        ? const Icon(Icons.chevron_right)
                        : PopupMenuButton<String>(
                            onSelected: (action) =>
                                action == 'remove' ? _remove(context, ref, s) : _setRole(context, ref, s, action == 'promote' ? 'admin' : 'staff'),
                            itemBuilder: (_) => [
                              if (s.role == 'staff')
                                const PopupMenuItem(value: 'promote', child: Text('Make admin'))
                              else
                                const PopupMenuItem(value: 'demote', child: Text('Make staff')),
                              const PopupMenuItem(value: 'remove', child: Text('Remove from organization')),
                            ],
                          ),
                    onTap: () => context.push('/org/$orgId/staff/${s.userId}'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addStaff(BuildContext context, WidgetRef ref) async {
    final email = await showDialog<String>(context: context, builder: (_) => const _AddStaffDialog());
    if (email == null || !context.mounted) return;
    try {
      await ref.read(orgRepositoryProvider).addStaff(orgId, email);
      ref.invalidate(orgStaffProvider(orgId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Added. Open them to choose their services and hours.')),
        );
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _setRole(BuildContext context, WidgetRef ref, OrgStaff member, String role) async {
    try {
      await ref.read(orgRepositoryProvider).setMemberRole(orgId, member.userId, role);
      ref.invalidate(orgStaffProvider(orgId));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, OrgStaff member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Remove ${member.name}?'),
        content: const Text('They will no longer be offered to customers and lose access to this organization.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(orgRepositoryProvider).removeStaff(orgId, member.userId);
      ref.invalidate(orgStaffProvider(orgId));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }
}

class _AddStaffDialog extends StatefulWidget {
  const _AddStaffDialog();

  @override
  State<_AddStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends State<_AddStaffDialog> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add staff'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('They need to have signed up to the app already. Enter the email they used.'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: validateEmail,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) Navigator.pop(context, _email.text.trim());
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

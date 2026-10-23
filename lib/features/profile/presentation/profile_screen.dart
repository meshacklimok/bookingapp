import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../org_dashboard/data/org_repository.dart';
import '../data/profile_repository.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseProvider);
    final user = client.auth.currentUser;
    final profile = ref.watch(myProfileProvider).valueOrNull;
    final memberships = ref.watch(membershipsProvider).valueOrNull ?? const <OrgMembership>[];
    final name = profile?.fullName ?? user?.userMetadata?['full_name'] as String?;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(name ?? user?.email ?? 'Guest'),
            subtitle: user?.email == null ? null : Text([user!.email!, if (profile?.phone != null) profile!.phone!].join(' · ')),
          ),
          const Divider(),
          if (user == null)
            ListTile(
              leading: const Icon(Icons.login),
              title: const Text('Sign in'),
              onTap: () => context.push('/login'),
            ),
          if (user != null)
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit profile'),
              onTap: () => context.push('/profile/edit'),
            ),
          for (final m in memberships) ...[
            ListTile(
              leading: const Icon(Icons.storefront),
              title: Text(m.orgName ?? 'Organization'),
              subtitle: Text('Dashboard · ${m.role}'),
              onTap: () => context.push('/org/${m.orgId}'),
            ),
          ],
          if (memberships.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text('Scan tickets'),
              onTap: () => context.push('/scanner'),
            ),
          if (user != null)
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              onTap: () => client.auth.signOut(),
            ),
        ],
      ),
    );
  }
}

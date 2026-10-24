import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/async_body.dart';
import '../../discover/domain/service.dart';
import '../data/org_repository.dart';
import '../domain/managed_service.dart';

class ServicesScreen extends ConsumerWidget {
  const ServicesScreen({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(orgServicesProvider(orgId));
    return Scaffold(
      appBar: AppBar(title: const Text('Services')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/org/$orgId/services/new'),
        icon: const Icon(Icons.add),
        label: const Text('Add service'),
      ),
      body: AsyncBody<List<ManagedService>>(
        value: services,
        onRetry: () => ref.invalidate(orgServicesProvider(orgId)),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyState(icon: Icons.design_services_outlined, message: 'No services yet. Add your first one.');
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(orgServicesProvider(orgId)),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
              children: [for (final s in items) _ServiceTile(service: s, orgId: orgId)],
            ),
          );
        },
      ),
    );
  }
}

class _ServiceTile extends ConsumerWidget {
  const _ServiceTile({required this.service, required this.orgId});

  final ManagedService service;
  final String orgId;

  Future<void> _toggle(BuildContext context, WidgetRef ref, bool active) async {
    try {
      await ref.read(orgRepositoryProvider).setServiceActive(service.id, active);
      ref.invalidate(orgServicesProvider(orgId));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEvent = service.mode == BookingMode.event;
    final when = isEvent && service.eventStartsAt != null ? formatDateTime(service.eventStartsAt!) : '${service.durationMin} min';
    final price = isEvent ? 'from ${formatKes(service.priceCents)}' : formatKes(service.priceCents);
    return Card(
      child: ListTile(
        leading: Icon(isEvent ? Icons.confirmation_number_outlined : Icons.event_available_outlined),
        title: Text(service.title, style: service.isActive ? null : const TextStyle(decoration: TextDecoration.lineThrough)),
        subtitle: Text([isEvent ? 'Event' : 'Appointment', when, price, if (!service.isActive) 'inactive'].join(' · ')),
        trailing: Switch(
          value: service.isActive,
          onChanged: (v) => _toggle(context, ref, v),
        ),
        onTap: () => context.push('/org/$orgId/services/${service.id}'),
      ),
    );
  }
}

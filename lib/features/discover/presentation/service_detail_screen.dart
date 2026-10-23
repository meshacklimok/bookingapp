import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/async_body.dart';
import '../data/service_repository.dart';
import '../domain/service.dart';

class ServiceDetailScreen extends ConsumerWidget {
  const ServiceDetailScreen({super.key, required this.serviceId});

  final String serviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(serviceProvider(serviceId));
    final loggedIn = ref.watch(currentUserIdProvider) != null;

    return Scaffold(
      appBar: AppBar(),
      body: AsyncBody<Service>(
        value: service,
        onRetry: () => ref.invalidate(serviceProvider(serviceId)),
        data: (s) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(s.title, style: Theme.of(context).textTheme.headlineSmall),
            if (s.orgName != null) ...[
              const SizedBox(height: 4),
              Text('by ${s.orgName}', style: Theme.of(context).textTheme.bodyMedium),
            ],
            const SizedBox(height: 16),
            if (s.mode == BookingMode.event && s.eventStartsAt != null)
              _InfoRow(icon: Icons.event, text: formatDateTime(s.eventStartsAt!)),
            if (s.mode == BookingMode.appointment) _InfoRow(icon: Icons.schedule, text: '${s.durationMin} minutes'),
            if (s.location != null) _InfoRow(icon: Icons.place_outlined, text: s.location!),
            _InfoRow(
              icon: Icons.payments_outlined,
              text: s.mode == BookingMode.event ? 'From ${formatKes(s.priceCents)}' : formatKes(s.priceCents),
            ),
            if (s.description != null && s.description!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(s.description!),
            ],
            const SizedBox(height: 24),
            if (s.mode == BookingMode.resource)
              const Text('Online booking for this service is coming soon.')
            else
              FilledButton(
                onPressed: () => loggedIn ? context.push('/book/${s.id}') : context.push('/login'),
                child: Text(loggedIn ? (s.mode == BookingMode.event ? 'Get tickets' : 'Book now') : 'Sign in to book'),
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

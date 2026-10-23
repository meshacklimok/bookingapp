import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/async_body.dart';
import '../data/service_repository.dart';
import '../domain/service.dart';

const _categories = ['Beauty', 'Health', 'Education', 'Events', 'Sports', 'Other'];

class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(serviceListProvider);
    final selected = ref.watch(categoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Discover')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search services and events'),
              textInputAction: TextInputAction.search,
              onSubmitted: (v) => ref.read(searchQueryProvider.notifier).state = v,
            ),
          ),
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              children: [
                for (final c in _categories)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilterChip(
                      label: Text(c),
                      selected: selected == c,
                      onSelected: (on) => ref.read(categoryProvider.notifier).state = on ? c : null,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncBody<List<Service>>(
              value: services,
              onRetry: () => ref.invalidate(serviceListProvider),
              data: (items) {
                if (items.isEmpty) {
                  return const EmptyState(icon: Icons.search_off, message: 'No services found.');
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(serviceListProvider),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: items.length,
                    itemBuilder: (context, i) => _ServiceCard(service: items[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service});

  final Service service;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (service.orgName != null) service.orgName!,
      if (service.mode == BookingMode.event && service.eventStartsAt != null) formatDateTime(service.eventStartsAt!),
      if (service.mode == BookingMode.appointment) '${service.durationMin} min',
    ].join(' · ');

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(service.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: Text(
          service.mode == BookingMode.event ? 'from ${formatKes(service.priceCents)}' : formatKes(service.priceCents),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        onTap: () => context.push('/service/${service.id}'),
      ),
    );
  }
}

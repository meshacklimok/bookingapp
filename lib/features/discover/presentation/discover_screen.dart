import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/async_body.dart';
import '../data/service_repository.dart';
import '../domain/service.dart';
import '../domain/service_filters.dart';

const _categories = ['Beauty', 'Health', 'Education', 'Events', 'Sports', 'Other'];

class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(serviceListProvider);
    final filters = ref.watch(serviceFiltersProvider);
    final selected = filters.category;
    void update(ServiceFilters f) => ref.read(serviceFiltersProvider.notifier).state = f;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        actions: [
          IconButton(
            tooltip: 'Filters',
            icon: Badge(
              isLabelVisible: filters.activeCount > 0,
              label: Text('${filters.activeCount}'),
              child: const Icon(Icons.tune),
            ),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => const _FilterSheet(),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search services and events',
                suffixIcon: filters.query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close),
                        onPressed: () => update(filters.copyWith(query: '')),
                      ),
              ),
              // the key makes the field pick up a cleared query
              key: ValueKey(filters.query.isEmpty),
              textInputAction: TextInputAction.search,
              onSubmitted: (v) => update(filters.copyWith(query: v.trim())),
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
                      onSelected: (on) => update(filters.copyWith(category: on ? c : null)),
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
                    // a full page means there may be more
                    itemCount: items.length + (items.length >= ref.watch(resultLimitProvider) ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i < items.length) return _ServiceCard(service: items[i]);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: OutlinedButton(
                          onPressed: services.isLoading
                              ? null
                              : () => ref.read(resultLimitProvider.notifier).state += ServiceRepository.pageSize,
                          child: Text(services.isLoading ? 'Loading...' : 'Load more'),
                        ),
                      );
                    },
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

const _priceCaps = [50000, 100000, 250000, 500000, 1000000];

class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(serviceFiltersProvider);
    void update(ServiceFilters f) => ref.read(serviceFiltersProvider.notifier).state = f;
    final heading = Theme.of(context).textTheme.titleSmall;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type', style: heading),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: filters.mode == null,
                  onSelected: (_) => update(filters.copyWith(mode: null)),
                ),
                ChoiceChip(
                  label: const Text('Appointments'),
                  selected: filters.mode == BookingMode.appointment,
                  onSelected: (_) => update(filters.copyWith(mode: BookingMode.appointment)),
                ),
                ChoiceChip(
                  label: const Text('Events'),
                  selected: filters.mode == BookingMode.event,
                  onSelected: (_) => update(filters.copyWith(mode: BookingMode.event)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Maximum price', style: heading),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Any'),
                  selected: filters.maxPriceCents == null,
                  onSelected: (_) => update(filters.copyWith(maxPriceCents: null)),
                ),
                for (final cap in _priceCaps)
                  ChoiceChip(
                    label: Text(formatKes(cap)),
                    selected: filters.maxPriceCents == cap,
                    onSelected: (_) => update(filters.copyWith(maxPriceCents: cap)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Sort by', style: heading),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final sort in ServiceSort.values)
                  ChoiceChip(
                    label: Text(sort.label),
                    selected: filters.sort == sort,
                    onSelected: (_) => update(filters.copyWith(sort: sort)),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                TextButton(
                  onPressed: filters.activeCount == 0
                      ? null
                      : () => update(filters.copyWith(mode: null, maxPriceCents: null, sort: ServiceSort.newest)),
                  child: const Text('Reset'),
                ),
                const Spacer(),
                FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

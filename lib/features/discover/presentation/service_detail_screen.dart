import '../../booking/domain/cancellation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/async_body.dart';
import '../../../shared/widgets/star_rating.dart';
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
            if (s.mode != BookingMode.event) _InfoRow(icon: Icons.schedule, text: '${s.durationMin} minutes'),
            if (s.ratingCount > 0)
              _InfoRow(icon: Icons.star_rounded, text: '${s.ratingAvg!.toStringAsFixed(1)} (${s.ratingCount} ${s.ratingCount == 1 ? 'review' : 'reviews'})'),
            if (s.location != null) _InfoRow(icon: Icons.place_outlined, text: s.location!),
            _InfoRow(
              icon: Icons.payments_outlined,
              text: s.mode == BookingMode.event ? 'From ${formatKes(s.priceCents)}' : formatKes(s.priceCents),
            ),
            _InfoRow(icon: Icons.event_busy_outlined, text: cancellationPolicyText(s.freeCancelHours, s.lateRefundPct)),
            if (s.description != null && s.description!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(s.description!),
            ],
            if (s.mode == BookingMode.appointment) _StaffSection(serviceId: s.id),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => loggedIn ? context.push('/book/${s.id}') : context.push('/login'),
              child: Text(loggedIn ? (s.mode == BookingMode.event ? 'Get tickets' : 'Book now') : 'Sign in to book'),
            ),
            if (s.ratingCount > 0) _ReviewsSection(serviceId: s.id),
          ],
        ),
      ),
    );
  }
}

class _ReviewsSection extends ConsumerWidget {
  const _ReviewsSection({required this.serviceId});

  final String serviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Like the team list, reviews are a nice-to-have: loading and errors render nothing.
    final reviews = ref.watch(reviewsProvider(serviceId)).valueOrNull ?? const [];
    if (reviews.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reviews', style: Theme.of(context).textTheme.titleMedium),
          for (final r in reviews)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      StarRating(rating: r.rating),
                      const SizedBox(width: 8),
                      Text(r.reviewer, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text(formatRelative(r.createdAt, DateTime.now()), style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                  if (r.comment != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(r.comment!)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StaffSection extends ConsumerWidget {
  const _StaffSection({required this.serviceId});

  final String serviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The team list is a nice-to-have, so loading and errors render nothing.
    final staff = ref.watch(staffProvider(serviceId)).valueOrNull ?? const [];
    if (staff.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your specialist', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final m in staff)
                Chip(
                  avatar: CircleAvatar(
                    backgroundImage: m.avatarUrl == null ? null : NetworkImage(m.avatarUrl!),
                    child: m.avatarUrl == null ? Text(m.name[0].toUpperCase()) : null,
                  ),
                  label: Text(m.name),
                ),
            ],
          ),
        ],
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

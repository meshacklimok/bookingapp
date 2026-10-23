import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/async_body.dart';
import '../data/ticket_repository.dart';

class TicketDetailScreen extends ConsumerWidget {
  const TicketDetailScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(ticketProvider(ticketId));

    return Scaffold(
      appBar: AppBar(title: const Text('Ticket')),
      body: AsyncBody<TicketInfo>(
        value: ticket,
        onRetry: () => ref.invalidate(ticketProvider(ticketId)),
        data: (t) {
          final valid = t.status == 'valid';
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(t.serviceTitle ?? 'Ticket', style: Theme.of(context).textTheme.headlineSmall),
                  if (t.startsAt != null) Text(formatDateTime(t.startsAt!)),
                  const SizedBox(height: 24),
                  // The QR background stays white so scanners can read it in dark mode too.
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(16),
                    child: Opacity(
                      opacity: valid ? 1 : 0.2,
                      child: QrImageView(data: t.qrToken, size: 240),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(valid ? 'Show this code at the entrance' : 'This ticket is ${t.status}'),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/errors.dart';
import '../../../core/utils/formatters.dart';
import '../data/booking_repository.dart';
import '../domain/cancellation.dart';

/// Shows what the cancellation would refund, asks for confirmation and cancels. Used by customers and, for the
/// organization's side, with the same database function. Returns true when the booking was cancelled.
Future<bool> confirmCancelBooking(BuildContext context, WidgetRef ref, {required String bookingId, required String title}) async {
  final repo = ref.read(bookingRepositoryProvider);
  final messenger = ScaffoldMessenger.of(context);
  final CancellationQuote quote;
  try {
    quote = await repo.cancellationQuote(bookingId);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    return false;
  }
  if (!context.mounted) return false;

  final reason = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text('Cancel $title?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_refundSentence(quote)),
          const SizedBox(height: 12),
          TextField(
            controller: reason,
            decoration: const InputDecoration(labelText: 'Reason (optional)'),
            maxLength: 200,
            textCapitalization: TextCapitalization.sentences,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Keep booking')),
        FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Cancel booking')),
      ],
    ),
  );
  final text = reason.text;
  reason.dispose();
  if (confirmed != true) return false;

  try {
    await repo.cancel(bookingId, reason: text.trim().isEmpty ? null : text.trim());
    ref.invalidate(myBookingsProvider);
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    return false;
  }
}

String _refundSentence(CancellationQuote q) {
  if (q.byOrg) return 'The customer will be refunded ${formatKes(q.refundCents)} in full.';
  if (q.refundCents == 0) return 'This is inside the free cancellation window, so you will not be refunded.';
  if (q.fullRefund) return 'You will be refunded ${formatKes(q.refundCents)} in full.';
  return 'This is after the free cancellation window. You will be refunded ${formatKes(q.refundCents)}.';
}

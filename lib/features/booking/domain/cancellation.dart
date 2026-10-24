/// Cancellation windows offered in the service form, in hours before the start.
const cancelWindowOptions = [0, 2, 6, 12, 24, 48, 72, 168];

/// Refund percentages offered for cancellations after the free window.
const lateRefundOptions = [0, 25, 50, 75];

/// "24 hours", "3 days"
String cancellationWindowLabel(int h) => switch (h) {
      168 => '7 days',
      48 || 72 => '${h ~/ 24} days',
      24 => '24 hours',
      1 => '1 hour',
      _ => '$h hours',
    };

/// One sentence for customers, e.g. "Free cancellation until 24 hours before. After that, 50% is refunded."
String cancellationPolicyText(int freeHours, int latePct) {
  final free = freeHours == 0 ? 'Free cancellation until it starts.' : 'Free cancellation until ${cancellationWindowLabel(freeHours)} before.';
  if (freeHours == 0) return free;
  final late = latePct == 0 ? 'After that, no refund.' : 'After that, $latePct% is refunded.';
  return '$free $late';
}

/// What a cancel would return, as quoted by `cancellation_quote`.
class CancellationQuote {
  const CancellationQuote({required this.refundCents, required this.fullRefund, required this.byOrg});

  final int refundCents;
  final bool fullRefund;
  final bool byOrg;

  factory CancellationQuote.fromMap(Map<String, dynamic> m) => CancellationQuote(
        refundCents: (m['refund_cents'] as num).toInt(),
        fullRefund: m['full_refund'] as bool,
        byOrg: m['by_org'] as bool,
      );
}

/// Where a booking's refund stands, from its `refunds` rows. Null when nothing was refunded.
enum RefundState {
  pending('Refund pending'),
  processed('Refunded'),
  failed('Refund failed - contact support');

  const RefundState(this.label);

  final String label;

  static RefundState? fromStatuses(Iterable<String> statuses) {
    final all = statuses.toList();
    if (all.isEmpty) return null;
    if (all.contains('failed')) return RefundState.failed;
    if (all.contains('pending') || all.contains('processing')) return RefundState.pending;
    return RefundState.processed;
  }
}

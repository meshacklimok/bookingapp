import '../../../core/utils/formatters.dart';

/// Reporting windows on the earnings screen. Dates follow the database: Africa/Nairobi, which has no daylight saving.
enum EarningsPeriod {
  thisMonth('This month'),
  lastMonth('Last month'),
  allTime('All time');

  const EarningsPeriod(this.label);

  final String label;

  /// Inclusive start and end dates as `yyyy-MM-dd`; null leaves that side open.
  (String?, String?) range(DateTime now) {
    final nairobi = now.toUtc().add(const Duration(hours: 3));
    final first = DateTime.utc(nairobi.year, nairobi.month);
    return switch (this) {
      EarningsPeriod.allTime => (null, null),
      EarningsPeriod.thisMonth => (formatIsoDate(first), formatIsoDate(DateTime.utc(first.year, first.month + 1, 0))),
      EarningsPeriod.lastMonth => (
          formatIsoDate(DateTime.utc(first.year, first.month - 1)),
          formatIsoDate(DateTime.utc(first.year, first.month, 0)),
        ),
    };
  }
}

/// Money in cents. [netCents] is what the organization keeps: gross minus commission.
class EarningsSummary {
  const EarningsSummary({
    required this.count,
    required this.grossCents,
    required this.commissionCents,
    required this.netCents,
    this.refundedCents = 0,
  });

  final int count;
  final int grossCents;
  final int commissionCents;
  final int netCents;

  /// Money handed back to customers; already left out of the gross above.
  final int refundedCents;

  factory EarningsSummary.fromMap(Map<String, dynamic> m) => EarningsSummary(
        count: (m['booking_count'] as num).toInt(),
        grossCents: (m['gross_cents'] as num).toInt(),
        commissionCents: (m['commission_cents'] as num).toInt(),
        netCents: (m['net_cents'] as num).toInt(),
        refundedCents: (m['refunded_cents'] as num?)?.toInt() ?? 0,
      );
}

class EarningsRow {
  const EarningsRow({
    required this.bookingId,
    required this.startsAt,
    required this.status,
    required this.grossCents,
    required this.commissionCents,
    required this.netCents,
    this.refundCents = 0,
    this.serviceTitle,
    this.customerName,
    this.commissionPct,
  });

  final String bookingId;
  final DateTime startsAt;
  final String status;
  final String? serviceTitle;
  final String? customerName;
  final int grossCents;
  final double? commissionPct;
  final int commissionCents;
  final int netCents;
  final int refundCents;

  factory EarningsRow.fromMap(Map<String, dynamic> m) => EarningsRow(
        bookingId: m['booking_id'] as String,
        startsAt: DateTime.parse(m['starts_at'] as String),
        status: m['status'] as String,
        serviceTitle: m['service_title'] as String?,
        customerName: m['customer_name'] as String?,
        grossCents: (m['gross_cents'] as num).toInt(),
        commissionPct: (m['commission_pct'] as num?)?.toDouble(),
        commissionCents: (m['commission_cents'] as num).toInt(),
        netCents: (m['net_cents'] as num).toInt(),
        refundCents: (m['refund_cents'] as num?)?.toInt() ?? 0,
      );
}

/// "10%" or "12.5%".
String formatPct(double pct) => '${pct == pct.roundToDouble() ? pct.round() : pct}%';

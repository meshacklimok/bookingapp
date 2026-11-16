enum BookingMode {
  appointment,
  event,
  resource;

  static BookingMode parse(String value) =>
      BookingMode.values.firstWhere((m) => m.name == value, orElse: () => BookingMode.appointment);
}

class Service {
  const Service({
    required this.id,
    required this.orgId,
    required this.orgName,
    required this.title,
    required this.description,
    required this.category,
    required this.mode,
    required this.priceCents,
    required this.durationMin,
    required this.location,
    required this.eventStartsAt,
    this.freeCancelHours = 24,
    this.lateRefundPct = 0,
    this.depositPct,
    this.ratingAvg,
    this.ratingCount = 0,
  });

  final String id;
  final String orgId;
  final String? orgName;
  final String title;
  final String? description;
  final String? category;
  final BookingMode mode;
  final int priceCents;
  final int durationMin;
  final String? location;
  final DateTime? eventStartsAt;
  final int freeCancelHours;
  final int lateRefundPct;

  /// Percent of the price the customer can pay online to book; the rest is paid at the venue. Null: pay in full.
  final int? depositPct;
  final double? ratingAvg;
  final int ratingCount;

  factory Service.fromMap(Map<String, dynamic> m) => Service(
        id: m['id'] as String,
        orgId: m['org_id'] as String,
        orgName: (m['organizations'] as Map<String, dynamic>?)?['name'] as String?,
        title: m['title'] as String,
        description: m['description'] as String?,
        category: m['category'] as String?,
        mode: BookingMode.parse(m['booking_mode'] as String),
        priceCents: m['price_cents'] as int,
        durationMin: m['duration_min'] as int,
        location: m['location'] as String?,
        eventStartsAt: m['event_starts_at'] == null ? null : DateTime.parse(m['event_starts_at'] as String),
        freeCancelHours: (m['free_cancel_hours'] as num?)?.toInt() ?? 24,
        lateRefundPct: (m['late_refund_pct'] as num?)?.toInt() ?? 0,
        depositPct: (m['deposit_pct'] as num?)?.toInt(),
        ratingAvg: (m['rating_avg'] as num?)?.toDouble(),
        ratingCount: (m['rating_count'] as num?)?.toInt() ?? 0,
      );
}

/// What other customers said: a star rating, an optional comment and the reviewer's first name.
class Review {
  const Review({required this.rating, required this.comment, required this.createdAt, required this.reviewer});

  final int rating;
  final String? comment;
  final DateTime createdAt;
  final String reviewer;

  factory Review.fromMap(Map<String, dynamic> m) => Review(
        rating: (m['rating'] as num).toInt(),
        comment: m['comment'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
        reviewer: m['reviewer'] as String? ?? 'Customer',
      );
}

class TicketTier {
  const TicketTier({
    required this.id,
    required this.name,
    required this.priceCents,
    required this.quantity,
    required this.sold,
  });

  final String id;
  final String name;
  final int priceCents;
  final int quantity;
  final int sold;

  int get remaining => quantity - sold;

  factory TicketTier.fromMap(Map<String, dynamic> m) => TicketTier(
        id: m['id'] as String,
        name: m['name'] as String,
        priceCents: m['price_cents'] as int,
        quantity: m['quantity'] as int,
        sold: m['sold'] as int,
      );
}

class StaffMember {
  const StaffMember({required this.id, required this.name, required this.avatarUrl});

  final String id;
  final String name;
  final String? avatarUrl;

  factory StaffMember.fromMap(Map<String, dynamic> m) => StaffMember(
        id: m['staff_id'] as String,
        name: (m['full_name'] as String?)?.trim().isNotEmpty == true ? m['full_name'] as String : 'Staff member',
        avatarUrl: m['avatar_url'] as String?,
      );
}

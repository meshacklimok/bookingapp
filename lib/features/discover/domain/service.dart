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

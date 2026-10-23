class Slot {
  const Slot({required this.staffId, required this.start, required this.end});

  final String staffId;
  final DateTime start;
  final DateTime end;

  factory Slot.fromMap(Map<String, dynamic> m) => Slot(
        staffId: m['staff_id'] as String,
        start: DateTime.parse(m['slot_start'] as String),
        end: DateTime.parse(m['slot_end'] as String),
      );
}

class Booking {
  const Booking({
    required this.id,
    required this.serviceId,
    required this.serviceTitle,
    required this.startsAt,
    required this.quantity,
    required this.status,
    required this.totalCents,
    required this.expiresAt,
  });

  final String id;
  final String serviceId;
  final String? serviceTitle;
  final DateTime startsAt;
  final int quantity;
  final String status;
  final int totalCents;
  final DateTime? expiresAt;

  bool get isUnpaid => status == 'held' || status == 'pending_payment';

  factory Booking.fromMap(Map<String, dynamic> m) => Booking(
        id: m['id'] as String,
        serviceId: m['service_id'] as String,
        serviceTitle: (m['services'] as Map<String, dynamic>?)?['title'] as String?,
        startsAt: DateTime.parse(m['starts_at'] as String),
        quantity: m['quantity'] as int,
        status: m['status'] as String,
        totalCents: (m['total_cents'] as num).toInt(),
        expiresAt: m['expires_at'] == null ? null : DateTime.parse(m['expires_at'] as String),
      );
}

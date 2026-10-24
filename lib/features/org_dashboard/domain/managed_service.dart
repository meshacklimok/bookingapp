import '../../discover/domain/service.dart';

/// A service as its own organization sees it: every column, including inactive ones.
class ManagedService {
  const ManagedService({
    required this.id,
    required this.orgId,
    required this.title,
    required this.mode,
    required this.priceCents,
    required this.durationMin,
    required this.bufferMin,
    required this.isActive,
    this.freeCancelHours = 24,
    this.lateRefundPct = 0,
    this.description,
    this.category,
    this.location,
    this.eventStartsAt,
    this.eventEndsAt,
  });

  final String id;
  final String orgId;
  final String title;
  final String? description;
  final String? category;
  final BookingMode mode;
  final int priceCents;
  final int durationMin;
  final int bufferMin;
  final String? location;
  final DateTime? eventStartsAt;
  final DateTime? eventEndsAt;
  final bool isActive;
  final int freeCancelHours;
  final int lateRefundPct;

  factory ManagedService.fromMap(Map<String, dynamic> m) => ManagedService(
        id: m['id'] as String,
        orgId: m['org_id'] as String,
        title: m['title'] as String,
        description: m['description'] as String?,
        category: m['category'] as String?,
        mode: BookingMode.parse(m['booking_mode'] as String),
        priceCents: (m['price_cents'] as num).toInt(),
        durationMin: (m['duration_min'] as num).toInt(),
        bufferMin: (m['buffer_min'] as num).toInt(),
        location: m['location'] as String?,
        eventStartsAt: m['event_starts_at'] == null ? null : DateTime.parse(m['event_starts_at'] as String),
        eventEndsAt: m['event_ends_at'] == null ? null : DateTime.parse(m['event_ends_at'] as String),
        isActive: m['is_active'] as bool,
        freeCancelHours: (m['free_cancel_hours'] as num?)?.toInt() ?? 24,
        lateRefundPct: (m['late_refund_pct'] as num?)?.toInt() ?? 0,
      );
}

/// What the service form collects. Only the fields that apply to [mode] are written.
class ServiceDraft {
  const ServiceDraft({
    required this.title,
    required this.mode,
    this.description,
    this.category,
    this.location,
    this.priceCents = 0,
    this.durationMin = 60,
    this.bufferMin = 0,
    this.eventStartsAt,
    this.eventEndsAt,
    this.isActive = true,
    this.freeCancelHours = 24,
    this.lateRefundPct = 0,
  });

  final String title;
  final BookingMode mode;
  final String? description;
  final String? category;
  final String? location;
  final int priceCents;
  final int durationMin;
  final int bufferMin;
  final DateTime? eventStartsAt;
  final DateTime? eventEndsAt;
  final bool isActive;
  final int freeCancelHours;
  final int lateRefundPct;

  Map<String, dynamic> toMap(String orgId) => {
        'org_id': orgId,
        'title': title.trim(),
        'description': _blankToNull(description),
        'category': category,
        'location': _blankToNull(location),
        'booking_mode': mode.name,
        'is_active': isActive,
        'free_cancel_hours': freeCancelHours,
        'late_refund_pct': lateRefundPct,
        if (mode == BookingMode.appointment) ...{
          'price_cents': priceCents,
          'duration_min': durationMin,
          'buffer_min': bufferMin,
          'event_starts_at': null,
          'event_ends_at': null,
        },
        // An event's price is its cheapest ticket tier; the database keeps it in sync.
        if (mode == BookingMode.event) ...{
          'event_starts_at': eventStartsAt?.toUtc().toIso8601String(),
          'event_ends_at': eventEndsAt?.toUtc().toIso8601String(),
        },
      };
}

String? _blankToNull(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();

/// A ticket tier being edited. [id] is null until it has been saved.
class TierDraft {
  const TierDraft({this.id, required this.name, required this.priceCents, required this.quantity});

  final String? id;
  final String name;
  final int priceCents;
  final int quantity;

  Map<String, dynamic> toMap(String serviceId) =>
      {'service_id': serviceId, 'name': name.trim(), 'price_cents': priceCents, 'quantity': quantity};
}

/// "1500", "1,500", "KES 1,500.50" -> cents. Null when it is not a non-negative amount with at most 2 decimals.
int? parseKesToCents(String input) {
  final cleaned = input.trim().replaceFirst(RegExp(r'^(kes|ksh|ksh\.)\s*', caseSensitive: false), '').replaceAll(',', '');
  final m = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(cleaned);
  if (m == null) return null;
  final whole = int.parse(m.group(1)!);
  final fraction = int.parse((m.group(2) ?? '').padRight(2, '0').padLeft(2, '0'));
  return whole * 100 + fraction;
}

String? validateServiceTitle(String? v) {
  final value = v?.trim() ?? '';
  if (value.length < 2) return 'Enter a title';
  if (value.length > 80) return 'Keep the title under 80 characters';
  return null;
}

String? validatePrice(String? v) => parseKesToCents(v ?? '') == null ? 'Enter an amount, e.g. 1500' : null;

String? validatePositiveInt(String? v, {String label = 'a whole number', int max = 1440}) {
  final n = int.tryParse((v ?? '').trim());
  if (n == null || n < 1) return 'Enter $label above 0';
  return n > max ? 'Enter $label up to $max' : null;
}

String? validateNonNegativeInt(String? v, {int max = 1440}) {
  final n = int.tryParse((v ?? '').trim());
  if (n == null || n < 0) return 'Enter 0 or more minutes';
  return n > max ? 'Enter up to $max minutes' : null;
}

/// An event needs a start; when given, the end must follow it. [now] is injectable for tests.
String? validateEventWindow(DateTime? starts, DateTime? ends, {DateTime? now, bool requireFuture = true}) {
  if (starts == null) return 'Choose when the event starts';
  if (requireFuture && !starts.isAfter(now ?? DateTime.now())) return 'The event must start in the future';
  if (ends != null && !ends.isAfter(starts)) return 'The event must end after it starts';
  return null;
}

/// Checks a tier list against what is already sold. [sold] maps saved tier id -> tickets sold.
/// Returns a message for the first problem, or null.
String? validateTiers(List<TierDraft> tiers, {Map<String, int> sold = const {}}) {
  if (tiers.isEmpty) return 'Add at least one ticket type';
  final names = <String>{};
  for (final t in tiers) {
    final name = t.name.trim();
    if (name.isEmpty) return 'Give every ticket type a name';
    if (!names.add(name.toLowerCase())) return 'Two ticket types are called "$name"';
    if (t.quantity < 1) return '"$name" needs a quantity of at least 1';
    final already = t.id == null ? 0 : (sold[t.id] ?? 0);
    if (t.quantity < already) return '"$name" has $already tickets sold; the quantity cannot go below that';
  }
  return null;
}

/// What to write so the saved tiers match the edited list.
class TierChanges {
  const TierChanges({required this.inserts, required this.updates, required this.deletes});

  final List<TierDraft> inserts;
  final List<TierDraft> updates;
  final List<String> deletes;

  bool get isEmpty => inserts.isEmpty && updates.isEmpty && deletes.isEmpty;
}

TierChanges diffTiers(List<TicketTier> saved, List<TierDraft> edited) {
  final byId = {for (final t in saved) t.id: t};
  final keptIds = {for (final t in edited) if (t.id != null) t.id!};
  return TierChanges(
    inserts: [for (final t in edited) if (t.id == null || !byId.containsKey(t.id)) t],
    updates: [
      for (final t in edited)
        if (t.id != null && byId.containsKey(t.id) && _changed(byId[t.id]!, t)) t,
    ],
    deletes: [for (final t in saved) if (!keptIds.contains(t.id)) t.id],
  );
}

bool _changed(TicketTier saved, TierDraft draft) =>
    saved.name != draft.name.trim() || saved.priceCents != draft.priceCents || saved.quantity != draft.quantity;

/// Tiers that were removed but already sold tickets cannot be deleted: bookings reference them.
List<String> undeletableTiers(List<TicketTier> saved, List<TierDraft> edited) {
  final keptIds = {for (final t in edited) if (t.id != null) t.id!};
  return [for (final t in saved) if (!keptIds.contains(t.id) && t.sold > 0) t.name];
}

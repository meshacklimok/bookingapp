import '../../../core/utils/formatters.dart';

/// A promo code as the organization sees it, with how many bookings have used it.
class PromoCode {
  const PromoCode({
    required this.id,
    required this.code,
    required this.percentOff,
    required this.amountOffCents,
    required this.maxUses,
    required this.validUntil,
    required this.isActive,
    required this.uses,
  });

  final String id;
  final String code;
  final int? percentOff;
  final int? amountOffCents;
  final int? maxUses;
  final DateTime? validUntil;
  final bool isActive;
  final int uses;

  String get discountLabel => percentOff != null ? '$percentOff% off' : '${formatKes(amountOffCents ?? 0)} off';

  bool isExpired(DateTime now) => validUntil != null && now.isAfter(validUntil!);
  bool get isUsedUp => maxUses != null && uses >= maxUses!;

  factory PromoCode.fromMap(Map<String, dynamic> m) => PromoCode(
        id: m['id'] as String,
        code: m['code'] as String,
        percentOff: (m['percent_off'] as num?)?.toInt(),
        amountOffCents: (m['amount_off_cents'] as num?)?.toInt(),
        maxUses: (m['max_uses'] as num?)?.toInt(),
        validUntil: m['valid_until'] == null ? null : DateTime.parse(m['valid_until'] as String),
        isActive: m['is_active'] as bool,
        uses: (m['uses'] as num?)?.toInt() ?? 0,
      );
}

/// What the new-code form collects. Exactly one of [percentOff] and [amountOffCents] is set.
class PromoDraft {
  const PromoDraft({required this.code, this.percentOff, this.amountOffCents, this.maxUses, this.validUntil});

  final String code;
  final int? percentOff;
  final int? amountOffCents;
  final int? maxUses;
  final DateTime? validUntil;

  Map<String, dynamic> toMap(String orgId) => {
        'org_id': orgId,
        'code': code.trim().toUpperCase(),
        'percent_off': percentOff,
        'amount_off_cents': amountOffCents,
        'max_uses': maxUses,
        'valid_until': validUntil?.toUtc().toIso8601String(),
      };
}

final _codePattern = RegExp(r'^[A-Za-z0-9_-]{3,24}$');

/// Letters, digits, "-" and "_", 3 to 24 characters, since customers type it in.
String? validatePromoCode(String? value) {
  final v = (value ?? '').trim();
  if (v.isEmpty) return 'Enter a code';
  if (!_codePattern.hasMatch(v)) return '3 to 24 letters, numbers, - or _';
  return null;
}

String? validatePercentOff(String? value) {
  final n = int.tryParse((value ?? '').trim());
  if (n == null || n < 1 || n > 100) return 'Enter a percentage from 1 to 100';
  return null;
}

/// Empty means unlimited.
String? validateMaxUses(String? value) {
  final v = (value ?? '').trim();
  if (v.isEmpty) return null;
  final n = int.tryParse(v);
  if (n == null || n < 1) return 'Enter a whole number, or leave empty';
  return null;
}

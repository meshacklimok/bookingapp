/// Returns the number as 2547XXXXXXXX / 2541XXXXXXXX, or null if it is not a Kenyan mobile number.
/// Mirrors `normalizeKenyanPhone` in supabase/functions/_shared/mpesa.ts.
String? normalizeKenyanPhone(String input) {
  final digits = input.replaceAll(RegExp(r'[\s+-]'), '');
  if (RegExp(r'^0[17]\d{8}$').hasMatch(digits)) return '254${digits.substring(1)}';
  if (RegExp(r'^254[17]\d{8}$').hasMatch(digits)) return digits;
  return null;
}

String? validateEmail(String? v) {
  final value = v?.trim() ?? '';
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value) ? null : 'Enter a valid email';
}

String? validatePassword(String? v) => (v == null || v.length < 6) ? 'At least 6 characters' : null;

String? validateRequiredName(String? v) => (v == null || v.trim().isEmpty) ? 'Enter your name' : null;

/// Phone is optional on the profile; when given it must be a Kenyan mobile number.
String? validateOptionalPhone(String? v) {
  if (v == null || v.trim().isEmpty) return null;
  return normalizeKenyanPhone(v) == null ? 'Enter a valid number, e.g. 0712345678' : null;
}

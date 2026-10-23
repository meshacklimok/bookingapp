/// Supplied at build time, so no keys live in source control:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Where auth emails send the user back into the app. Must also be listed under
  /// Supabase Dashboard > Authentication > URL Configuration > Redirect URLs.
  static const authRedirectUrl = 'com.example.bookingapp://auth-callback';

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'features/tickets/data/ticket_cache.dart';

Future<void> main() async {
  // Without a SENTRY_DSN (local runs, tests) the app starts the same, just without crash reports.
  if (Env.sentryDsn.isEmpty) return _start();
  await SentryFlutter.init(
    (o) {
      o.dsn = Env.sentryDsn;
      o.environment = kReleaseMode ? 'production' : 'development';
      // Bookings carry names and phone numbers; reports only get the user id set below.
      o.sendDefaultPii = false;
    },
    appRunner: _start,
  );
}

Future<void> _start() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Supabase.initialize throws on an empty URL, so explain the fix instead of crashing.
  if (!Env.isConfigured) {
    runApp(const MissingConfigApp());
    return;
  }
  await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
  Supabase.instance.client.auth.onAuthStateChange.listen((s) {
    final id = s.session?.user.id;
    Sentry.configureScope((scope) => scope.setUser(id == null ? null : SentryUser(id: id)));
    // Covers every way out: the sign-out button, account deletion and an expired session.
    if (s.event == AuthChangeEvent.signedOut) TicketCache().clear();
  });
  runApp(const ProviderScope(child: BookingApp()));
}

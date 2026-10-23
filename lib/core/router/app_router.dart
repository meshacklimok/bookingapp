import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/booking/presentation/booking_screen.dart';
import '../../features/booking/presentation/my_bookings_screen.dart';
import '../../features/checkout/presentation/checkout_screen.dart';
import '../../features/discover/presentation/discover_screen.dart';
import '../../features/discover/presentation/service_detail_screen.dart';
import '../../features/org_dashboard/presentation/org_dashboard_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/scanner/presentation/scanner_screen.dart';
import '../../features/tickets/presentation/ticket_detail_screen.dart';
import '../../features/tickets/presentation/tickets_screen.dart';
import '../../shared/widgets/main_shell.dart';
import '../supabase/supabase_providers.dart';

/// Re-runs the router redirect whenever the auth state changes.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Stream<dynamic> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(supabaseProvider).auth;
  final refresh = _AuthRefresh(auth.onAuthStateChange);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = auth.currentSession != null;
      final path = state.matchedLocation;
      // Guests can browse; everything that books, pays or shows personal data needs an account.
      final isPublic = path == '/' || path == '/login' || path.startsWith('/service/');
      if (!loggedIn && !isPublic) return '/login';
      if (loggedIn && path == '/login') return '/';
      return null;
    },
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => MainShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/', builder: (context, state) => const DiscoverScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/bookings', builder: (context, state) => const MyBookingsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/tickets', builder: (context, state) => const TicketsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
          ]),
        ],
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/service/:id',
        builder: (context, state) => ServiceDetailScreen(serviceId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/book/:id',
        builder: (context, state) => BookingScreen(serviceId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/checkout/:bookingId',
        builder: (context, state) => CheckoutScreen(bookingId: state.pathParameters['bookingId']!),
      ),
      GoRoute(
        path: '/ticket/:id',
        builder: (context, state) => TicketDetailScreen(ticketId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/scanner', builder: (context, state) => const ScannerScreen()),
      GoRoute(
        path: '/org/:orgId',
        builder: (context, state) => OrgDashboardScreen(orgId: state.pathParameters['orgId']!),
      ),
    ],
  );
});

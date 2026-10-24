import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/reset_password_screen.dart';
import '../../features/booking/presentation/booking_screen.dart';
import '../../features/booking/presentation/my_bookings_screen.dart';
import '../../features/checkout/presentation/checkout_screen.dart';
import '../../features/discover/presentation/discover_screen.dart';
import '../../features/discover/presentation/service_detail_screen.dart';
import '../../features/admin/presentation/admin_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/org_dashboard/presentation/earnings_screen.dart';
import '../../features/org_dashboard/presentation/payouts_screen.dart';
import '../../features/org_dashboard/presentation/org_dashboard_screen.dart';
import '../../features/org_dashboard/presentation/register_org_screen.dart';
import '../../features/org_dashboard/presentation/service_form_screen.dart';
import '../../features/org_dashboard/presentation/staff_detail_screen.dart';
import '../../features/org_dashboard/presentation/staff_hours_screen.dart';
import '../../features/org_dashboard/presentation/staff_screen.dart';
import '../../features/org_dashboard/presentation/services_screen.dart';
import '../../features/profile/presentation/edit_profile_screen.dart';
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

/// Guests can browse; everything that books, pays or shows personal data needs an account.
/// A guest sent to /login carries the page they wanted in `from`, and returns there after signing in.
String? authRedirect({required bool loggedIn, required Uri location}) {
  final path = location.path;
  final isPublic = path == '/' || path == '/login' || path.startsWith('/service/');
  if (!loggedIn && !isPublic) {
    return Uri(path: '/login', queryParameters: {'from': location.toString()}).toString();
  }
  if (loggedIn && path == '/login') {
    final from = location.queryParameters['from'];
    // Only same-app paths, never an absolute URL smuggled in through a deep link.
    return (from != null && from.startsWith('/') && !from.startsWith('//')) ? from : '/';
  }
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(supabaseProvider).auth;
  final refresh = _AuthRefresh(auth.onAuthStateChange);
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) => authRedirect(loggedIn: auth.currentSession != null, location: state.uri),
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
            GoRoute(
              path: '/profile',
              builder: (context, state) => const ProfileScreen(),
              routes: [
                GoRoute(path: 'edit', builder: (context, state) => const EditProfileScreen()),
              ],
            ),
          ]),
        ],
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/reset-password', builder: (context, state) => const ResetPasswordScreen()),
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
      GoRoute(path: '/notifications', builder: (context, state) => const NotificationsScreen()),
      GoRoute(path: '/admin', builder: (context, state) => const AdminScreen()),
      // must stay above /org/:orgId, which would otherwise take "register" as an id
      GoRoute(path: '/org/register', builder: (context, state) => const RegisterOrgScreen()),
      GoRoute(
        path: '/org/:orgId',
        builder: (context, state) => OrgDashboardScreen(orgId: state.pathParameters['orgId']!),
        routes: [
          GoRoute(
            path: 'services',
            builder: (context, state) => ServicesScreen(orgId: state.pathParameters['orgId']!),
            routes: [
              // "new" must stay above :serviceId
              GoRoute(
                path: 'new',
                builder: (context, state) => ServiceFormScreen(orgId: state.pathParameters['orgId']!),
              ),
              GoRoute(
                path: ':serviceId',
                builder: (context, state) => ServiceFormScreen(
                  orgId: state.pathParameters['orgId']!,
                  serviceId: state.pathParameters['serviceId'],
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'payouts',
            builder: (context, state) => PayoutsScreen(orgId: state.pathParameters['orgId']!),
          ),
          GoRoute(
            path: 'earnings',
            builder: (context, state) => EarningsScreen(orgId: state.pathParameters['orgId']!),
          ),
          GoRoute(
            path: 'staff',
            builder: (context, state) => StaffScreen(orgId: state.pathParameters['orgId']!),
            routes: [
              GoRoute(
                path: ':staffId',
                builder: (context, state) => StaffDetailScreen(
                  orgId: state.pathParameters['orgId']!,
                  staffId: state.pathParameters['staffId']!,
                ),
                routes: [
                  GoRoute(
                    path: 'hours',
                    builder: (context, state) => StaffHoursScreen(
                      orgId: state.pathParameters['orgId']!,
                      staffId: state.pathParameters['staffId']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );

  // A password reset link signs the user in with a recovery session; send them to set a new password.
  final recovery = auth.onAuthStateChange
      .where((s) => s.event == AuthChangeEvent.passwordRecovery)
      .listen((_) => router.go('/reset-password'));
  ref.onDispose(recovery.cancel);
  ref.onDispose(router.dispose);

  return router;
});

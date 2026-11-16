import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/notifications/data/notification_repository.dart';

class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationsProvider);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width =
              constraints.maxWidth > 1200 ? 1200.0 : constraints.maxWidth;

          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              height: constraints.maxHeight,
              child: Column(
                children: [
                  const Material(
                    color: Colors.amber,
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: Center(
                        child: Text(
                          'DIAGNOSTIC: MAIN SHELL BODY IS VISIBLE',
                          style: TextStyle(color: Colors.black),
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: shell),
                ],
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: LayoutBuilder(
        builder: (context, constraints) {
          final width =
              constraints.maxWidth > 1200 ? 1200.0 : constraints.maxWidth;

          return Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: width,
              child: NavigationBar(
                selectedIndex: shell.currentIndex,
                onDestinationSelected: (i) => shell.goBranch(
                  i,
                  initialLocation: i == shell.currentIndex,
                ),
                destinations: [
                  const NavigationDestination(
                    icon: Icon(Icons.explore_outlined),
                    selectedIcon: Icon(Icons.explore),
                    label: 'Discover',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.event_note_outlined),
                    selectedIcon: Icon(Icons.event_note),
                    label: 'Bookings',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.confirmation_number_outlined),
                    selectedIcon: Icon(Icons.confirmation_number),
                    label: 'Tickets',
                  ),
                  NavigationDestination(
                    icon: Badge(
                      isLabelVisible: unread > 0,
                      label: Text('$unread'),
                      child: const Icon(Icons.person_outline),
                    ),
                    selectedIcon: Badge(
                      isLabelVisible: unread > 0,
                      label: Text('$unread'),
                      child: const Icon(Icons.person),
                    ),
                    label: 'Profile',
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

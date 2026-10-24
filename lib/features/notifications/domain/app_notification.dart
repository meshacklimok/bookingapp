class AppNotification {
  const AppNotification({required this.id, required this.title, required this.createdAt, this.body, this.readAt, this.route});

  final String id;
  final String title;
  final String? body;
  final DateTime createdAt;
  final DateTime? readAt;

  /// In-app path to open on tap, already checked by [safeRoute].
  final String? route;

  bool get isUnread => readAt == null;

  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
        id: m['id'] as String,
        title: m['title'] as String,
        body: m['body'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
        readAt: m['read_at'] == null ? null : DateTime.parse(m['read_at'] as String),
        route: safeRoute((m['data'] as Map<String, dynamic>?)?['route']),
      );
}

/// Only same-app paths are followed, never an absolute URL that ended up in a notification payload.
String? safeRoute(Object? value) {
  if (value is! String || !value.startsWith('/') || value.startsWith('//') || value.contains('://')) return null;
  return value;
}

int unreadCount(Iterable<AppNotification> items) => items.where((n) => n.isUnread).length;

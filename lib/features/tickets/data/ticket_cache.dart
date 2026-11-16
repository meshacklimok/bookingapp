import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The ticket rows the server last sent, saved with the time they were fetched.
class SavedTickets {
  const SavedTickets(this.rows, this.savedAt);

  final List<Map<String, dynamic>> rows;
  final DateTime savedAt;
}

/// Keeps the last ticket list on the device, per user, so the wallet opens without a connection.
class TicketCache {
  TicketCache([Future<SharedPreferences>? prefs]) : _prefs = prefs ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _prefs;

  static const _prefix = 'tickets.v1.';

  Future<void> save(String userId, List<Map<String, dynamic>> rows, {DateTime? now}) async {
    final prefs = await _prefs;
    await prefs.setString(
      '$_prefix$userId',
      jsonEncode({'saved_at': (now ?? DateTime.now()).toUtc().toIso8601String(), 'rows': rows}),
    );
  }

  /// Null when nothing was saved for this user, or the saved copy cannot be read.
  Future<SavedTickets?> load(String userId) async {
    final raw = (await _prefs).getString('$_prefix$userId');
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return SavedTickets(
        [for (final r in m['rows'] as List) Map<String, dynamic>.from(r as Map)],
        DateTime.parse(m['saved_at'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  /// Signing out removes every saved ticket, so the next person on this device cannot open them.
  Future<void> clear() async {
    final prefs = await _prefs;
    for (final key in prefs.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
      await prefs.remove(key);
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/errors.dart';
import '../../../shared/widgets/star_rating.dart';
import '../data/booking_repository.dart';

/// Asks for a star rating and an optional comment. Returns true when a review was saved.
Future<bool> showReviewDialog(
  BuildContext context,
  WidgetRef ref, {
  required String bookingId,
  required String title,
  int? currentRating,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _ReviewDialog(bookingId: bookingId, title: title, currentRating: currentRating),
  );
  return saved ?? false;
}

class _ReviewDialog extends ConsumerStatefulWidget {
  const _ReviewDialog({required this.bookingId, required this.title, this.currentRating});

  final String bookingId;
  final String title;
  final int? currentRating;

  @override
  ConsumerState<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends ConsumerState<_ReviewDialog> {
  final _comment = TextEditingController();
  late int _rating = widget.currentRating ?? 0;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(bookingRepositoryProvider).submitReview(widget.bookingId, rating: _rating, comment: _comment.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Rate ${widget.title}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StarRating(rating: _rating, size: 36, onChanged: (v) => setState(() => _rating = v)),
          const SizedBox(height: 12),
          TextField(
            controller: _comment,
            maxLines: 3,
            maxLength: 1000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Comment (optional)'),
          ),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Not now')),
        FilledButton(onPressed: (_busy || _rating == 0) ? null : _save, child: const Text('Submit')),
      ],
    );
  }
}

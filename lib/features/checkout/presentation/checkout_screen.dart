import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/async_body.dart';
import '../../booking/data/booking_repository.dart';
import '../../booking/domain/booking.dart';
import '../../tickets/data/ticket_repository.dart';

enum _Method { mpesa, card }

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _phone = TextEditingController();
  _Method _method = _Method.mpesa;
  bool _busy = false;
  String? _notice;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final repo = ref.read(bookingRepositoryProvider);
      if (_method == _Method.mpesa) {
        await repo.startPayment(bookingId: widget.bookingId, provider: 'mpesa', phone: _phone.text.trim());
        setState(() => _notice = 'Check your phone and enter your M-Pesa PIN to approve the payment.');
      } else {
        final res = await repo.startPayment(bookingId: widget.bookingId, provider: 'paystack');
        await launchUrl(Uri.parse(res['authorization_url'] as String), mode: LaunchMode.externalApplication);
        setState(() => _notice = 'Complete the card payment in your browser, then return here.');
      }
    } catch (e) {
      setState(() => _notice = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final booking = ref.watch(bookingStreamProvider(widget.bookingId));

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: AsyncBody<Booking?>(
        value: booking,
        onRetry: () => ref.invalidate(bookingStreamProvider(widget.bookingId)),
        data: (b) {
          if (b == null) return const EmptyState(icon: Icons.search_off, message: 'Booking not found.');
          if (b.status == 'confirmed') {
            return _Success(onView: () {
              ref.invalidate(myTicketsProvider);
              ref.invalidate(myBookingsProvider);
              context.go('/tickets');
            });
          }
          if (!b.isUnpaid) {
            return const EmptyState(icon: Icons.info_outline, message: 'This booking is no longer open for payment.');
          }
          return _form(context, b);
        },
      ),
    );
  }

  Widget _form(BuildContext context, Booking b) {
    final expired = b.expiresAt != null && b.expiresAt!.isBefore(DateTime.now());
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Total', style: Theme.of(context).textTheme.labelLarge),
        Text(formatKes(b.totalCents), style: Theme.of(context).textTheme.headlineMedium),
        if (b.expiresAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              expired ? 'Your hold has expired.' : 'Held for you until ${formatTime(b.expiresAt!.toLocal())}',
            ),
          ),
        const SizedBox(height: 24),
        SegmentedButton<_Method>(
          segments: const [
            ButtonSegment(value: _Method.mpesa, label: Text('M-Pesa'), icon: Icon(Icons.phone_android)),
            ButtonSegment(value: _Method.card, label: Text('Card'), icon: Icon(Icons.credit_card)),
          ],
          selected: {_method},
          onSelectionChanged: (s) => setState(() => _method = s.first),
        ),
        const SizedBox(height: 16),
        if (_method == _Method.mpesa)
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'M-Pesa phone number', hintText: '0712345678'),
          ),
        if (_notice != null) ...[
          const SizedBox(height: 16),
          Text(_notice!),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: (_busy || expired) ? null : _pay,
          child: _busy
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text('Pay ${formatKes(b.totalCents)}'),
        ),
      ],
    );
  }
}

class _Success extends StatelessWidget {
  const _Success({required this.onView});

  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('Payment received', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('Your booking is confirmed.'),
            const SizedBox(height: 24),
            FilledButton(onPressed: onView, child: const Text('View my tickets')),
          ],
        ),
      ),
    );
  }
}

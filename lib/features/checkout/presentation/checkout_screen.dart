import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/async_body.dart';
import '../../booking/data/booking_repository.dart';
import '../../booking/domain/booking.dart';
import '../../booking/domain/deposit.dart';
import '../../discover/data/service_repository.dart';
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
  final _promo = TextEditingController();
  _Method _method = _Method.mpesa;
  bool _busy = false;
  String? _notice;

  @override
  void dispose() {
    _phone.dispose();
    _promo.dispose();
    super.dispose();
  }

  bool get _depositChosen => (ref.read(bookingStreamProvider(widget.bookingId)).value?.balanceCents ?? 0) > 0;

  Future<void> _setPlan(bool deposit) async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await ref.read(bookingRepositoryProvider).setPaymentPlan(widget.bookingId, deposit: deposit);
    } catch (e) {
      _notice = friendlyError(e);
    }
    ref.invalidate(bookingStreamProvider(widget.bookingId));
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _applyPromo() async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    final repo = ref.read(bookingRepositoryProvider);
    try {
      final wasDeposit = _depositChosen;
      await repo.applyPromo(widget.bookingId, _promo.text.trim());
      // A code changes the price, which resets the payment plan; keep the customer's choice.
      if (wasDeposit) await repo.setPaymentPlan(widget.bookingId, deposit: true);
      _promo.clear();
    } catch (e) {
      _notice = friendlyError(e);
    }
    // The checkout watches the booking live, but a plain update may not be pushed to a stale stream.
    ref.invalidate(bookingStreamProvider(widget.bookingId));
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _removePromo() async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(bookingRepositoryProvider);
      final wasDeposit = _depositChosen;
      await repo.removePromo(widget.bookingId);
      if (wasDeposit) await repo.setPaymentPlan(widget.bookingId, deposit: true);
    } catch (e) {
      _notice = friendlyError(e);
    }
    ref.invalidate(bookingStreamProvider(widget.bookingId));
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _confirmFree() async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await ref.read(bookingRepositoryProvider).confirmFree(widget.bookingId);
      ref.invalidate(bookingStreamProvider(widget.bookingId));
    } catch (e) {
      _notice = friendlyError(e);
    }
    if (mounted) setState(() => _busy = false);
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
        Text(b.balanceCents > 0 ? 'Pay now' : 'Total', style: Theme.of(context).textTheme.labelLarge),
        Text(formatKes(b.totalCents), style: Theme.of(context).textTheme.headlineMedium),
        if (b.balanceCents > 0)
          Text('${formatKes(b.balanceCents)} is paid at the venue (full price ${formatKes(b.fullPriceCents)}).'),
        if (b.discountCents > 0)
          Text('Promo code saved you ${formatKes(b.discountCents)}', style: Theme.of(context).textTheme.bodyMedium),
        if (b.expiresAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              expired ? 'Your hold has expired.' : 'Held for you until ${formatTime(b.expiresAt!.toLocal())}',
            ),
          ),
        const SizedBox(height: 20),
        if (b.status == 'held' && b.fullPriceCents > 0) ..._depositChoice(b, expired),
        // Codes only change an unpaid hold; once a payment has started the price is fixed.
        if (b.status == 'held') ...[
          if (b.discountCents > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: (_busy || expired) ? null : _removePromo, child: const Text('Remove promo code')),
            )
          else
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _promo,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Promo code (optional)'),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(onPressed: (_busy || expired) ? null : _applyPromo, child: const Text('Apply')),
              ],
            ),
          const SizedBox(height: 20),
        ],
        if (b.totalCents == 0) ...[
          if (_notice != null) Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(_notice!)),
          FilledButton(
            onPressed: (_busy || expired) ? null : _confirmFree,
            child: _busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Confirm booking'),
          ),
        ] else ..._paymentFields(context, b, expired),
      ],
    );
  }

  /// Only for services that offer a deposit, and only while the hold is unpaid.
  List<Widget> _depositChoice(Booking b, bool expired) {
    final pct = ref.watch(serviceProvider(b.serviceId)).value?.depositPct;
    if (pct == null) return const [];
    final deposit = depositCents(b.fullPriceCents, pct);
    return [
      SegmentedButton<bool>(
        segments: [
          ButtonSegment(value: false, label: Text('Pay in full\n${formatKes(b.fullPriceCents)}', textAlign: TextAlign.center)),
          ButtonSegment(value: true, label: Text('Deposit $pct%\n${formatKes(deposit)}', textAlign: TextAlign.center)),
        ],
        selected: {b.balanceCents > 0},
        onSelectionChanged: (_busy || expired) ? null : (s) => _setPlan(s.first),
      ),
      const SizedBox(height: 20),
    ];
  }

  List<Widget> _paymentFields(BuildContext context, Booking b, bool expired) {
    return [
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
    ];
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

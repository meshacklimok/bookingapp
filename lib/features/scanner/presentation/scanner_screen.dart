import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/utils/formatters.dart';
import '../../tickets/data/ticket_repository.dart';

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  final _controller = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool _checking = false;
  _Verdict? _verdict;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_checking || _verdict != null) return;
    final code = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (code == null) return;

    _checking = true;
    try {
      final res = await ref.read(ticketRepositoryProvider).verify(code);
      if (mounted) setState(() => _verdict = _Verdict.from(res));
    } catch (_) {
      if (mounted) setState(() => _verdict = const _Verdict(ok: false, title: 'Network error', detail: 'Try scanning again.'));
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final verdict = _verdict;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan tickets')),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          if (verdict != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Card(
                color: verdict.ok ? Colors.green.shade700 : Colors.red.shade700,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(verdict.title,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white)),
                      if (verdict.detail.isNotEmpty)
                        Text(verdict.detail, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                        onPressed: () => setState(() => _verdict = null),
                        child: const Text('Scan next'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Verdict {
  const _Verdict({required this.ok, required this.title, required this.detail});

  final bool ok;
  final String title;
  final String detail;

  factory _Verdict.from(Map<String, dynamic> r) {
    final service = r['service'] as String? ?? '';
    switch (r['result']) {
      case 'ok':
        final holder = r['holder'] as String?;
        return _Verdict(ok: true, title: 'Valid ticket', detail: [service, if (holder != null) holder].join('\n'));
      case 'already_used':
        final at = r['checked_in_at'] as String?;
        return _Verdict(
          ok: false,
          title: 'Already used',
          detail: at == null ? service : 'Checked in ${formatDateTime(DateTime.parse(at))}',
        );
      case 'void':
        return const _Verdict(ok: false, title: 'Ticket cancelled', detail: '');
      case 'forbidden':
        return const _Verdict(ok: false, title: 'Not your event', detail: 'This ticket belongs to another organization.');
      default:
        return const _Verdict(ok: false, title: 'Invalid ticket', detail: 'This code is not recognised.');
    }
  }
}

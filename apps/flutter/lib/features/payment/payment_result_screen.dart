import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/page_form_scaffold.dart';

class PaymentSuccessScreen extends ConsumerStatefulWidget {
  const PaymentSuccessScreen({
    super.key,
    required this.paymentKey,
    required this.orderId,
    required this.amount,
  });

  final String? paymentKey;
  final String? orderId;
  final String? amount;

  @override
  ConsumerState<PaymentSuccessScreen> createState() =>
      _PaymentSuccessScreenState();
}

class _PaymentSuccessScreenState extends ConsumerState<PaymentSuccessScreen> {
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _confirm();
  }

  Future<void> _confirm() async {
    final amount = int.tryParse(widget.amount ?? '');
    if (widget.paymentKey == null || widget.orderId == null || amount == null) {
      setState(() {
        _loading = false;
        _error = '결제 승인 정보가 올바르지 않습니다.';
      });
      return;
    }
    try {
      await ref
          .read(apiClientProvider)
          .confirmTossPayment(
            paymentKey: widget.paymentKey!,
            orderId: widget.orderId!,
            amount: amount,
          );
      ref.invalidate(cartProvider);
      ref.invalidate(ordersProvider);
    } on ApiException catch (error) {
      try {
        final payment = await ref
            .read(apiClientProvider)
            .tossPaymentStatus(widget.orderId!);
        if (payment.status != 'paid') _error = error.message;
      } catch (_) {
        _error = error.message;
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageFormScaffold(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                _error == null ? Icons.check_circle : Icons.error_outline,
                size: 52,
                color: _error == null
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                _loading
                    ? '결제를 확인하고 있습니다'
                    : _error == null
                    ? '결제가 완료되었습니다'
                    : '결제를 완료하지 못했습니다',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              Text(
                _loading
                    ? '창을 닫거나 새로고침하지 마세요.'
                    : (_error ?? '주문 내역에서 배송 상태를 확인할 수 있습니다.'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else
                FilledButton(
                  onPressed: () =>
                      context.go(_error == null ? '/orders' : '/cart'),
                  child: Text(_error == null ? '주문 내역 보기' : '장바구니로'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class PaymentFailScreen extends StatelessWidget {
  const PaymentFailScreen({super.key, this.code, this.message, this.orderId});

  final String? code;
  final String? message;
  final String? orderId;

  @override
  Widget build(BuildContext context) {
    return PageFormScaffold(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.error_outline,
                size: 52,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                '결제가 완료되지 않았습니다',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              Text(message ?? '장바구니는 그대로 유지됩니다.', textAlign: TextAlign.center),
              if (code != null) ...[
                const SizedBox(height: 6),
                Text(
                  '오류 코드: $code',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => context.go('/cart'),
                child: const Text('장바구니로'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

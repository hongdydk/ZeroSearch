import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format/price_format.dart';
import '../../core/fulfillment/fulfillment_labels.dart';
import '../../core/models/models.dart';
import '../../core/network/api_exception.dart';
import '../../core/payment/toss_payment_bridge.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/async_busy.dart';
import '../../shared/widgets/page_form_scaffold.dart';

String _newIdempotencyKey() {
  final rand = Random.secure().nextInt(1 << 32).toRadixString(16);
  return '${DateTime.now().toUtc().microsecondsSinceEpoch}-$rand';
}

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen>
    with AsyncBusyState {
  bool _checkingOut = false;
  String? _checkoutKey;
  String? _selectedAddressId;

  void _invalidateCheckoutKey() {
    _checkoutKey = null;
  }

  Future<void> _pay(ShippingAddressModel address) async {
    setState(() {
      _checkingOut = true;
      _checkoutKey ??= _newIdempotencyKey();
    });
    final key = _checkoutKey!;
    try {
      final prepared = await ref
          .read(apiClientProvider)
          .prepareTossPayment(idempotencyKey: key, addressId: address.id);
      final origin = Uri.base.origin;
      await requestTossCardPayment(
        clientKey: prepared.clientKey,
        customerKey: prepared.customerKey,
        orderId: prepared.orderId,
        orderName: prepared.orderName,
        amount: prepared.amount,
        successUrl: '$origin/payment/success',
        failUrl: '$origin/payment/fail',
      );
    } on ApiException catch (e) {
      final retryable = e.message.contains('시간') || e.message.contains('연결');
      if (!retryable) {
        _invalidateCheckoutKey();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final message = e is StateError
          ? e.message
          : '결제 페이지로 이동하지 못했습니다. $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartAsync = ref.watch(cartProvider);
    final addressesAsync = ref.watch(addressesProvider);

    return PageFormScaffold(
      child: cartAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('장바구니를 불러오지 못했습니다.')),
        data: (cart) {
          if (cart.items.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('주문서', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 24),
                const Text('장바구니가 비어 있습니다.'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.go('/'),
                  child: const Text('상품 둘러보기'),
                ),
              ],
            );
          }

          return addressesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const Center(child: Text('배송지를 불러오지 못했습니다.')),
            data: (addresses) {
              final selected = _pickAddress(addresses);
              final canPay =
                  tossPaymentSupported &&
                  !cart.checkoutBlocked &&
                  selected != null &&
                  !_checkingOut &&
                  !isBusy();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('주문서', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 16),
                  Text(
                    '배송지',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (addresses.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('등록된 배송지가 없습니다. 결제 전에 주소를 추가해 주세요.'),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: () => context.push(
                                '/settings/addresses/new',
                              ),
                              child: const Text('배송지 추가'),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ...addresses.map((address) {
                      return Card(
                        child: RadioListTile<String>(
                          value: address.id,
                          groupValue: selected?.id,
                          onChanged: (value) {
                            _invalidateCheckoutKey();
                            setState(() => _selectedAddressId = value);
                          },
                          title: Text(
                            '${address.recipientName}${address.isDefault ? ' · 기본' : ''}',
                          ),
                          subtitle: Text(
                            '${address.line}\n${address.phone}',
                          ),
                          isThreeLine: true,
                        ),
                      );
                    }),
                  if (addresses.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () =>
                            context.push('/settings/addresses/new'),
                        child: const Text('배송지 추가'),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    '주문 상품',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...cart.items.map(
                    (item) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.productTitle),
                      subtitle: Text(
                        '${shippingOwnerLabel(item.sellerType)} · ${item.shopName}',
                      ),
                      trailing: Text(formatWonLine(item.priceCredits, item.qty)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '합계: ${formatWon(cart.totalCredits)}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (cart.checkoutBlocked) ...[
                    const SizedBox(height: 8),
                    Text(
                      '구매할 수 없는 상품이 있어 주문할 수 없습니다.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  if (!tossPaymentSupported) ...[
                    const SizedBox(height: 8),
                    const Text('토스 결제는 현재 웹에서만 지원합니다.'),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: canPay ? () => _pay(selected) : null,
                    child: Text(_checkingOut ? '결제 준비 중…' : '토스로 결제하기'),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  ShippingAddressModel? _pickAddress(List<ShippingAddressModel> addresses) {
    if (addresses.isEmpty) return null;
    final selected = _selectedAddressId;
    if (selected != null) {
      for (final address in addresses) {
        if (address.id == selected) return address;
      }
    }
    for (final address in addresses) {
      if (address.isDefault) return address;
    }
    return addresses.first;
  }
}

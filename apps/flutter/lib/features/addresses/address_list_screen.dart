import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/page_form_scaffold.dart';

class AddressListScreen extends ConsumerWidget {
  const AddressListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addressesAsync = ref.watch(addressesProvider);

    return PageFormScaffold(
      child: addressesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('배송지를 불러오지 못했습니다.'),
              TextButton(
                onPressed: () => ref.invalidate(addressesProvider),
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
        data: (addresses) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('배송지', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              if (addresses.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text('저장된 배송지가 없습니다.'),
                ),
              ...addresses.map(
                (address) => Card(
                  child: ListTile(
                    title: Text(
                      '${address.recipientName}${address.isDefault ? ' · 기본' : ''}',
                    ),
                    subtitle: Text('${address.line}\n${address.phone}'),
                    isThreeLine: true,
                    onTap: () =>
                        context.push('/settings/addresses/${address.id}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(context, ref, address),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.push('/settings/addresses/new'),
                child: const Text('배송지 추가'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ShippingAddressModel address,
  ) async {
    try {
      await ref.read(apiClientProvider).deleteAddress(address.id);
      ref.invalidate(addressesProvider);
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}

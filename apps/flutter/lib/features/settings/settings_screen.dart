import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/app_providers.dart';
import '../../shared/widgets/page_form_scaffold.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull?.user;

    return PageFormScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('설정', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('계정', style: Theme.of(context).textTheme.titleMedium),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('닉네임'),
                    subtitle: Text(user?.displayName ?? '—'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('이메일'),
                    subtitle: Text(user?.email ?? '—'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('앱', style: Theme.of(context).textTheme.titleMedium),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('알림'),
                    subtitle: Text('미구현'),
                    enabled: false,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: const Text('판매자 센터'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/seller'),
            ),
          ),
          if (user?.isAdmin == true) ...[
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('관리자'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/admin'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

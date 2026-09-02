import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/page_form_scaffold.dart';

class MembershipScreen extends ConsumerStatefulWidget {
  const MembershipScreen({super.key});

  @override
  ConsumerState<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends ConsumerState<MembershipScreen> {
  String? _subscribingSlug;

  Future<void> _subscribe(String slug) async {
    setState(() => _subscribingSlug = slug);
    try {
      await ref.read(apiClientProvider).subscribe(slug);
      ref.invalidate(myMembershipProvider);
      ref.invalidate(creditsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('멤버십 구독이 완료되었습니다.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Theme.of(context).colorScheme.error),
      );
    } finally {
      if (mounted) setState(() => _subscribingSlug = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plansAsync = ref.watch(membershipPlansProvider);
    final subAsync = ref.watch(myMembershipProvider);

    return PageFormScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('멤버십', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          subAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('구독 상태를 불러오지 못했습니다: $e'),
            data: (sub) {
              if (sub == null) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('현재 활성 구독이 없습니다.'),
                  ),
                );
              }
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('현재 플랜: ${sub.planName}', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text('상태: ${sub.status}'),
                      Text('만료: ${_formatDate(sub.currentPeriodEnd)}'),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Text('플랜', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          plansAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('플랜을 불러오지 못했습니다: $e'),
            data: (plans) => Column(
              children: plans.map((plan) {
                final loading = _subscribingSlug == plan.slug;
                return Card(
                  child: ListTile(
                    title: Text(plan.name),
                    subtitle: Text('💎 ${plan.priceCredits} / ${plan.interval}'),
                    trailing: plan.slug == 'free'
                        ? const Text('기본')
                        : FilledButton(
                            onPressed: loading ? null : () => _subscribe(plan.slug),
                            child: Text(loading ? '처리 중…' : '구독'),
                          ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

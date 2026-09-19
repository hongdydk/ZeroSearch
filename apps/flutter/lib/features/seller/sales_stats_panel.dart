import 'package:flutter/material.dart';

import '../../core/format/price_format.dart';
import '../../shared/widgets/portal_workspace.dart';

int _number(Map<String, dynamic> stats, String key) =>
    (stats[key] as num?)?.toInt() ?? 0;

class SalesStatsPanel extends StatelessWidget {
  const SalesStatsPanel({super.key, required this.stats});

  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    final days = (stats['dailySales'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final peak = days.fold<int>(0, (max, day) {
      final amount = (day['amount'] as num?)?.toInt() ?? 0;
      return amount > max ? amount : max;
    });
    final fulfillment = (stats['fulfillmentCounts'] as Map<String, dynamic>? ?? const {});
    final offers = (stats['offerCounts'] as Map<String, dynamic>? ?? const {});
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PortalMetricGrid(children: [
          PortalMetricCard(label: '결제 완료 주문', value: '${_number(stats, 'paidOrderCount')}건'),
          PortalMetricCard(label: '판매 주문 줄', value: '${_number(stats, 'salesLineCount')}건'),
          PortalMetricCard(label: '판매 품목', value: '${_number(stats, 'soldItemCount')}종'),
          PortalMetricCard(label: '판매 수량', value: '${_number(stats, 'soldQtySum')}개'),
          PortalMetricCard(label: '판매 금액', value: formatWon(_number(stats, 'soldAmountSum'))),
        ]),
        const SizedBox(height: 18),
        PortalSection(
          title: '최근 30일 판매 금액',
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: days.isEmpty || peak == 0
                ? const Text('최근 30일 결제 완료 주문이 없습니다.')
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final day in days)
                          Tooltip(
                            message: '${day['date']} · ${day['lineCount']}건 · ${formatWon((day['amount'] as num?)?.toInt() ?? 0)}',
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 16,
                                    height: 8 + 92 * (((day['amount'] as num?)?.toInt() ?? 0) / peak),
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                  const SizedBox(height: 5),
                                  Text((day['date'] as String? ?? '').substring(5)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 18),
        PortalSection(
          title: '배송 상태 · 판매 주문 줄',
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Wrap(spacing: 24, runSpacing: 8, children: [
              for (final entry in const {'paid': '결제 완료', 'preparing': '준비 중', 'shipped': '배송 중', 'delivered': '배송 완료'}.entries)
                Text('${entry.value} ${fulfillment[entry.key] ?? 0}건'),
            ]),
          ),
        ),
        const SizedBox(height: 18),
        PortalSection(
          title: '현재 오퍼 상태',
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Wrap(spacing: 24, runSpacing: 8, children: [
              for (final entry in const {'published': '공개', 'draft': '초안', 'archived': '숨김'}.entries)
                Text('${entry.value} ${offers[entry.key] ?? 0}건'),
            ]),
          ),
        ),
      ],
    );
  }
}

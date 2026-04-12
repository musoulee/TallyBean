import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tally_design_system/tally_design_system.dart';

import 'package:tally_bean/features/overview/application/overview_providers.dart';
import 'package:tally_bean/features/overview/presentation/widgets/recent_transactions.dart';
import 'package:tally_bean/features/overview/presentation/widgets/trend_summary.dart';
import 'package:tally_bean/shared/widgets/async_loading_view.dart';

class OverviewPage extends ConsumerWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(overviewSnapshotProvider);

    return snapshot.when(
      data: (data) {
        final theme = Theme.of(context);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(
                  colors: [Color(0xFFF0E5D1), Color(0xFFFBF8F1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('净资产', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Text(data.netWorth, style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 4),
                  Text(
                    data.changeDescription,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TallyMetricCard(
                    label: '总资产',
                    value: data.totalAssets,
                    accent: const Color(0xFF4E6A40),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TallyMetricCard(
                    label: '总负债',
                    value: data.totalLiabilities,
                    accent: const Color(0xFFA45B46),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const TallySectionCard(title: '近期收支趋势', child: TrendSummary()),
            const SizedBox(height: 16),
            TallySectionCard(
              title: '最近交易',
              child: RecentTransactions(entries: data.recentTransactions),
            ),
          ],
        );
      },
      loading: () => const AsyncLoadingView(),
      error: (error, _) => Center(child: Text('概览加载失败: $error')),
    );
  }
}

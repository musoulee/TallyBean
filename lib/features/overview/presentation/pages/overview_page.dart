import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tally_bean/features/overview/application/overview_providers.dart';
import 'package:tally_bean/features/overview/presentation/widgets/overview_summary_card.dart';
import 'package:tally_bean/features/overview/presentation/widgets/recent_transactions.dart';
import 'package:tally_bean/features/overview/presentation/widgets/trend_summary.dart';
import 'package:tally_design_system/tally_design_system.dart';
import 'package:tally_bean/shared/widgets/async_loading_view.dart';
import 'package:tally_bean/shared/widgets/async_error_view.dart';

class OverviewPage extends ConsumerWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(overviewSnapshotProvider);

    return snapshot.when(
      data: (data) {
        final viewPadding = MediaQuery.viewPaddingOf(context);
        // Standard FAB height is 56, plus bottom padding, plus some extra breathing room.
        final bottomPadding = viewPadding.bottom + 104;

        return RefreshIndicator(
          onRefresh: () => ref.refresh(overviewSnapshotProvider.future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
            children: [
              OverviewSummaryCard(snapshot: data),
              const SizedBox(height: 16),
              const TrendSummary(),
              const SizedBox(height: 16),
              TallySectionCard(
                title: '最近交易',
                child: RecentTransactions(entries: data.recentTransactions),
              ),
            ],
          ),
        );
      },
      loading: () => const AsyncLoadingView(),
      error: (error, _) => AsyncErrorView(
        error: error,
        message: '概览加载失败',
        onRetry: () => ref.invalidate(overviewSnapshotProvider),
      ),
    );
  }
}

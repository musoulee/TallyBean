import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tally_bean/app/session/quick_entry_session.dart';
import 'package:tally_bean/features/overview/application/overview_providers.dart';
import 'package:tally_bean/features/overview/presentation/widgets/overview_summary_card.dart';
import 'package:tally_bean/features/overview/presentation/widgets/recent_transactions.dart';
import 'package:tally_bean/features/overview/presentation/widgets/trend_summary.dart';
import 'package:tally_bean/features/workspace/application/workspace_providers.dart';
import 'package:tally_design_system/tally_design_system.dart';
import 'package:tally_bean/shared/widgets/async_loading_view.dart';
import 'package:tally_bean/shared/widgets/async_error_view.dart';
import 'package:tally_bean/shared/widgets/quick_entry_feedback_banner.dart';
import 'package:tally_bean/shared/widgets/workspace_gate_view.dart';
import 'package:beancount_domain/beancount_domain.dart';

class OverviewPage extends ConsumerWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaceState = ref.watch(currentWorkspaceProvider);
    final workspace = workspaceState.asData?.value;

    if (workspaceState.hasError && workspace == null) {
      return AsyncErrorView(
        error: workspaceState.error!,
        message: '工作区加载失败',
        onRetry: () => ref.invalidate(currentWorkspaceProvider),
      );
    }
    if (workspaceState.isLoading) {
      return const AsyncLoadingView();
    }
    if (workspace == null) {
      return const WorkspaceGateView(
        title: '还没有账本',
        message: '先导入一个本地 beancount 工作区，再查看首页总览。',
      );
    }
    if (workspace.status == WorkspaceStatus.issuesFirst) {
      return const WorkspaceGateView(
        title: '账本需要先修复',
        message: '当前账本存在阻塞性问题，请先前往工作区查看 issues。',
      );
    }

    final snapshot = ref.watch(overviewSnapshotProvider);
    final latestSavedTransaction = ref.watch(latestSavedTransactionProvider);

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
              if (latestSavedTransaction != null) ...[
                QuickEntryFeedbackBanner(receipt: latestSavedTransaction),
                const SizedBox(height: 16),
              ],
              OverviewSummaryCard(snapshot: data),
              const SizedBox(height: 16),
              TrendSummary(
                weekTrend: data.weekTrend,
                monthTrend: data.monthTrend,
              ),
              const SizedBox(height: 16),
              TallySectionCard(
                title: '最近交易',
                child: RecentTransactions(
                  entries: data.recentTransactions,
                  latestSavedTransaction: latestSavedTransaction,
                ),
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

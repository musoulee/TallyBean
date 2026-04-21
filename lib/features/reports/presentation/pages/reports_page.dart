import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tally_design_system/tally_design_system.dart';

import 'package:tally_bean/features/reports/application/reports_providers.dart';
import 'package:tally_bean/features/ledger/application/ledger_providers.dart';
import 'package:tally_bean/shared/widgets/async_error_view.dart';
import 'package:tally_bean/shared/widgets/async_loading_view.dart';
import 'package:tally_bean/shared/widgets/ledger_gate_view.dart';

class ReportsPage extends ConsumerWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerState = ref.watch(currentLedgerProvider);
    final ledger = ledgerState.asData?.value;
    if (ledgerState.hasError && ledger == null) {
      return AsyncErrorView(
        error: ledgerState.error!,
        message: '账本加载失败',
        onRetry: () => ref.invalidate(currentLedgerProvider),
      );
    }
    if (ledgerState.isLoading) {
      return const AsyncLoadingView();
    }
    if (ledger == null) {
      return const LedgerGateView(
        title: '还没有账本',
        message: '导入账本后，统计页才会显示真实分析结果。',
      );
    }
    if (ledger.status == LedgerStatus.issuesFirst) {
      return const LedgerGateView(
        title: '统计暂不可用',
        message: '当前账本存在阻塞性问题，请先到账本页处理 issues。',
      );
    }

    final reports = ref.watch(reportSummariesProvider);

    return reports.when(
      data: (data) => DefaultTabController(
        length: 4,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: '收支'),
                  Tab(text: '资产'),
                  Tab(text: '账户贡献'),
                  Tab(text: '时间对比'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _ReportsList(
                    cards: data[ReportCategory.incomeExpense] ?? const [],
                  ),
                  _ReportsList(cards: data[ReportCategory.assets] ?? const []),
                  _ReportsList(
                    cards: data[ReportCategory.accountContribution] ?? const [],
                  ),
                  _ReportsList(
                    cards: data[ReportCategory.timeComparison] ?? const [],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      loading: () => const AsyncLoadingView(),
      error: (error, _) => Center(child: Text('统计加载失败: $error')),
    );
  }
}

class _ReportsList extends StatelessWidget {
  const _ReportsList({required this.cards});

  final List<ReportSummary> cards;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: cards.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final card = cards[index];
        return TallySectionCard(
          title: card.title,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: card.lines
                .map(
                  (line) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(line),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }
}

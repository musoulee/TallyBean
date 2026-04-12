import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tally_design_system/tally_design_system.dart';

import 'package:tally_bean/features/reports/application/reports_providers.dart';
import 'package:tally_bean/shared/widgets/async_loading_view.dart';

class ReportsPage extends ConsumerWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

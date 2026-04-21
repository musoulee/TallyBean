import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tally_bean/app/session/quick_entry_session.dart';
import 'package:tally_bean/features/journal/application/journal_providers.dart';
import 'package:tally_bean/features/journal/application/journal_ui_models.dart';
import 'package:tally_bean/features/ledger/application/ledger_providers.dart';
import 'package:tally_bean/shared/formatters/date_label_formatter.dart';
import 'package:tally_bean/shared/formatters/journal_entry_display.dart';
import 'package:tally_bean/shared/widgets/async_error_view.dart';
import 'package:tally_bean/shared/widgets/async_loading_view.dart';
import 'package:tally_bean/shared/widgets/quick_entry_feedback_banner.dart';
import 'package:tally_bean/shared/widgets/ledger_gate_view.dart';

class JournalPage extends ConsumerWidget {
  const JournalPage({super.key});

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
        message: '导入账本后，明细时间线才会显示真实记录。',
      );
    }
    if (ledger.status == LedgerStatus.issuesFirst) {
      return const LedgerGateView(
        title: '明细已锁定',
        message: '当前账本存在阻塞性问题，请先到账本页处理 issues。',
      );
    }

    final selectedFilter = ref.watch(journalFilterProvider);
    final records = ref.watch(filteredJournalEntriesProvider);
    final latestSavedTransaction = ref.watch(latestSavedTransactionProvider);

    return records.when(
      data: (entries) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          if (latestSavedTransaction != null) ...[
            QuickEntryFeedbackBanner(receipt: latestSavedTransaction),
            const SizedBox(height: 12),
          ],
          const SearchBar(
            hintText: '搜索摘要、账户或价格',
            leading: Icon(Icons.search),
            enabled: false,
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: JournalFilter.values.map((filter) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: selectedFilter == filter,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    selectedColor: filter.color.withValues(alpha: 0.16),
                    side: BorderSide(
                      color: filter.color.withValues(alpha: 0.22),
                    ),
                    label: Text(
                      filter.label,
                      style: TextStyle(
                        color: selectedFilter == filter
                            ? filter.color
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    onSelected: (_) {
                      ref.read(journalFilterProvider.notifier).state = filter;
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          ..._buildTimeline(
            context,
            entries,
            latestSavedTransaction: latestSavedTransaction,
          ),
        ],
      ),
      loading: () => const AsyncLoadingView(),
      error: (error, _) => Center(child: Text('明细加载失败: $error')),
    );
  }

  List<Widget> _buildTimeline(
    BuildContext context,
    List<JournalEntry> entries, {
    QuickEntrySaveReceipt? latestSavedTransaction,
  }) {
    final widgets = <Widget>[];
    String? currentDate;
    var didHighlightSavedEntry = false;

    for (final entry in entries) {
      final dateLabel = formatDateLabel(entry.date);
      if (currentDate != dateLabel) {
        if (currentDate != null) {
          widgets.add(const SizedBox(height: 12));
        }
        widgets.add(
          Text(dateLabel, style: Theme.of(context).textTheme.titleMedium),
        );
        widgets.add(const SizedBox(height: 8));
        currentDate = dateLabel;
      }

      final markerColor = journalEntryColor(entry);
      final subtitle = journalEntrySubtitle(entry);
      final trailing = journalEntryTrailing(entry);
      final isHighlighted =
          !didHighlightSavedEntry &&
          latestSavedTransaction?.matches(entry) == true;
      if (isHighlighted) {
        didHighlightSavedEntry = true;
      }

      widgets.add(
        Card(
          key: isHighlighted ? const Key('journal-entry-highlight') : null,
          color: isHighlighted ? markerColor.withValues(alpha: 0.08) : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: isHighlighted
                  ? markerColor.withValues(alpha: 0.22)
                  : Colors.transparent,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: markerColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    journalEntryMarker(entry),
                    style: Theme.of(
                      context,
                    ).textTheme.titleSmall?.copyWith(color: markerColor),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.title,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          if (isHighlighted) const QuickEntryFeedbackBadge(),
                        ],
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Text(trailing, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return widgets;
  }
}

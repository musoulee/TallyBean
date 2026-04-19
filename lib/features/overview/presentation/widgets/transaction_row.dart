import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter/material.dart';

import 'package:tally_bean/shared/formatters/journal_entry_display.dart';
import 'package:tally_bean/shared/widgets/quick_entry_feedback_banner.dart';

class TransactionRow extends StatelessWidget {
  const TransactionRow({
    super.key,
    required this.entry,
    this.isHighlighted = false,
    this.highlightKey,
  });

  final JournalEntry entry;
  final bool isHighlighted;
  final Key? highlightKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final markerColor = journalEntryColor(entry);
    final subtitle = journalEntrySubtitle(entry);
    final trailing = journalEntryTrailing(entry);

    return AnimatedContainer(
      key: isHighlighted ? highlightKey : null,
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isHighlighted
            ? markerColor.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isHighlighted
              ? markerColor.withValues(alpha: 0.24)
              : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: markerColor.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Text(
              journalEntryMarker(entry),
              style: theme.textTheme.titleMedium?.copyWith(color: markerColor),
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
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    if (isHighlighted) const QuickEntryFeedbackBadge(),
                  ],
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(subtitle, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
          if (trailing.isNotEmpty) ...[
            const SizedBox(width: 12),
            Text(
              trailing,
              style: theme.textTheme.titleSmall?.copyWith(color: markerColor),
            ),
          ],
        ],
      ),
    );
  }
}

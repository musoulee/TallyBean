import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter/material.dart';

import 'package:tally_bean/shared/formatters/journal_entry_display.dart';

class TransactionRow extends StatelessWidget {
  const TransactionRow({super.key, required this.entry});

  final JournalEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final markerColor = journalEntryColor(entry);
    final subtitle = journalEntrySubtitle(entry);
    final trailing = journalEntryTrailing(entry);

    return Row(
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
              Text(entry.title, style: theme.textTheme.titleSmall),
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
    );
  }
}

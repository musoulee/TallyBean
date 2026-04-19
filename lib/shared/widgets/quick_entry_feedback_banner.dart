import 'package:flutter/material.dart';

import 'package:tally_bean/app/session/quick_entry_session.dart';

class QuickEntryFeedbackBanner extends StatelessWidget {
  const QuickEntryFeedbackBanner({
    super.key,
    required this.receipt,
  });

  final QuickEntrySaveReceipt receipt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      key: const Key('quick-entry-feedback-banner'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.check_rounded,
              color: colors.onPrimary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '刚刚记录',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${receipt.summary} · ${receipt.amountLabel}',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  receipt.pairLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class QuickEntryFeedbackBadge extends StatelessWidget {
  const QuickEntryFeedbackBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '刚刚记录',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colors.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

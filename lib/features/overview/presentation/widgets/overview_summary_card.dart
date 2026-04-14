import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter/material.dart';

class OverviewSummaryCard extends StatelessWidget {
  const OverviewSummaryCard({super.key, required this.snapshot});

  final OverviewSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final changeDescription = _sanitizeChangeDescription(
      snapshot.changeDescription,
    );

    return Container(
      key: const Key('overview-summary-card'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFFF0E5D1), Color(0xFFFBF8F1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 29,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('净资产', style: theme.textTheme.labelLarge),
                const SizedBox(height: 5),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      snapshot.netWorth,
                      style: theme.textTheme.headlineMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(changeDescription, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 23,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _SummaryMetric(
                  label: '总资产',
                  value: snapshot.totalAssets,
                  accent: const Color(0xFF4E6A40),
                  amountAlignment: Alignment.centerRight,
                ),
                const SizedBox(height: 6),
                _SummaryMetric(
                  label: '总负债',
                  value: snapshot.totalLiabilities,
                  accent: const Color(0xFFA45B46),
                  amountAlignment: Alignment.centerRight,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _sanitizeChangeDescription(String value) {
  final sanitized = value.replaceFirst(RegExp(r'\s*[·•]\s*更新于.*$'), '');

  return sanitized.trim();
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.accent,
    this.amountAlignment = Alignment.centerLeft,
  });

  final String label;
  final String value;
  final Color accent;
  final Alignment amountAlignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(label, style: theme.textTheme.labelLarge),
        ),
        const SizedBox(height: 1),
        Align(
          alignment: amountAlignment,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: amountAlignment,
            child: Text(
              value,
              textAlign: amountAlignment == Alignment.centerRight
                  ? TextAlign.right
                  : TextAlign.left,
              style: theme.textTheme.titleLarge?.copyWith(color: accent),
            ),
          ),
        ),
      ],
    );
  }
}

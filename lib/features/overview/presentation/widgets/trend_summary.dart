import 'package:flutter/material.dart';
import 'package:tally_design_system/tally_design_system.dart';
import 'package:beancount_domain/beancount_domain.dart';
import 'package:tally_bean/shared/formatters/currency_formatter.dart';

enum _TrendPeriod { week, month }

class TrendSummary extends StatefulWidget {
  const TrendSummary({
    super.key,
    required this.weekTrend,
    required this.monthTrend,
  });

  final TrendSnapshot weekTrend;
  final TrendSnapshot monthTrend;

  @override
  State<TrendSummary> createState() => _TrendSummaryState();
}

class _TrendSummaryState extends State<TrendSummary> {
  _TrendPeriod _selectedPeriod = _TrendPeriod.week;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = _selectedPeriod == _TrendPeriod.week
        ? widget.weekTrend
        : widget.monthTrend;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final metricItems = [
      _TrendMetricItem(
        label: '收入',
        value: metrics.income,
        color: const Color(0xFF4E6A40),
      ),
      _TrendMetricItem(
        label: '支出',
        value: metrics.expense,
        color: const Color(0xFFA45B46),
      ),
      _TrendMetricItem(
        label: '结余',
        value: metrics.balance,
        color: theme.colorScheme.onSurface,
      ),
    ];

    return Card(
      key: const Key('overview-trend-card'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('本周'),
                  selected: _selectedPeriod == _TrendPeriod.week,
                  showCheckmark: false,
                  onSelected: (_) {
                    setState(() {
                      _selectedPeriod = _TrendPeriod.week;
                    });
                  },
                ),
                ChoiceChip(
                  label: const Text('本月'),
                  selected: _selectedPeriod == _TrendPeriod.month,
                  showCheckmark: false,
                  onSelected: (_) {
                    setState(() {
                      _selectedPeriod = _TrendPeriod.month;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            TallyChartPlaceholder(label: metrics.chartLabel, height: 54),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final useMultiLine =
                    constraints.maxWidth < 270 || textScale > 1.15;

                if (!useMultiLine) {
                  return Row(
                    key: const Key('trend-metrics-row'),
                    children: [
                      for (
                        var index = 0;
                        index < metricItems.length;
                        index++
                      ) ...[
                        Expanded(child: metricItems[index]),
                        if (index != metricItems.length - 1)
                          const SizedBox(width: 8),
                      ],
                    ],
                  );
                }

                final wrapItemWidth = (constraints.maxWidth - 8) / 2;

                return Wrap(
                  key: const Key('trend-metrics-wrap'),
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in metricItems)
                      SizedBox(width: wrapItemWidth, child: item),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendMetricItem extends StatelessWidget {
  const _TrendMetricItem({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final num value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            formatAmount(value),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

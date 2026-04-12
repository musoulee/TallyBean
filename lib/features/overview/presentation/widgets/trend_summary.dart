import 'package:flutter/material.dart';
import 'package:tally_design_system/tally_design_system.dart';

class TrendSummary extends StatelessWidget {
  const TrendSummary({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Wrap(
          spacing: 8,
          children: [
            Chip(label: Text('7天')),
            Chip(label: Text('30天')),
            Chip(label: Text('本月')),
          ],
        ),
        const SizedBox(height: 12),
        const TallyChartPlaceholder(label: '趋势图占位'),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('收入 ¥ 20,000', style: theme.textTheme.bodyMedium),
            Text('支出 ¥ 5,860', style: theme.textTheme.bodyMedium),
            Text('结余 ¥ 14,140', style: theme.textTheme.bodyMedium),
          ],
        ),
      ],
    );
  }
}

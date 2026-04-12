import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter/material.dart';

import 'transaction_row.dart';

class RecentTransactions extends StatelessWidget {
  const RecentTransactions({super.key, required this.entries});

  final List<JournalEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < entries.length; index++) ...[
          TransactionRow(entry: entries[index]),
          if (index != entries.length - 1) const Divider(height: 24),
        ],
      ],
    );
  }
}

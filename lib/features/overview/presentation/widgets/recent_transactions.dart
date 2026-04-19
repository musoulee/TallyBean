import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter/material.dart';

import 'package:tally_bean/app/session/quick_entry_session.dart';

import 'transaction_row.dart';

class RecentTransactions extends StatelessWidget {
  const RecentTransactions({
    super.key,
    required this.entries,
    this.latestSavedTransaction,
  });

  final List<JournalEntry> entries;
  final QuickEntrySaveReceipt? latestSavedTransaction;

  @override
  Widget build(BuildContext context) {
    var didHighlightSavedRow = false;
    final children = <Widget>[];

    for (var index = 0; index < entries.length; index++) {
      final shouldHighlight =
          !didHighlightSavedRow &&
          latestSavedTransaction?.matches(entries[index]) == true;
      children.add(
        TransactionRow(
          entry: entries[index],
          isHighlighted: shouldHighlight,
          highlightKey: shouldHighlight
              ? const Key('recent-transaction-highlight')
              : null,
        ),
      );
      if (shouldHighlight) {
        didHighlightSavedRow = true;
      }
      if (index != entries.length - 1) {
        children.add(const Divider(height: 24));
      }
    }

    return Column(children: children);
  }
}

import '../journal/journal_entry.dart';

class OverviewSnapshot {
  const OverviewSnapshot({
    required this.netWorth,
    required this.totalAssets,
    required this.totalLiabilities,
    required this.changeDescription,
    required this.updatedAt,
    required this.recentTransactions,
  });

  final String netWorth;
  final String totalAssets;
  final String totalLiabilities;
  final String changeDescription;
  final DateTime updatedAt;
  final List<JournalEntry> recentTransactions;
}

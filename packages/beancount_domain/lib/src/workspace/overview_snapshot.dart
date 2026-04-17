import '../journal/journal_entry.dart';
import 'workspace.dart';

class OverviewSnapshot {
  const OverviewSnapshot({
    required this.netWorth,
    required this.totalAssets,
    required this.totalLiabilities,
    required this.changeDescription,
    required this.updatedAt,
    required this.weekTrend,
    required this.monthTrend,
    required this.recentTransactions,
  });

  final String netWorth;
  final String totalAssets;
  final String totalLiabilities;
  final String changeDescription;
  final DateTime updatedAt;
  final TrendSnapshot weekTrend;
  final TrendSnapshot monthTrend;
  final List<JournalEntry> recentTransactions;
}

enum LedgerStatus { ready, issuesFirst }

class TrendSnapshot {
  const TrendSnapshot({
    required this.chartLabel,
    required this.income,
    required this.expense,
    required this.balance,
  });

  final String chartLabel;
  final num income;
  final num expense;
  final num balance;
}

class Ledger {
  const Ledger({
    required this.id,
    required this.name,
    required this.rootPath,
    required this.lastImportedAt,
    required this.loadedFileCount,
    required this.status,
    required this.openAccountCount,
    required this.closedAccountCount,
  });

  final String id;
  final String name;
  final String rootPath;
  final DateTime lastImportedAt;
  final int loadedFileCount;
  final LedgerStatus status;
  final int openAccountCount;
  final int closedAccountCount;
}

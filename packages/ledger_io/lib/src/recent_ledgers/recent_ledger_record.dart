class RecentLedgerRecord {
  const RecentLedgerRecord({
    required this.id,
    required this.name,
    required this.path,
    required this.lastOpenedAt,
    this.entryFilePath,
  });

  final String id;
  final String name;
  final String path;
  final DateTime lastOpenedAt;
  final String? entryFilePath;
}

class CurrentLedgerRecord {
  const CurrentLedgerRecord({
    required this.id,
    required this.name,
    required this.path,
    required this.entryFilePath,
    required this.lastImportedAt,
  });

  final String id;
  final String name;
  final String path;
  final String entryFilePath;
  final DateTime lastImportedAt;
}

class ImportedLedgerSummary {
  const ImportedLedgerSummary({
    required this.ledgerId,
    required this.name,
    required this.path,
    required this.entryFilePath,
    required this.fileCount,
    required this.lastImportedAt,
  });

  final String ledgerId;
  final String name;
  final String path;
  final String entryFilePath;
  final int fileCount;
  final DateTime lastImportedAt;
}

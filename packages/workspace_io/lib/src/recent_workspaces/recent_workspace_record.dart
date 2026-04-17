class RecentWorkspaceRecord {
  const RecentWorkspaceRecord({
    required this.id,
    required this.name,
    required this.path,
    required this.lastOpenedAt,
  });

  final String id;
  final String name;
  final String path;
  final DateTime lastOpenedAt;
}

class CurrentWorkspaceRecord {
  const CurrentWorkspaceRecord({
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

class ImportedWorkspaceSummary {
  const ImportedWorkspaceSummary({
    required this.workspaceId,
    required this.name,
    required this.path,
    required this.entryFilePath,
    required this.fileCount,
    required this.lastImportedAt,
  });

  final String workspaceId;
  final String name;
  final String path;
  final String entryFilePath;
  final int fileCount;
  final DateTime lastImportedAt;
}

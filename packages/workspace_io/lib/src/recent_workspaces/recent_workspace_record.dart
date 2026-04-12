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

class ImportedWorkspaceSummary {
  const ImportedWorkspaceSummary({
    required this.workspaceId,
    required this.fileCount,
  });

  final String workspaceId;
  final int fileCount;
}

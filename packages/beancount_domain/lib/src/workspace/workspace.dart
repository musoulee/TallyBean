enum WorkspaceStatus { ready, issuesFirst }

class Workspace {
  const Workspace({
    required this.id,
    required this.name,
    required this.rootPath,
    required this.lastImportedAt,
    required this.loadedFileCount,
    required this.status,
  });

  final String id;
  final String name;
  final String rootPath;
  final DateTime lastImportedAt;
  final int loadedFileCount;
  final WorkspaceStatus status;
}

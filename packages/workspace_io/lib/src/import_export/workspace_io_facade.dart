import '../recent_workspaces/recent_workspace_record.dart';

abstract interface class WorkspaceIoFacade {
  Future<ImportedWorkspaceSummary> importWorkspace(String sourcePath);
  Future<void> exportWorkspace(String workspaceId, String destinationPath);
  Future<List<RecentWorkspaceRecord>> loadRecentWorkspaces();
}

class MemoryWorkspaceIoFacade implements WorkspaceIoFacade {
  const MemoryWorkspaceIoFacade();

  @override
  Future<void> exportWorkspace(
    String workspaceId,
    String destinationPath,
  ) async {}

  @override
  Future<ImportedWorkspaceSummary> importWorkspace(String sourcePath) async {
    return const ImportedWorkspaceSummary(
      workspaceId: 'household',
      fileCount: 12,
    );
  }

  @override
  Future<List<RecentWorkspaceRecord>> loadRecentWorkspaces() async {
    return <RecentWorkspaceRecord>[
      RecentWorkspaceRecord(
        id: 'household',
        name: 'Household Ledger',
        path: '/storage/emulated/0/Documents/beancount',
        lastOpenedAt: DateTime(2026, 4, 12, 9, 42),
      ),
    ];
  }
}

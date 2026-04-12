import 'package:beancount_bridge/beancount_bridge.dart';
import 'package:beancount_domain/beancount_domain.dart';
import 'package:workspace_io/workspace_io.dart';

import '../datasources/mock_beancount_datasource.dart';
import '../mappers/recent_workspace_mapper.dart';

class BeancountRepositoryImpl implements BeancountRepository {
  BeancountRepositoryImpl({
    required WorkspaceIoFacade workspaceIo,
    required BeancountBridgeFacade bridge,
    required MockBeancountDatasource datasource,
  }) : _workspaceIo = workspaceIo,
       _bridge = bridge,
       _datasource = datasource;

  final WorkspaceIoFacade _workspaceIo;
  final BeancountBridgeFacade _bridge;
  final MockBeancountDatasource _datasource;
  String? _cachedWorkspaceId;
  String? _cachedWorkspaceRootPath;

  @override
  Future<List<AccountNode>> loadAccountTree() async {
    return _datasource.accountTree();
  }

  @override
  Future<Workspace> loadCurrentWorkspace() async {
    final workspace = _datasource.workspace();
    final workspaceId = await _resolveWorkspaceId(workspace);

    return Workspace(
      id: workspaceId,
      name: workspace.name,
      rootPath: workspace.rootPath,
      lastImportedAt: workspace.lastImportedAt,
      loadedFileCount: workspace.loadedFileCount,
      status: workspace.status,
    );
  }

  @override
  Future<List<JournalEntry>> loadJournalEntries() async {
    return _datasource.journalEntries();
  }

  @override
  Future<OverviewSnapshot> loadOverviewSnapshot() async {
    return _datasource.overviewSnapshot();
  }

  @override
  Future<List<RecentWorkspace>> loadRecentWorkspaces() async {
    final recent = await _workspaceIo.loadRecentWorkspaces();
    return recent.map(mapRecentWorkspaceRecord).toList();
  }

  @override
  Future<Map<ReportCategory, List<ReportSummary>>> loadReportSummaries() async {
    return _datasource.reportSummaries();
  }

  @override
  Future<List<ValidationIssue>> loadValidationIssues() async {
    final workspace = _datasource.workspace();
    final workspaceId = await _resolveWorkspaceId(workspace);
    final issues = await _bridge.validateWorkspace(workspaceId);
    return issues
        .map(
          (issue) => ValidationIssue(
            message: issue.message,
            location: issue.location,
            blocking: issue.blocking,
          ),
        )
        .toList();
  }

  Future<String> _resolveWorkspaceId(Workspace workspace) async {
    if (_cachedWorkspaceId != null &&
        _cachedWorkspaceRootPath == workspace.rootPath) {
      return _cachedWorkspaceId!;
    }

    final parseResult = await _bridge.parseWorkspace(workspace.rootPath);
    _cachedWorkspaceRootPath = workspace.rootPath;
    _cachedWorkspaceId = parseResult.workspaceId;
    return parseResult.workspaceId;
  }
}

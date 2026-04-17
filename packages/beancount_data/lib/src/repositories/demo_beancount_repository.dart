import 'package:beancount_domain/beancount_domain.dart';
import 'package:workspace_io/workspace_io.dart';

import '../datasources/mock_beancount_datasource.dart';
import '../mappers/recent_workspace_mapper.dart';

class DemoBeancountRepository implements BeancountRepository {
  DemoBeancountRepository({
    required MockBeancountDatasource datasource,
    required WorkspaceIoFacade workspaceIo,
  }) : _datasource = datasource,
       _workspaceIo = workspaceIo;

  final MockBeancountDatasource _datasource;
  final WorkspaceIoFacade _workspaceIo;

  @override
  Future<void> importWorkspace(String sourcePath) async {}

  @override
  Future<List<AccountNode>> loadAccountTree() async {
    return _datasource.accountTree();
  }

  @override
  Future<Workspace?> loadCurrentWorkspace() async {
    return _datasource.workspace();
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
    return const <ValidationIssue>[];
  }

  @override
  Future<void> reopenWorkspace(String workspaceId) async {}
}

import '../accounts/account_node.dart';
import '../journal/journal_entry.dart';
import '../reports/report_summary.dart';
import '../workspace/overview_snapshot.dart';
import '../workspace/recent_workspace.dart';
import '../workspace/workspace.dart';
import 'report_category.dart';
import 'validation_issue.dart';

abstract interface class BeancountRepository {
  Future<void> importWorkspace(String sourcePath);
  Future<void> reopenWorkspace(String workspaceId);
  Future<Workspace?> loadCurrentWorkspace();
  Future<List<RecentWorkspace>> loadRecentWorkspaces();
  Future<OverviewSnapshot> loadOverviewSnapshot();
  Future<List<JournalEntry>> loadJournalEntries();
  Future<List<AccountNode>> loadAccountTree();
  Future<Map<ReportCategory, List<ReportSummary>>> loadReportSummaries();
  Future<List<ValidationIssue>> loadValidationIssues();
}

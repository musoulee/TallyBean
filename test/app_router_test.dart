import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tally_bean/app/bootstrap/app_bootstrap.dart';
import 'package:tally_bean/app/bootstrap/app_config.dart';
import 'package:tally_bean/app/di/package_registrations.dart';

void main() {
  testWidgets(
    'uses overview as initial route when local data mode is enabled',
    (tester) async {
      const config = AppConfig(useDemoData: false);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appConfigProvider.overrideWithValue(config),
            beancountRepositoryProvider.overrideWithValue(
              _NoWorkspaceRepository(),
            ),
          ],
          child: const AppBootstrap(config: config),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('还没有账本'), findsOneWidget);
      expect(find.text('账本一览'), findsNothing);
    },
  );
}

class _NoWorkspaceRepository implements BeancountRepository {
  @override
  Future<void> appendTransaction(CreateTransactionInput input) async {}

  @override
  Future<void> createDefaultWorkspace() async {}

  @override
  Future<void> importWorkspace(String sourcePath) async {}

  @override
  Future<List<AccountNode>> loadAccountTree() async => const <AccountNode>[];

  @override
  Future<Workspace?> loadCurrentWorkspace() async => null;

  @override
  Future<List<WorkspaceTextFile>> loadCurrentWorkspaceFiles() async =>
      const <WorkspaceTextFile>[];

  @override
  Future<List<JournalEntry>> loadJournalEntries() async =>
      const <JournalEntry>[];

  @override
  Future<OverviewSnapshot> loadOverviewSnapshot() async =>
      throw UnimplementedError();

  @override
  Future<List<RecentWorkspace>> loadRecentWorkspaces() async =>
      const <RecentWorkspace>[];

  @override
  Future<Map<ReportCategory, List<ReportSummary>>>
  loadReportSummaries() async => const <ReportCategory, List<ReportSummary>>{};

  @override
  Future<List<ValidationIssue>> loadValidationIssues() async =>
      const <ValidationIssue>[];

  @override
  Future<void> renameWorkspace(String workspaceId, String newName) async {}

  @override
  Future<void> deleteWorkspace(String workspaceId) async {}

  @override
  Future<void> reopenWorkspace(String workspaceId) async {}
}

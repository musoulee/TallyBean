import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tally_bean/app/di/app_providers.dart';
import 'package:tally_bean/features/workspace/presentation/pages/workspace_page.dart';

void main() {
  testWidgets(
    'does not auto initialize default ledger when workspace loading fails',
    (tester) async {
      final repository = _FakeWorkspaceRepository(
        workspaceError: StateError('workspace boom'),
        recentWorkspaces: const <RecentWorkspace>[],
      );

      await tester.pumpWidget(_host(repository));
      await tester.pumpAndSettle();

      expect(find.text('工作区加载失败'), findsOneWidget);
      expect(find.textContaining('workspace boom'), findsOneWidget);
      expect(repository.createDefaultCalls, 0);
    },
  );
}

Widget _host(BeancountRepository repository) {
  return ProviderScope(
    overrides: [beancountRepositoryProvider.overrideWithValue(repository)],
    child: const MaterialApp(home: WorkspacePage()),
  );
}

class _FakeWorkspaceRepository implements BeancountRepository {
  _FakeWorkspaceRepository({
    this.workspaceError,
    required this.recentWorkspaces,
  });

  final Object? workspaceError;
  final List<RecentWorkspace> recentWorkspaces;
  int createDefaultCalls = 0;

  @override
  Future<void> appendTransaction(CreateTransactionInput input) async {}

  @override
  Future<void> createDefaultWorkspace() async {
    createDefaultCalls += 1;
  }

  @override
  Future<void> importWorkspace(String sourcePath) async {}

  @override
  Future<void> renameWorkspace(String workspaceId, String newName) async {}

  @override
  Future<void> reopenWorkspace(String workspaceId) async {}

  @override
  Future<Workspace?> loadCurrentWorkspace() async {
    if (workspaceError != null) {
      throw workspaceError!;
    }
    return null;
  }

  @override
  Future<List<RecentWorkspace>> loadRecentWorkspaces() async {
    return recentWorkspaces;
  }

  @override
  Future<OverviewSnapshot> loadOverviewSnapshot() {
    throw UnimplementedError();
  }

  @override
  Future<List<JournalEntry>> loadJournalEntries() {
    throw UnimplementedError();
  }

  @override
  Future<List<AccountNode>> loadAccountTree() {
    throw UnimplementedError();
  }

  @override
  Future<Map<ReportCategory, List<ReportSummary>>> loadReportSummaries() {
    throw UnimplementedError();
  }

  @override
  Future<List<ValidationIssue>> loadValidationIssues() async {
    return const <ValidationIssue>[];
  }

  @override
  Future<List<WorkspaceTextFile>> loadCurrentWorkspaceFiles() async {
    return const <WorkspaceTextFile>[];
  }
}

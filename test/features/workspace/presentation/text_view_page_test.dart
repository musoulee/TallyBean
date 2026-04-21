import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tally_bean/app/di/app_providers.dart';
import 'package:tally_bean/features/workspace/presentation/pages/text_view_page.dart';

void main() {
  testWidgets('renders single workspace file in read-only view without tabs', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testHost(
        _FakeRepository(
          workspace: _workspace,
          files: const <WorkspaceTextFile>[
            WorkspaceTextFile(
              fileName: 'main.beancount',
              relativePath: 'main.beancount',
              content: 'option "title" "demo"\n',
              sizeBytes: 22,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('文本视图'), findsOneWidget);
    expect(find.text('只读'), findsOneWidget);
    expect(find.text('main.beancount'), findsOneWidget);
    expect(find.text('22 B'), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
    expect(find.textContaining('option "title"'), findsOneWidget);
  });

  testWidgets('renders tabs and supports switching between files', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testHost(
        _FakeRepository(
          workspace: _workspace,
          files: const <WorkspaceTextFile>[
            WorkspaceTextFile(
              fileName: 'main.beancount',
              relativePath: 'main.beancount',
              content: '2026-01-01 open Assets:Cash CNY\n',
              sizeBytes: 32,
            ),
            WorkspaceTextFile(
              fileName: 'notes.bean',
              relativePath: 'notes.bean',
              content: '2026-01-02 note Assets:Cash "memo"\n',
              sizeBytes: 35,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('main.beancount'), findsAtLeastNWidgets(1));
    expect(find.text('notes.bean'), findsOneWidget);
    expect(find.textContaining('open Assets:Cash'), findsOneWidget);

    await tester.tap(find.text('notes.bean'));
    await tester.pumpAndSettle();

    expect(find.textContaining('note Assets:Cash'), findsOneWidget);
  });

  testWidgets('shows empty state when no beancount files are found', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testHost(_FakeRepository(workspace: _workspace, files: const [])),
    );
    await tester.pumpAndSettle();

    expect(find.text('没有可显示的账本文件'), findsOneWidget);
    expect(find.text('当前账本未找到 .bean 或 .beancount 文件。'), findsOneWidget);
  });

  testWidgets('shows async error state when loading files fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testHost(
        _FakeRepository(
          workspace: _workspace,
          files: const <WorkspaceTextFile>[],
          filesError: StateError('file boom'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('文本加载失败'), findsOneWidget);
    expect(find.textContaining('file boom'), findsOneWidget);
  });
}

Widget _testHost(BeancountRepository repository) {
  return ProviderScope(
    overrides: [beancountRepositoryProvider.overrideWithValue(repository)],
    child: const MaterialApp(home: TextViewPage()),
  );
}

final _workspace = Workspace(
  id: 'w-1',
  name: 'Household',
  rootPath: '/workspace/household',
  lastImportedAt: DateTime(2026, 4, 18, 9, 0),
  loadedFileCount: 2,
  status: WorkspaceStatus.ready,
  openAccountCount: 3,
  closedAccountCount: 1,
);

class _FakeRepository implements BeancountRepository {
  _FakeRepository({
    required this.workspace,
    required this.files,
    this.filesError,
  });

  final Workspace? workspace;
  final List<WorkspaceTextFile> files;
  final Object? filesError;

  @override
  Future<void> appendTransaction(CreateTransactionInput input) async {}

  @override
  Future<void> createDefaultWorkspace() async {}

  @override
  Future<void> importWorkspace(String sourcePath) async {}

  @override
  Future<void> renameWorkspace(String workspaceId, String newName) async {}

  @override
  Future<void> deleteWorkspace(String workspaceId) async {}

  @override
  Future<void> reopenWorkspace(String workspaceId) async {}

  @override
  Future<Workspace?> loadCurrentWorkspace() async => workspace;

  @override
  Future<List<WorkspaceTextFile>> loadCurrentWorkspaceFiles() async {
    if (filesError != null) {
      throw filesError!;
    }
    return files;
  }

  @override
  Future<List<RecentWorkspace>> loadRecentWorkspaces() async {
    return const <RecentWorkspace>[];
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
}

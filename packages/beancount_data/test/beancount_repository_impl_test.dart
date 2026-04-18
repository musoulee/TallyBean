import 'package:beancount_bridge/beancount_bridge.dart';
import 'package:beancount_data/beancount_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workspace_io/workspace_io.dart';

void main() {
  test(
    'loadCurrentWorkspace returns null when no active workspace is stored',
    () async {
      final repository = BeancountRepositoryImpl(
        workspaceIo: _FakeWorkspaceIoFacade(),
        bridge: _FakeBridgeFacade(),
      );

      expect(await repository.loadCurrentWorkspace(), isNull);
    },
  );

  test(
    'validation uses the parsed workspace id instead of fixture data',
    () async {
      final bridge = _FakeBridgeFacade();
      final repository = BeancountRepositoryImpl(
        workspaceIo: _FakeWorkspaceIoFacade(
          current: CurrentWorkspaceRecord(
            id: 'recent-id',
            name: 'Household',
            path: '/app/workspaces/household',
            entryFilePath: '/app/workspaces/household/main.beancount',
            lastImportedAt: DateTime(2026, 4, 15, 10, 0),
          ),
        ),
        bridge: bridge,
      );

      final workspace = await repository.loadCurrentWorkspace();
      final issues = await repository.loadValidationIssues();

      expect(workspace, isNotNull);
      expect(workspace?.id, 'parsed-ledger');
      expect(issues, hasLength(1));
      expect(bridge.validatedWorkspaceIds, ['parsed-ledger']);
    },
  );

  test(
    'loadCurrentWorkspaceFiles returns entry file first and remaining files sorted by relative path',
    () async {
      final repository = BeancountRepositoryImpl(
        workspaceIo: _FakeWorkspaceIoFacade(
          current: CurrentWorkspaceRecord(
            id: 'recent-id',
            name: 'Household',
            path: '/app/workspaces/household',
            entryFilePath: '/app/workspaces/household/main.beancount',
            lastImportedAt: DateTime(2026, 4, 15, 10, 0),
          ),
          workspaceFiles: const <WorkspaceIoFileRecord>[
            WorkspaceIoFileRecord(
              filePath: '/app/workspaces/household/z/txn.bean',
              relativePath: 'z/txn.bean',
              content: 'txn',
              sizeBytes: 3,
            ),
            WorkspaceIoFileRecord(
              filePath: '/app/workspaces/household/main.beancount',
              relativePath: 'main.beancount',
              content: 'main',
              sizeBytes: 4,
            ),
            WorkspaceIoFileRecord(
              filePath: '/app/workspaces/household/a/assets.beancount',
              relativePath: 'a/assets.beancount',
              content: 'assets',
              sizeBytes: 6,
            ),
          ],
        ),
        bridge: _FakeBridgeFacade(),
      );

      final files = await repository.loadCurrentWorkspaceFiles();

      expect(files.map((item) => item.relativePath), <String>[
        'main.beancount',
        'a/assets.beancount',
        'z/txn.bean',
      ]);
      expect(files.first.fileName, 'main.beancount');
      expect(files.first.sizeBytes, 4);
      expect(files.first.content, 'main');
    },
  );

  test(
    'loadCurrentWorkspaceFiles still pins entry file first when file records use backslash separators',
    () async {
      final repository = BeancountRepositoryImpl(
        workspaceIo: _FakeWorkspaceIoFacade(
          current: CurrentWorkspaceRecord(
            id: 'recent-id',
            name: 'Household',
            path: '/app/workspaces/household',
            entryFilePath: '/app/workspaces/household/journal/main.beancount',
            lastImportedAt: DateTime(2026, 4, 15, 10, 0),
          ),
          workspaceFiles: const <WorkspaceIoFileRecord>[
            WorkspaceIoFileRecord(
              filePath: '/app/workspaces/household/journal/main.beancount',
              relativePath: r'journal\main.beancount',
              content: 'main',
              sizeBytes: 4,
            ),
            WorkspaceIoFileRecord(
              filePath: '/app/workspaces/household/a/assets.beancount',
              relativePath: 'a/assets.beancount',
              content: 'assets',
              sizeBytes: 6,
            ),
          ],
        ),
        bridge: _FakeBridgeFacade(),
      );

      final files = await repository.loadCurrentWorkspaceFiles();

      expect(files.first.relativePath, r'journal\main.beancount');
      expect(files.first.fileName, 'main.beancount');
    },
  );
}

class _FakeWorkspaceIoFacade implements WorkspaceIoFacade {
  _FakeWorkspaceIoFacade({
    this.current,
    this.workspaceFiles = const <WorkspaceIoFileRecord>[],
  });

  final CurrentWorkspaceRecord? current;
  final List<WorkspaceIoFileRecord> workspaceFiles;

  @override
  Future<ImportedWorkspaceSummary> createDefaultWorkspace() {
    throw UnimplementedError();
  }

  @override
  Future<void> exportWorkspace(
    String workspaceId,
    String destinationPath,
  ) async {}

  @override
  Future<ImportedWorkspaceSummary> importWorkspace(String sourcePath) {
    throw UnimplementedError();
  }

  @override
  Future<String> loadFileContent(String filePath) {
    throw UnimplementedError();
  }

  @override
  Future<CurrentWorkspaceRecord?> loadCurrentWorkspace() async => current;

  @override
  Future<List<RecentWorkspaceRecord>> loadRecentWorkspaces() async => const [];

  @override
  Future<List<WorkspaceIoFileRecord>> loadWorkspaceFiles(
    String workspaceRootPath,
  ) async {
    return workspaceFiles;
  }

  @override
  Future<void> renameWorkspace(String workspaceId, String newName) async {}

  @override
  Future<void> setCurrentWorkspace(String workspaceId) async {}
}

class _FakeBridgeFacade implements BeancountBridgeFacade {
  final List<String> validatedWorkspaceIds = <String>[];

  @override
  Future<List<BridgeReportResultDto>> buildReports(String workspaceId) async {
    return const <BridgeReportResultDto>[];
  }

  @override
  Future<BridgeParseResultDto> parseWorkspace(
    String rootPath,
    String entryFilePath,
  ) async {
    return BridgeParseResultDto(
      workspaceId: 'parsed-ledger',
      workspaceName: 'Household',
      loadedFileCount: 2,
      journalEntries: const <BridgeJournalEntryDto>[],
      accountNodes: const <BridgeAccountNodeDto>[],
      overview: const BridgeOverviewDto(
        netWorth: '¥ 0',
        totalAssets: '¥ 0',
        totalLiabilities: '¥ 0',
        changeDescription: '较上月 + ¥ 0',
        weekTrend: BridgeTrendSummaryDto(
          chartLabel: '本周收支趋势',
          income: 0,
          expense: 0,
          balance: 0,
        ),
        monthTrend: BridgeTrendSummaryDto(
          chartLabel: '本月收支趋势',
          income: 0,
          expense: 0,
          balance: 0,
        ),
      ),
      validationIssues: const <BridgeValidationIssueDto>[],
      openAccountCount: 2,
      closedAccountCount: 0,
    );
  }

  @override
  Future<List<BridgeValidationIssueDto>> validateWorkspace(
    String workspaceId,
  ) async {
    validatedWorkspaceIds.add(workspaceId);
    return const <BridgeValidationIssueDto>[
      BridgeValidationIssueDto(
        message: 'blocking issue',
        location: 'main.beancount:1',
        blocking: true,
      ),
    ];
  }
}

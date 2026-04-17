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
}

class _FakeWorkspaceIoFacade implements WorkspaceIoFacade {
  _FakeWorkspaceIoFacade({this.current});

  final CurrentWorkspaceRecord? current;

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
  Future<CurrentWorkspaceRecord?> loadCurrentWorkspace() async => current;

  @override
  Future<List<RecentWorkspaceRecord>> loadRecentWorkspaces() async => const [];

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

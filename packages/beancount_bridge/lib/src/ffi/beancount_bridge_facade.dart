import '../dtos/bridge_dtos.dart';
import '../ledger/bridge_workspace_projector.dart';
import '../rust/rust_ledger_runtime.dart';

abstract interface class BeancountBridgeFacade {
  Future<BridgeParseResultDto> parseWorkspace(
    String rootPath,
    String entryFilePath,
  );
  Future<List<BridgeValidationIssueDto>> validateWorkspace(String workspaceId);
  Future<List<BridgeReportResultDto>> buildReports(String workspaceId);
}

class StubBeancountBridgeFacade implements BeancountBridgeFacade {
  const StubBeancountBridgeFacade();

  @override
  Future<List<BridgeReportResultDto>> buildReports(String workspaceId) async {
    return const <BridgeReportResultDto>[];
  }

  @override
  Future<BridgeParseResultDto> parseWorkspace(
    String rootPath,
    String entryFilePath,
  ) async {
    return const BridgeParseResultDto(
      workspaceId: 'household',
      workspaceName: 'Household Ledger',
      loadedFileCount: 0,
      journalEntries: <BridgeJournalEntryDto>[],
      accountNodes: <BridgeAccountNodeDto>[],
      overview: BridgeOverviewDto(
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
      validationIssues: <BridgeValidationIssueDto>[],
      openAccountCount: 0,
      closedAccountCount: 0,
    );
  }

  @override
  Future<List<BridgeValidationIssueDto>> validateWorkspace(
    String workspaceId,
  ) async {
    return const <BridgeValidationIssueDto>[];
  }
}

class RustBeancountBridgeFacade implements BeancountBridgeFacade {
  RustBeancountBridgeFacade({
    RustLedgerRuntime runtime = const DefaultRustLedgerRuntime(),
    BridgeWorkspaceProjector projector = const BridgeWorkspaceProjector(),
  }) : _runtime = runtime,
       _projector = projector;

  final RustLedgerRuntime _runtime;
  final BridgeWorkspaceProjector _projector;
  final Map<String, BridgeParseResultDto> _parsedWorkspaces =
      <String, BridgeParseResultDto>{};

  @override
  Future<List<BridgeReportResultDto>> buildReports(String workspaceId) async {
    return _parsedWorkspaces[workspaceId]?.reportResults ??
        const <BridgeReportResultDto>[];
  }

  @override
  Future<BridgeParseResultDto> parseWorkspace(
    String rootPath,
    String entryFilePath,
  ) async {
    final snapshot = await _runtime.parseWorkspace(
      rootPath: rootPath,
      entryFilePath: entryFilePath,
    );
    final result = _projector.project(snapshot);
    _parsedWorkspaces[result.workspaceId] = result;
    return result;
  }

  @override
  Future<List<BridgeValidationIssueDto>> validateWorkspace(
    String workspaceId,
  ) async {
    return _parsedWorkspaces[workspaceId]?.validationIssues ??
        const <BridgeValidationIssueDto>[];
  }
}

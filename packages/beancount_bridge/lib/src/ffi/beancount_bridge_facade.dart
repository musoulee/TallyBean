import '../dtos/bridge_dtos.dart';
import '../native/api.dart' as frb_api;
import '../native/rust_ledger_runtime.dart';

abstract interface class BeancountBridgeFacade {
  Future<BridgeWorkspaceSessionDto> openWorkspace(
    String rootPath,
    String entryFilePath,
  );
  Future<void> closeWorkspace(int handle);
  Future<BridgeRefreshResultDto> refreshWorkspace(int handle);
  Future<BridgeWorkspaceSummaryDto> getWorkspaceSummary(int handle);
  Future<List<BridgeValidationIssueDto>> listDiagnostics(int handle);
  Future<List<BridgeJournalEntryDto>> getJournalEntries(int handle);
  Future<BridgeAccountTreeDto> getAccountTree(int handle);
  Future<BridgeOverviewDto> getOverview(int handle);
  Future<List<BridgeReportResultDto>> getReportSnapshot(int handle);
  Future<List<BridgeDocumentSummaryDto>> listDocuments(int handle);
  Future<BridgeDocumentDto> getDocument(int handle, String documentId);

  Future<BridgeParseResultDto> parseWorkspace(
    String rootPath,
    String entryFilePath,
  );
  Future<List<BridgeValidationIssueDto>> validateWorkspace(String workspaceId);
  Future<List<BridgeReportResultDto>> buildReports(String workspaceId);
}

class StubBeancountBridgeFacade implements BeancountBridgeFacade {
  const StubBeancountBridgeFacade();

  static const _summary = BridgeWorkspaceSummaryDto(
    workspaceId: 'household',
    workspaceName: 'Household Ledger',
    loadedFileCount: 0,
    openAccountCount: 0,
    closedAccountCount: 0,
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
  );

  @override
  Future<List<BridgeReportResultDto>> buildReports(String workspaceId) async =>
      const <BridgeReportResultDto>[];

  @override
  Future<void> closeWorkspace(int handle) async {}

  @override
  Future<BridgeAccountTreeDto> getAccountTree(int handle) async =>
      const BridgeAccountTreeDto(nodes: <BridgeAccountNodeDto>[]);

  @override
  Future<BridgeDocumentDto> getDocument(int handle, String documentId) async =>
      const BridgeDocumentDto(
        documentId: 'main.beancount',
        fileName: 'main.beancount',
        relativePath: 'main.beancount',
        content: '',
        sizeBytes: 0,
        isEntry: true,
      );

  @override
  Future<List<BridgeJournalEntryDto>> getJournalEntries(int handle) async =>
      const <BridgeJournalEntryDto>[];

  @override
  Future<BridgeOverviewDto> getOverview(int handle) async => const BridgeOverviewDto(
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
  );

  @override
  Future<List<BridgeValidationIssueDto>> listDiagnostics(int handle) async =>
      const <BridgeValidationIssueDto>[];

  @override
  Future<List<BridgeDocumentSummaryDto>> listDocuments(int handle) async =>
      const <BridgeDocumentSummaryDto>[];

  @override
  Future<BridgeWorkspaceSessionDto> openWorkspace(
    String rootPath,
    String entryFilePath,
  ) async {
    return const BridgeWorkspaceSessionDto(
      handle: 1,
      summary: _summary,
      diagnostics: <BridgeValidationIssueDto>[],
    );
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
  Future<BridgeRefreshResultDto> refreshWorkspace(int handle) async =>
      const BridgeRefreshResultDto(summary: _summary, diagnosticsCount: 0);

  @override
  Future<List<BridgeReportResultDto>> getReportSnapshot(int handle) async =>
      const <BridgeReportResultDto>[];

  @override
  Future<BridgeWorkspaceSummaryDto> getWorkspaceSummary(int handle) async =>
      _summary;

  @override
  Future<List<BridgeValidationIssueDto>> validateWorkspace(
    String workspaceId,
  ) async => const <BridgeValidationIssueDto>[];
}

class RustBeancountBridgeFacade implements BeancountBridgeFacade {
  RustBeancountBridgeFacade({
    RustLedgerRuntime runtime = const DefaultRustLedgerRuntime(),
  }) : _runtime = runtime;

  final RustLedgerRuntime _runtime;
  final Map<String, _CachedWorkspaceSession> _sessionsByKey =
      <String, _CachedWorkspaceSession>{};
  final Map<String, int> _workspaceHandlesById = <String, int>{};

  @override
  Future<List<BridgeReportResultDto>> buildReports(String workspaceId) async {
    final handle = _workspaceHandlesById[workspaceId];
    if (handle == null) {
      return const <BridgeReportResultDto>[];
    }
    return getReportSnapshot(handle);
  }

  @override
  Future<void> closeWorkspace(int handle) async {
    await _runtime.closeWorkspace(handle: handle);
    _sessionsByKey.removeWhere((_, session) => session.handle == handle);
    _workspaceHandlesById.removeWhere((_, value) => value == handle);
  }

  @override
  Future<BridgeAccountTreeDto> getAccountTree(int handle) async {
    final raw = await _runtime.getAccountTree(
      handle: handle,
      query: const frb_api.RustAccountTreeQuery(includeClosedAccounts: true),
    );
    return BridgeAccountTreeDto(
      nodes: raw.nodes.map(_mapAccountNode).toList(growable: false),
    );
  }

  @override
  Future<BridgeDocumentDto> getDocument(int handle, String documentId) async {
    final raw = await _runtime.getDocument(handle: handle, documentId: documentId);
    return BridgeDocumentDto(
      documentId: raw.documentId,
      fileName: raw.fileName,
      relativePath: raw.relativePath,
      content: raw.content,
      sizeBytes: raw.sizeBytes,
      isEntry: raw.isEntry,
    );
  }

  @override
  Future<List<BridgeJournalEntryDto>> getJournalEntries(int handle) async {
    final raw = await _runtime.getJournalPage(
      handle: handle,
      query: const frb_api.RustJournalQuery(pageSize: 5000, offset: 0),
    );
    return raw.entries.map(_mapJournalEntry).toList(growable: false);
  }

  @override
  Future<BridgeOverviewDto> getOverview(int handle) async {
    final summary = await getWorkspaceSummary(handle);
    return BridgeOverviewDto(
      netWorth: summary.netWorth,
      totalAssets: summary.totalAssets,
      totalLiabilities: summary.totalLiabilities,
      changeDescription: summary.changeDescription,
      weekTrend: summary.weekTrend,
      monthTrend: summary.monthTrend,
    );
  }

  @override
  Future<List<BridgeValidationIssueDto>> listDiagnostics(int handle) async {
    final raw = await _runtime.listDiagnostics(
      handle: handle,
      query: const frb_api.RustDiagnosticQuery(
        includeBlocking: true,
        includeNonBlocking: true,
      ),
    );
    return raw.map(_mapDiagnostic).toList(growable: false);
  }

  @override
  Future<List<BridgeDocumentSummaryDto>> listDocuments(int handle) async {
    final raw = await _runtime.listDocuments(handle: handle);
    return raw
        .map(
          (document) => BridgeDocumentSummaryDto(
            documentId: document.documentId,
            fileName: document.fileName,
            relativePath: document.relativePath,
            sizeBytes: document.sizeBytes,
            isEntry: document.isEntry,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<BridgeWorkspaceSessionDto> openWorkspace(
    String rootPath,
    String entryFilePath,
  ) async {
    final key = _sessionKey(rootPath, entryFilePath);
    final cached = _sessionsByKey[key];
    if (cached != null) {
      return cached.toDto();
    }

    final handle = await _runtime.openWorkspace(
      rootPath: rootPath,
      entryFilePath: entryFilePath,
    );
    final summary = await getWorkspaceSummary(handle);
    final diagnostics = await listDiagnostics(handle);
    final session = _CachedWorkspaceSession(
      handle: handle,
      rootPath: rootPath,
      entryFilePath: entryFilePath,
      summary: summary,
      diagnostics: diagnostics,
    );
    _sessionsByKey[key] = session;
    _workspaceHandlesById[summary.workspaceId] = handle;
    return session.toDto();
  }

  @override
  Future<BridgeParseResultDto> parseWorkspace(
    String rootPath,
    String entryFilePath,
  ) async {
    final session = await openWorkspace(rootPath, entryFilePath);
    final journalEntries = await getJournalEntries(session.handle);
    final accountTree = await getAccountTree(session.handle);
    final reports = await getReportSnapshot(session.handle);

    return BridgeParseResultDto(
      workspaceId: session.summary.workspaceId,
      workspaceName: session.summary.workspaceName,
      loadedFileCount: session.summary.loadedFileCount,
      journalEntries: journalEntries,
      accountNodes: accountTree.nodes,
      overview: BridgeOverviewDto(
        netWorth: session.summary.netWorth,
        totalAssets: session.summary.totalAssets,
        totalLiabilities: session.summary.totalLiabilities,
        changeDescription: session.summary.changeDescription,
        weekTrend: session.summary.weekTrend,
        monthTrend: session.summary.monthTrend,
      ),
      validationIssues: session.diagnostics,
      openAccountCount: session.summary.openAccountCount,
      closedAccountCount: session.summary.closedAccountCount,
      reportResults: reports,
    );
  }

  @override
  Future<BridgeRefreshResultDto> refreshWorkspace(int handle) async {
    final raw = await _runtime.refreshWorkspace(handle: handle);
    final summary = _mapWorkspaceSummary(raw.summary);
    final diagnostics = await listDiagnostics(handle);
    _updateCachedSession(
      handle,
      (session) => session.copyWith(summary: summary, diagnostics: diagnostics),
    );
    return BridgeRefreshResultDto(
      summary: summary,
      diagnosticsCount: raw.diagnosticsCount,
    );
  }

  @override
  Future<List<BridgeReportResultDto>> getReportSnapshot(int handle) async {
    final raw = await _runtime.getReportSnapshot(
      handle: handle,
      query: const frb_api.RustReportQuery(),
    );
    return raw.results
        .map(
          (result) => BridgeReportResultDto(key: result.key, lines: result.lines),
        )
        .toList(growable: false);
  }

  @override
  Future<BridgeWorkspaceSummaryDto> getWorkspaceSummary(int handle) async {
    final raw = await _runtime.getWorkspaceSummary(handle: handle);
    final summary = _mapWorkspaceSummary(raw);
    _updateCachedSession(
      handle,
      (session) => session.copyWith(summary: summary),
    );
    _workspaceHandlesById[summary.workspaceId] = handle;
    return summary;
  }

  @override
  Future<List<BridgeValidationIssueDto>> validateWorkspace(
    String workspaceId,
  ) async {
    final handle = _workspaceHandlesById[workspaceId];
    if (handle == null) {
      return const <BridgeValidationIssueDto>[];
    }
    return listDiagnostics(handle);
  }

  BridgeWorkspaceSummaryDto _mapWorkspaceSummary(frb_api.RustWorkspaceSummary raw) {
    return BridgeWorkspaceSummaryDto(
      workspaceId: raw.workspaceId,
      workspaceName: raw.workspaceName,
      loadedFileCount: raw.loadedFileCount,
      openAccountCount: raw.openAccountCount,
      closedAccountCount: raw.closedAccountCount,
      netWorth: raw.netWorth,
      totalAssets: raw.totalAssets,
      totalLiabilities: raw.totalLiabilities,
      changeDescription: raw.changeDescription,
      weekTrend: BridgeTrendSummaryDto(
        chartLabel: raw.weekTrend.chartLabel,
        income: raw.weekTrend.income,
        expense: raw.weekTrend.expense,
        balance: raw.weekTrend.balance,
      ),
      monthTrend: BridgeTrendSummaryDto(
        chartLabel: raw.monthTrend.chartLabel,
        income: raw.monthTrend.income,
        expense: raw.monthTrend.expense,
        balance: raw.monthTrend.balance,
      ),
    );
  }

  BridgeValidationIssueDto _mapDiagnostic(frb_api.RustLedgerDiagnostic raw) {
    return BridgeValidationIssueDto(
      message: raw.message,
      location: raw.location,
      blocking: raw.blocking,
    );
  }

  BridgeAccountNodeDto _mapAccountNode(frb_api.RustAccountNode raw) {
    return BridgeAccountNodeDto(
      name: raw.name,
      subtitle: raw.subtitle,
      balance: raw.balance,
      isClosed: raw.isClosed,
      children: raw.children.map(_mapAccountNode).toList(growable: false),
    );
  }

  BridgeJournalEntryDto _mapJournalEntry(frb_api.RustJournalEntry raw) {
    return BridgeJournalEntryDto(
      date: DateTime.parse(raw.dateIso8601),
      type: switch (raw.entryType) {
        frb_api.RustJournalEntryType.transaction =>
          BridgeJournalEntryType.transaction,
        frb_api.RustJournalEntryType.open => BridgeJournalEntryType.open,
        frb_api.RustJournalEntryType.close => BridgeJournalEntryType.close,
        frb_api.RustJournalEntryType.price => BridgeJournalEntryType.price,
        frb_api.RustJournalEntryType.balance => BridgeJournalEntryType.balance,
      },
      title: raw.title,
      primaryAccount: raw.primaryAccount,
      secondaryAccount: raw.secondaryAccount,
      detail: raw.detail,
      amount: raw.amount == null
          ? null
          : BridgeEntryAmountDto(
              value: raw.amount!.value,
              commodity: raw.amount!.commodity,
              fractionDigits: raw.amount!.fractionDigits,
            ),
      status: raw.status,
      transactionFlag: switch (raw.transactionFlag) {
        frb_api.RustTransactionFlag.pending => BridgeTransactionFlag.pending,
        frb_api.RustTransactionFlag.cleared => BridgeTransactionFlag.cleared,
        null => null,
      },
    );
  }

  void _updateCachedSession(
    int handle,
    _CachedWorkspaceSession Function(_CachedWorkspaceSession session) update,
  ) {
    final key = _sessionsByKey.entries
        .where((entry) => entry.value.handle == handle)
        .map((entry) => entry.key)
        .cast<String?>()
        .firstWhere((_) => true, orElse: () => null);
    if (key == null) {
      return;
    }
    _sessionsByKey[key] = update(_sessionsByKey[key]!);
  }

  String _sessionKey(String rootPath, String entryFilePath) {
    return '$rootPath::$entryFilePath';
  }
}

class _CachedWorkspaceSession {
  const _CachedWorkspaceSession({
    required this.handle,
    required this.rootPath,
    required this.entryFilePath,
    required this.summary,
    required this.diagnostics,
  });

  final int handle;
  final String rootPath;
  final String entryFilePath;
  final BridgeWorkspaceSummaryDto summary;
  final List<BridgeValidationIssueDto> diagnostics;

  BridgeWorkspaceSessionDto toDto() {
    return BridgeWorkspaceSessionDto(
      handle: handle,
      summary: summary,
      diagnostics: diagnostics,
    );
  }

  _CachedWorkspaceSession copyWith({
    BridgeWorkspaceSummaryDto? summary,
    List<BridgeValidationIssueDto>? diagnostics,
  }) {
    return _CachedWorkspaceSession(
      handle: handle,
      rootPath: rootPath,
      entryFilePath: entryFilePath,
      summary: summary ?? this.summary,
      diagnostics: diagnostics ?? this.diagnostics,
    );
  }
}

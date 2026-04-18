import 'package:beancount_bridge/beancount_bridge.dart';
import 'package:beancount_domain/beancount_domain.dart';
import 'package:workspace_io/workspace_io.dart';

import '../mappers/recent_workspace_mapper.dart';

class BeancountRepositoryImpl implements BeancountRepository {
  BeancountRepositoryImpl({
    required WorkspaceIoFacade workspaceIo,
    required BeancountBridgeFacade bridge,
  }) : _workspaceIo = workspaceIo,
       _bridge = bridge;

  final WorkspaceIoFacade _workspaceIo;
  final BeancountBridgeFacade _bridge;
  CurrentWorkspaceRecord? _cachedWorkspace;
  BridgeWorkspaceSessionDto? _cachedSession;

  @override
  Future<List<AccountNode>> loadAccountTree() async {
    final session = await _requireReadyWorkspace();
    final tree = await _bridge.getAccountTree(session.handle);
    return tree.nodes.map(_mapAccountNode).toList();
  }

  @override
  Future<Workspace?> loadCurrentWorkspace() async {
    final current = await _workspaceIo.loadCurrentWorkspace();
    if (current == null) {
      await _disposeSession();
      _clearCache();
      return null;
    }

    final session = await _ensureWorkspaceSession(current);
    return Workspace(
      id: session.summary.workspaceId,
      name: current.name,
      rootPath: current.path,
      lastImportedAt: current.lastImportedAt,
      loadedFileCount: session.summary.loadedFileCount,
      status: _hasBlockingIssues(session)
          ? WorkspaceStatus.issuesFirst
          : WorkspaceStatus.ready,
      openAccountCount: session.summary.openAccountCount,
      closedAccountCount: session.summary.closedAccountCount,
    );
  }

  @override
  Future<List<JournalEntry>> loadJournalEntries() async {
    final session = await _requireReadyWorkspace();
    final entries = await _bridge.getJournalEntries(session.handle);
    return entries.map(_mapJournalEntry).toList();
  }

  @override
  Future<OverviewSnapshot> loadOverviewSnapshot() async {
    final session = await _requireReadyWorkspace();
    final overview = await _bridge.getOverview(session.handle);
    final transactions = (await _bridge.getJournalEntries(session.handle))
        .where((entry) => entry.type == BridgeJournalEntryType.transaction)
        .map(_mapJournalEntry)
        .toList();

    return OverviewSnapshot(
      netWorth: overview.netWorth,
      totalAssets: overview.totalAssets,
      totalLiabilities: overview.totalLiabilities,
      changeDescription: overview.changeDescription,
      updatedAt: DateTime.now(),
      weekTrend: TrendSnapshot(
        chartLabel: overview.weekTrend.chartLabel,
        income: overview.weekTrend.income,
        expense: overview.weekTrend.expense,
        balance: overview.weekTrend.balance,
      ),
      monthTrend: TrendSnapshot(
        chartLabel: overview.monthTrend.chartLabel,
        income: overview.monthTrend.income,
        expense: overview.monthTrend.expense,
        balance: overview.monthTrend.balance,
      ),
      recentTransactions: transactions,
    );
  }

  @override
  Future<List<RecentWorkspace>> loadRecentWorkspaces() async {
    final recent = await _workspaceIo.loadRecentWorkspaces();
    return recent.map(mapRecentWorkspaceRecord).toList();
  }

  @override
  Future<Map<ReportCategory, List<ReportSummary>>> loadReportSummaries() async {
    final session = await _requireReadyWorkspace();
    final reports = await _bridge.getReportSnapshot(session.handle);
    final categories = <ReportCategory, List<ReportSummary>>{};
    for (final report in reports) {
      final category = switch (report.key) {
        'income_expense' => ReportCategory.incomeExpense,
        'assets' => ReportCategory.assets,
        'account_contribution' => ReportCategory.accountContribution,
        'time_comparison' => ReportCategory.timeComparison,
        _ => null,
      };
      if (category == null) {
        continue;
      }
      categories.update(
        category,
        (items) => [
          ...items,
          ReportSummary(title: report.key, lines: report.lines),
        ],
        ifAbsent: () => <ReportSummary>[
          ReportSummary(title: report.key, lines: report.lines),
        ],
      );
    }
    return categories;
  }

  @override
  Future<List<ValidationIssue>> loadValidationIssues() async {
    final current = await _workspaceIo.loadCurrentWorkspace();
    if (current == null) {
      await _disposeSession();
      _clearCache();
      return const <ValidationIssue>[];
    }

    final session = await _ensureWorkspaceSession(current, forceDiagnosticsRefresh: true);
    return session.diagnostics
        .map(
          (issue) => ValidationIssue(
            message: issue.message,
            location: issue.location,
            blocking: issue.blocking,
          ),
        )
        .toList();
  }

  @override
  Future<void> importWorkspace(String sourcePath) async {
    await _workspaceIo.importWorkspace(sourcePath);
    await _disposeSession();
    _clearCache();
  }

  @override
  Future<void> createDefaultWorkspace() async {
    await _workspaceIo.createDefaultWorkspace();
    await _disposeSession();
    _clearCache();
  }

  @override
  Future<void> renameWorkspace(String workspaceId, String newName) async {
    await _workspaceIo.renameWorkspace(workspaceId, newName);
    await _disposeSession();
    _clearCache();
  }

  @override
  Future<void> reopenWorkspace(String workspaceId) async {
    await _workspaceIo.setCurrentWorkspace(workspaceId);
    await _disposeSession();
    _clearCache();
  }

  @override
  Future<List<WorkspaceTextFile>> loadCurrentWorkspaceFiles() async {
    final current = await _workspaceIo.loadCurrentWorkspace();
    if (current == null) {
      throw StateError('当前没有激活的账本');
    }

    final session = await _ensureWorkspaceSession(current);
    final documents = await _bridge.listDocuments(session.handle);
    final files = <WorkspaceTextFile>[];
    for (final document in documents) {
      final loaded = await _bridge.getDocument(session.handle, document.documentId);
      files.add(
        WorkspaceTextFile(
          fileName: loaded.fileName,
          relativePath: loaded.relativePath,
          content: loaded.content,
          sizeBytes: loaded.sizeBytes,
        ),
      );
    }

    final entryRelativePath = _normalizePath(
      _relativeEntryPath(
        currentPath: current.path,
        entryFilePath: current.entryFilePath,
      ),
    );
    files.sort((left, right) {
      final leftPath = _normalizePath(left.relativePath);
      final rightPath = _normalizePath(right.relativePath);
      final leftIsEntry = leftPath == entryRelativePath;
      final rightIsEntry = rightPath == entryRelativePath;
      if (leftIsEntry && !rightIsEntry) {
        return -1;
      }
      if (!leftIsEntry && rightIsEntry) {
        return 1;
      }
      return leftPath.compareTo(rightPath);
    });

    return files;
  }

  Future<BridgeWorkspaceSessionDto> _requireReadyWorkspace() async {
    final current = await loadCurrentWorkspace();
    if (current == null) {
      throw StateError('当前没有激活工作区');
    }

    if (current.status == WorkspaceStatus.issuesFirst) {
      throw StateError('当前账本存在阻塞性问题');
    }

    final record = _cachedWorkspace ?? await _workspaceIo.loadCurrentWorkspace();
    if (record == null) {
      throw StateError('当前没有激活工作区');
    }

    return _ensureWorkspaceSession(record);
  }

  Future<BridgeWorkspaceSessionDto> _ensureWorkspaceSession(
    CurrentWorkspaceRecord current, {
    bool forceDiagnosticsRefresh = false,
  }) async {
    if (_cachedSession != null &&
        _cachedWorkspace?.path == current.path &&
        _cachedWorkspace?.entryFilePath == current.entryFilePath) {
      if (!forceDiagnosticsRefresh) {
        return _cachedSession!;
      }
      final refreshedDiagnostics = await _bridge.listDiagnostics(_cachedSession!.handle);
      _cachedSession = BridgeWorkspaceSessionDto(
        handle: _cachedSession!.handle,
        summary: _cachedSession!.summary,
        diagnostics: refreshedDiagnostics,
      );
      return _cachedSession!;
    }

    await _disposeSession();
    final session = await _bridge.openWorkspace(current.path, current.entryFilePath);
    _cachedWorkspace = current;
    _cachedSession = session;
    return session;
  }

  Future<void> _disposeSession() async {
    final handle = _cachedSession?.handle;
    if (handle == null) {
      return;
    }
    await _bridge.closeWorkspace(handle);
  }

  bool _hasBlockingIssues(BridgeWorkspaceSessionDto session) {
    return session.diagnostics.any((issue) => issue.blocking);
  }

  AccountNode _mapAccountNode(BridgeAccountNodeDto dto) {
    return AccountNode(
      name: dto.name,
      subtitle: dto.subtitle,
      balance: dto.balance,
      children: dto.children.map(_mapAccountNode).toList(),
    );
  }

  JournalEntry _mapJournalEntry(BridgeJournalEntryDto dto) {
    return JournalEntry(
      date: dto.date,
      type: switch (dto.type) {
        BridgeJournalEntryType.transaction => JournalEntryType.transaction,
        BridgeJournalEntryType.open => JournalEntryType.open,
        BridgeJournalEntryType.close => JournalEntryType.close,
        BridgeJournalEntryType.price => JournalEntryType.price,
        BridgeJournalEntryType.balance => JournalEntryType.balance,
      },
      title: dto.title,
      primaryAccount: dto.primaryAccount,
      secondaryAccount: dto.secondaryAccount,
      detail: dto.detail,
      amount: dto.amount == null
          ? null
          : EntryAmount(
              value: dto.amount!.value,
              commodity: dto.amount!.commodity,
              fractionDigits: dto.amount!.fractionDigits,
              displayStyle:
                  dto.amount!.displayStyle ==
                      BridgeEntryAmountDisplayStyle.prefix
                  ? EntryAmountDisplayStyle.prefix
                  : EntryAmountDisplayStyle.suffix,
            ),
      status: dto.status,
      transactionFlag: switch (dto.transactionFlag) {
        BridgeTransactionFlag.pending => TransactionFlag.pending,
        BridgeTransactionFlag.cleared => TransactionFlag.cleared,
        null => null,
      },
    );
  }

  void _clearCache() {
    _cachedWorkspace = null;
    _cachedSession = null;
  }

  String _relativeEntryPath({
    required String currentPath,
    required String entryFilePath,
  }) {
    final normalizedRoot = currentPath.replaceAll('\\', '/');
    final normalizedEntry = entryFilePath.replaceAll('\\', '/');
    if (normalizedEntry.startsWith('$normalizedRoot/')) {
      return normalizedEntry.substring(normalizedRoot.length + 1);
    }
    return normalizedEntry;
  }

  String _normalizePath(String sourcePath) {
    return sourcePath.replaceAll('\\', '/');
  }
}

import 'package:beancount_bridge/beancount_bridge.dart';
import 'package:beancount_domain/beancount_domain.dart';
import 'package:workspace_io/workspace_io.dart';

import '../mappers/recent_workspace_mapper.dart';

class BeancountRepositoryImpl implements BeancountRepository {
  static const String _unsupportedSummaryQuoteMessage = '摘要暂不支持双引号';

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
  Future<void> appendTransaction(CreateTransactionInput input) async {
    _validateCreateTransactionInput(input);

    final current = await _workspaceIo.loadCurrentWorkspace();
    if (current == null) {
      throw StateError('当前没有激活工作区');
    }

    final session = await _requireReadyWorkspace();
    final originalContent = await _workspaceIo.loadFileContent(
      current.entryFilePath,
    );
    final updatedContent = _appendTransactionEntry(
      originalContent: originalContent,
      input: input,
    );

    await _workspaceIo.writeFileContent(current.entryFilePath, updatedContent);
    final diagnostics = await _refreshAfterWriteOrRollback(
      entryFilePath: current.entryFilePath,
      originalContent: originalContent,
      handle: session.handle,
      action: () => _refreshCachedSession(session.handle),
    );
    final blockingDiagnostics = diagnostics
        .where((issue) => issue.blocking)
        .toList(growable: false);
    if (blockingDiagnostics.isEmpty) {
      return;
    }

    await _restoreOriginalEntryFile(
      entryFilePath: current.entryFilePath,
      originalContent: originalContent,
      handle: session.handle,
    );
    throw StateError(blockingDiagnostics.first.message);
  }

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
    final resolvedWorkspaceName = await _resolveWorkspaceName(
      current,
      session.summary.workspaceName,
    );
    return Workspace(
      id: session.summary.workspaceId,
      name: resolvedWorkspaceName,
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
    final current = await _workspaceIo.loadCurrentWorkspace();
    if (current == null) {
      await _disposeSession();
      _clearCache();
      return const <ReportCategory, List<ReportSummary>>{};
    }

    final session = await _ensureWorkspaceSession(
      current,
      forceDiagnosticsRefresh: true,
    );
    if (_hasBlockingIssues(session)) {
      return const <ReportCategory, List<ReportSummary>>{};
    }
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

    final session = await _ensureWorkspaceSession(
      current,
      forceDiagnosticsRefresh: true,
    );
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
    final imported = await _workspaceIo.importWorkspace(sourcePath);
    await _disposeSession();
    _clearCache();
    await _trySyncWorkspaceNameFromRustSummary(
      workspaceId: imported.workspaceId,
      currentName: imported.name,
      rootPath: imported.path,
      entryFilePath: imported.entryFilePath,
    );
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
  Future<void> deleteWorkspace(String workspaceId) async {
    await _workspaceIo.deleteWorkspace(workspaceId);
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

    final fileRecords = [
      ...await _workspaceIo.loadWorkspaceFiles(current.path),
    ];

    final entryRelativePath = _normalizePath(
      _relativeEntryPath(
        currentPath: current.path,
        entryFilePath: current.entryFilePath,
      ),
    );
    fileRecords.sort((left, right) {
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

    return fileRecords
        .map(
          (record) => WorkspaceTextFile(
            fileName: _fileName(record.relativePath),
            relativePath: record.relativePath,
            content: record.content,
            sizeBytes: record.sizeBytes,
          ),
        )
        .toList(growable: false);
  }

  Future<BridgeWorkspaceSessionDto> _requireReadyWorkspace() async {
    final current = await loadCurrentWorkspace();
    if (current == null) {
      throw StateError('当前没有激活工作区');
    }

    if (current.status == WorkspaceStatus.issuesFirst) {
      throw StateError('当前账本存在阻塞性问题');
    }

    final record =
        _cachedWorkspace ?? await _workspaceIo.loadCurrentWorkspace();
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
      final refreshedDiagnostics = await _bridge.listDiagnostics(
        _cachedSession!.handle,
      );
      _cachedSession = BridgeWorkspaceSessionDto(
        handle: _cachedSession!.handle,
        summary: _cachedSession!.summary,
        diagnostics: refreshedDiagnostics,
      );
      return _cachedSession!;
    }

    await _disposeSession();
    final session = await _bridge.openWorkspace(
      current.path,
      current.entryFilePath,
    );
    _cachedWorkspace = current;
    _cachedSession = session;
    return session;
  }

  Future<String> _resolveWorkspaceName(
    CurrentWorkspaceRecord current,
    String workspaceNameFromSummary,
  ) async {
    final summaryWorkspaceName = workspaceNameFromSummary.trim();
    final resolvedWorkspaceName = summaryWorkspaceName.isEmpty
        ? current.name
        : summaryWorkspaceName;
    if (summaryWorkspaceName.isNotEmpty &&
        summaryWorkspaceName != current.name) {
      await _workspaceIo.renameWorkspace(current.id, summaryWorkspaceName);
      _cachedWorkspace = CurrentWorkspaceRecord(
        id: current.id,
        name: summaryWorkspaceName,
        path: current.path,
        entryFilePath: current.entryFilePath,
        lastImportedAt: current.lastImportedAt,
      );
    }
    return resolvedWorkspaceName;
  }

  Future<void> _trySyncWorkspaceNameFromRustSummary({
    required String workspaceId,
    required String currentName,
    required String rootPath,
    required String entryFilePath,
  }) async {
    BridgeWorkspaceSessionDto? session;
    try {
      session = await _bridge.openWorkspace(rootPath, entryFilePath);
      final summaryWorkspaceName = session.summary.workspaceName.trim();
      if (summaryWorkspaceName.isNotEmpty &&
          summaryWorkspaceName != currentName) {
        await _workspaceIo.renameWorkspace(workspaceId, summaryWorkspaceName);
      }
    } catch (_) {
      return;
    } finally {
      if (session != null) {
        await _bridge.closeWorkspace(session.handle);
      }
    }
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

  Future<List<BridgeValidationIssueDto>> _refreshCachedSession(
    int handle,
  ) async {
    final refreshed = await _bridge.refreshWorkspace(handle);
    final diagnostics = await _bridge.listDiagnostics(handle);
    _cachedSession = BridgeWorkspaceSessionDto(
      handle: handle,
      summary: refreshed.summary,
      diagnostics: diagnostics,
    );
    return diagnostics;
  }

  Future<T> _refreshAfterWriteOrRollback<T>({
    required String entryFilePath,
    required String originalContent,
    required int handle,
    required Future<T> Function() action,
  }) async {
    try {
      return await action();
    } catch (_) {
      await _restoreOriginalEntryFile(
        entryFilePath: entryFilePath,
        originalContent: originalContent,
        handle: handle,
      );
      rethrow;
    }
  }

  Future<void> _restoreOriginalEntryFile({
    required String entryFilePath,
    required String originalContent,
    required int handle,
  }) async {
    await _workspaceIo.writeFileContent(entryFilePath, originalContent);
    try {
      await _refreshCachedSession(handle);
    } catch (_) {
      try {
        await _bridge.closeWorkspace(handle);
      } catch (_) {}
      _clearCache();
      // Keep the rollback best-effort even if bridge refresh is unavailable.
    }
  }

  AccountNode _mapAccountNode(BridgeAccountNodeDto dto) {
    return AccountNode(
      name: dto.name,
      subtitle: dto.subtitle,
      balance: dto.balance,
      isClosed: dto.isClosed,
      isPostable: dto.isPostable,
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

  String _appendTransactionEntry({
    required String originalContent,
    required CreateTransactionInput input,
  }) {
    final trimmedContent = originalContent.trimRight();
    final transaction = _serializeTransaction(input);
    if (trimmedContent.isEmpty) {
      return transaction;
    }
    return '$trimmedContent\n\n$transaction';
  }

  String _serializeTransaction(CreateTransactionInput input) {
    return '${_formatDate(input.date)} * "${input.summary}"\n'
        '  ${input.primaryAccount}  ${input.amount} ${input.commodity}\n'
        '  ${input.counterAccount}\n';
  }

  void _validateCreateTransactionInput(CreateTransactionInput input) {
    if (input.summary.contains('"')) {
      throw StateError(_unsupportedSummaryQuoteMessage);
    }
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
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

  String _fileName(String relativePath) {
    final normalizedPath = _normalizePath(relativePath);
    final parts = normalizedPath.split('/');
    return parts.isEmpty ? relativePath : parts.last;
  }

  String _normalizePath(String sourcePath) {
    return sourcePath.replaceAll('\\', '/');
  }
}

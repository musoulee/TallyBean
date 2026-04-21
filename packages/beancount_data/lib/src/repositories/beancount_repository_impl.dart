import 'package:beancount_bridge/beancount_bridge.dart';
import 'package:beancount_domain/beancount_domain.dart';
import 'package:ledger_io/ledger_io.dart';

import '../mappers/recent_ledger_mapper.dart';

class BeancountRepositoryImpl implements BeancountRepository {
  static const String _unsupportedSummaryQuoteMessage = '摘要暂不支持双引号';

  BeancountRepositoryImpl({
    required LedgerIoFacade ledgerIo,
    required BeancountBridgeFacade bridge,
  }) : _ledgerIo = ledgerIo,
       _bridge = bridge;

  final LedgerIoFacade _ledgerIo;
  final BeancountBridgeFacade _bridge;
  CurrentLedgerRecord? _cachedLedger;
  BridgeLedgerSessionDto? _cachedSession;

  @override
  Future<void> appendTransaction(CreateTransactionInput input) async {
    _validateCreateTransactionInput(input);

    final current = await _ledgerIo.loadCurrentLedger();
    if (current == null) {
      throw StateError('当前没有激活账本');
    }

    final session = await _requireReadyLedger();
    final originalContent = await _ledgerIo.loadFileContent(
      current.entryFilePath,
    );
    final updatedContent = _appendTransactionEntry(
      originalContent: originalContent,
      input: input,
    );

    await _ledgerIo.writeFileContent(current.entryFilePath, updatedContent);
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
    final session = await _requireReadyLedger();
    final tree = await _bridge.getAccountTree(session.handle);
    return tree.nodes.map(_mapAccountNode).toList();
  }

  @override
  Future<Ledger?> loadCurrentLedger() async {
    final current = await _ledgerIo.loadCurrentLedger();
    if (current == null) {
      await _disposeSession();
      _clearCache();
      return null;
    }

    final session = await _ensureLedgerSession(current);
    final resolvedLedgerName = await _resolveLedgerName(
      current,
      session.summary.ledgerName,
    );
    return Ledger(
      id: session.summary.ledgerId,
      name: resolvedLedgerName,
      rootPath: current.path,
      lastImportedAt: current.lastImportedAt,
      loadedFileCount: session.summary.loadedFileCount,
      status: _hasBlockingIssues(session)
          ? LedgerStatus.issuesFirst
          : LedgerStatus.ready,
      openAccountCount: session.summary.openAccountCount,
      closedAccountCount: session.summary.closedAccountCount,
    );
  }

  @override
  Future<List<JournalEntry>> loadJournalEntries() async {
    final session = await _requireReadyLedger();
    final entries = await _bridge.getJournalEntries(session.handle);
    return entries.map(_mapJournalEntry).toList();
  }

  @override
  Future<OverviewSnapshot> loadOverviewSnapshot() async {
    final session = await _requireReadyLedger();
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
  Future<List<RecentLedger>> loadRecentLedgers() async {
    final recent = await _ledgerIo.loadRecentLedgers();
    return recent.map(mapRecentLedgerRecord).toList();
  }

  @override
  Future<Map<ReportCategory, List<ReportSummary>>> loadReportSummaries() async {
    final current = await _ledgerIo.loadCurrentLedger();
    if (current == null) {
      await _disposeSession();
      _clearCache();
      return const <ReportCategory, List<ReportSummary>>{};
    }

    final session = await _ensureLedgerSession(
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
    final current = await _ledgerIo.loadCurrentLedger();
    if (current == null) {
      await _disposeSession();
      _clearCache();
      return const <ValidationIssue>[];
    }

    final session = await _ensureLedgerSession(
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
  Future<void> importLedger(String sourcePath) async {
    final imported = await _ledgerIo.importLedger(sourcePath);
    await _disposeSession();
    _clearCache();
    await _trySyncLedgerNameFromRustSummary(
      ledgerId: imported.ledgerId,
      currentName: imported.name,
      rootPath: imported.path,
      entryFilePath: imported.entryFilePath,
    );
  }

  @override
  Future<void> createDefaultLedger() async {
    await _ledgerIo.createDefaultLedger();
    await _disposeSession();
    _clearCache();
  }

  @override
  Future<void> renameLedger(String ledgerId, String newName) async {
    await _ledgerIo.renameLedger(ledgerId, newName);
    await _disposeSession();
    _clearCache();
  }

  @override
  Future<void> deleteLedger(String ledgerId) async {
    await _ledgerIo.deleteLedger(ledgerId);
    await _disposeSession();
    _clearCache();
  }

  @override
  Future<void> reopenLedger(String ledgerId) async {
    await _ledgerIo.setCurrentLedger(ledgerId);
    await _disposeSession();
    _clearCache();
  }

  @override
  Future<List<LedgerTextFile>> loadCurrentLedgerFiles() async {
    final current = await _ledgerIo.loadCurrentLedger();
    if (current == null) {
      throw StateError('当前没有激活的账本');
    }

    final fileRecords = [...await _ledgerIo.loadLedgerFiles(current.path)];

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
          (record) => LedgerTextFile(
            fileName: _fileName(record.relativePath),
            relativePath: record.relativePath,
            content: record.content,
            sizeBytes: record.sizeBytes,
          ),
        )
        .toList(growable: false);
  }

  Future<BridgeLedgerSessionDto> _requireReadyLedger() async {
    final current = await loadCurrentLedger();
    if (current == null) {
      throw StateError('当前没有激活账本');
    }

    if (current.status == LedgerStatus.issuesFirst) {
      throw StateError('当前账本存在阻塞性问题');
    }

    final record = _cachedLedger ?? await _ledgerIo.loadCurrentLedger();
    if (record == null) {
      throw StateError('当前没有激活账本');
    }

    return _ensureLedgerSession(record);
  }

  Future<BridgeLedgerSessionDto> _ensureLedgerSession(
    CurrentLedgerRecord current, {
    bool forceDiagnosticsRefresh = false,
  }) async {
    if (_cachedSession != null &&
        _cachedLedger?.path == current.path &&
        _cachedLedger?.entryFilePath == current.entryFilePath) {
      if (!forceDiagnosticsRefresh) {
        return _cachedSession!;
      }
      final refreshedDiagnostics = await _bridge.listDiagnostics(
        _cachedSession!.handle,
      );
      _cachedSession = BridgeLedgerSessionDto(
        handle: _cachedSession!.handle,
        summary: _cachedSession!.summary,
        diagnostics: refreshedDiagnostics,
      );
      return _cachedSession!;
    }

    await _disposeSession();
    final session = await _bridge.openLedger(
      current.path,
      current.entryFilePath,
    );
    _cachedLedger = current;
    _cachedSession = session;
    return session;
  }

  Future<String> _resolveLedgerName(
    CurrentLedgerRecord current,
    String ledgerNameFromSummary,
  ) async {
    final summaryLedgerName = ledgerNameFromSummary.trim();
    final resolvedLedgerName = summaryLedgerName.isEmpty
        ? current.name
        : summaryLedgerName;
    if (summaryLedgerName.isNotEmpty && summaryLedgerName != current.name) {
      await _ledgerIo.renameLedger(current.id, summaryLedgerName);
      _cachedLedger = CurrentLedgerRecord(
        id: current.id,
        name: summaryLedgerName,
        path: current.path,
        entryFilePath: current.entryFilePath,
        lastImportedAt: current.lastImportedAt,
      );
    }
    return resolvedLedgerName;
  }

  Future<void> _trySyncLedgerNameFromRustSummary({
    required String ledgerId,
    required String currentName,
    required String rootPath,
    required String entryFilePath,
  }) async {
    BridgeLedgerSessionDto? session;
    try {
      session = await _bridge.openLedger(rootPath, entryFilePath);
      final summaryLedgerName = session.summary.ledgerName.trim();
      if (summaryLedgerName.isNotEmpty && summaryLedgerName != currentName) {
        await _ledgerIo.renameLedger(ledgerId, summaryLedgerName);
      }
    } catch (_) {
      return;
    } finally {
      if (session != null) {
        await _bridge.closeLedger(session.handle);
      }
    }
  }

  Future<void> _disposeSession() async {
    final handle = _cachedSession?.handle;
    if (handle == null) {
      return;
    }
    await _bridge.closeLedger(handle);
  }

  bool _hasBlockingIssues(BridgeLedgerSessionDto session) {
    return session.diagnostics.any((issue) => issue.blocking);
  }

  Future<List<BridgeValidationIssueDto>> _refreshCachedSession(
    int handle,
  ) async {
    final refreshed = await _bridge.refreshLedger(handle);
    final diagnostics = await _bridge.listDiagnostics(handle);
    _cachedSession = BridgeLedgerSessionDto(
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
    await _ledgerIo.writeFileContent(entryFilePath, originalContent);
    try {
      await _refreshCachedSession(handle);
    } catch (_) {
      try {
        await _bridge.closeLedger(handle);
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
    _cachedLedger = null;
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

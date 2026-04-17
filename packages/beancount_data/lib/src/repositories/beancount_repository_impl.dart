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
  BridgeParseResultDto? _cachedParseResult;

  @override
  Future<List<AccountNode>> loadAccountTree() async {
    final parsed = await _requireReadyWorkspace();
    return parsed.accountNodes.map(_mapAccountNode).toList();
  }

  @override
  Future<Workspace?> loadCurrentWorkspace() async {
    final current = await _workspaceIo.loadCurrentWorkspace();
    if (current == null) {
      _clearCache();
      return null;
    }

    final parsed = await _ensureParsedWorkspace(current);
    return Workspace(
      id: parsed.workspaceId,
      name: current.name,
      rootPath: current.path,
      lastImportedAt: current.lastImportedAt,
      loadedFileCount: parsed.loadedFileCount,
      status: _hasBlockingIssues(parsed)
          ? WorkspaceStatus.issuesFirst
          : WorkspaceStatus.ready,
      openAccountCount: parsed.openAccountCount,
      closedAccountCount: parsed.closedAccountCount,
    );
  }

  @override
  Future<List<JournalEntry>> loadJournalEntries() async {
    final parsed = await _requireReadyWorkspace();
    return parsed.journalEntries.map(_mapJournalEntry).toList();
  }

  @override
  Future<OverviewSnapshot> loadOverviewSnapshot() async {
    final parsed = await _requireReadyWorkspace();
    final transactions = parsed.journalEntries
        .where((entry) => entry.type == BridgeJournalEntryType.transaction)
        .map(_mapJournalEntry)
        .toList();

    return OverviewSnapshot(
      netWorth: parsed.overview.netWorth,
      totalAssets: parsed.overview.totalAssets,
      totalLiabilities: parsed.overview.totalLiabilities,
      changeDescription: parsed.overview.changeDescription,
      updatedAt: DateTime.now(),
      weekTrend: TrendSnapshot(
        chartLabel: parsed.overview.weekTrend.chartLabel,
        income: parsed.overview.weekTrend.income,
        expense: parsed.overview.weekTrend.expense,
        balance: parsed.overview.weekTrend.balance,
      ),
      monthTrend: TrendSnapshot(
        chartLabel: parsed.overview.monthTrend.chartLabel,
        income: parsed.overview.monthTrend.income,
        expense: parsed.overview.monthTrend.expense,
        balance: parsed.overview.monthTrend.balance,
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
    final current = await loadCurrentWorkspace();
    if (current == null || current.status == WorkspaceStatus.issuesFirst) {
      return const <ReportCategory, List<ReportSummary>>{};
    }

    final reports = await _bridge.buildReports(current.id);
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
      _clearCache();
      return const <ValidationIssue>[];
    }

    final parsed = await _ensureParsedWorkspace(current);
    final issues = await _bridge.validateWorkspace(parsed.workspaceId);
    return issues
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
    _clearCache();
  }

  @override
  Future<void> reopenWorkspace(String workspaceId) async {
    await _workspaceIo.setCurrentWorkspace(workspaceId);
    _clearCache();
  }

  Future<BridgeParseResultDto> _requireReadyWorkspace() async {
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

    return _ensureParsedWorkspace(record);
  }

  Future<BridgeParseResultDto> _ensureParsedWorkspace(
    CurrentWorkspaceRecord current,
  ) async {
    if (_cachedParseResult != null &&
        _cachedWorkspace?.path == current.path &&
        _cachedWorkspace?.entryFilePath == current.entryFilePath) {
      return _cachedParseResult!;
    }

    final parseResult = await _bridge.parseWorkspace(
      current.path,
      current.entryFilePath,
    );
    _cachedWorkspace = current;
    _cachedParseResult = parseResult;
    return parseResult;
  }

  bool _hasBlockingIssues(BridgeParseResultDto parsed) {
    return parsed.validationIssues.any((issue) => issue.blocking);
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
    _cachedParseResult = null;
  }
}

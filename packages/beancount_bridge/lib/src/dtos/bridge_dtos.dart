enum BridgeJournalEntryType { transaction, open, close, price, balance }

enum BridgeTransactionFlag { cleared, pending }

enum BridgeEntryAmountDisplayStyle { prefix, suffix }

class BridgeEntryAmountDto {
  const BridgeEntryAmountDto({
    required this.value,
    required this.commodity,
    required this.fractionDigits,
    this.displayStyle = BridgeEntryAmountDisplayStyle.prefix,
  });

  final num value;
  final String commodity;
  final int fractionDigits;
  final BridgeEntryAmountDisplayStyle displayStyle;
}

class BridgeJournalEntryDto {
  const BridgeJournalEntryDto({
    required this.date,
    required this.type,
    required this.title,
    required this.primaryAccount,
    this.secondaryAccount,
    this.detail,
    this.amount,
    this.status,
    this.transactionFlag,
  });

  final DateTime date;
  final BridgeJournalEntryType type;
  final String title;
  final String primaryAccount;
  final String? secondaryAccount;
  final String? detail;
  final BridgeEntryAmountDto? amount;
  final String? status;
  final BridgeTransactionFlag? transactionFlag;
}

class BridgeAccountNodeDto {
  const BridgeAccountNodeDto({
    required this.name,
    required this.subtitle,
    required this.balance,
    this.isClosed = false,
    this.isPostable = true,
    this.children = const <BridgeAccountNodeDto>[],
  });

  final String name;
  final String subtitle;
  final String balance;
  final bool isClosed;
  final bool isPostable;
  final List<BridgeAccountNodeDto> children;
}

class BridgeTrendSummaryDto {
  const BridgeTrendSummaryDto({
    required this.chartLabel,
    required this.income,
    required this.expense,
    required this.balance,
  });

  final String chartLabel;
  final num income;
  final num expense;
  final num balance;
}

class BridgeOverviewDto {
  const BridgeOverviewDto({
    required this.netWorth,
    required this.totalAssets,
    required this.totalLiabilities,
    required this.changeDescription,
    required this.weekTrend,
    required this.monthTrend,
  });

  final String netWorth;
  final String totalAssets;
  final String totalLiabilities;
  final String changeDescription;
  final BridgeTrendSummaryDto weekTrend;
  final BridgeTrendSummaryDto monthTrend;
}

class BridgeWorkspaceSummaryDto {
  const BridgeWorkspaceSummaryDto({
    required this.workspaceId,
    required this.workspaceName,
    required this.loadedFileCount,
    required this.openAccountCount,
    required this.closedAccountCount,
    required this.netWorth,
    required this.totalAssets,
    required this.totalLiabilities,
    required this.changeDescription,
    required this.weekTrend,
    required this.monthTrend,
  });

  final String workspaceId;
  final String workspaceName;
  final int loadedFileCount;
  final int openAccountCount;
  final int closedAccountCount;
  final String netWorth;
  final String totalAssets;
  final String totalLiabilities;
  final String changeDescription;
  final BridgeTrendSummaryDto weekTrend;
  final BridgeTrendSummaryDto monthTrend;
}

class BridgeWorkspaceSessionDto {
  const BridgeWorkspaceSessionDto({
    required this.handle,
    required this.summary,
    required this.diagnostics,
  });

  final int handle;
  final BridgeWorkspaceSummaryDto summary;
  final List<BridgeValidationIssueDto> diagnostics;
}

class BridgeRefreshResultDto {
  const BridgeRefreshResultDto({
    required this.summary,
    required this.diagnosticsCount,
  });

  final BridgeWorkspaceSummaryDto summary;
  final int diagnosticsCount;
}

class BridgeAccountTreeDto {
  const BridgeAccountTreeDto({required this.nodes});

  final List<BridgeAccountNodeDto> nodes;
}

class BridgeParseResultDto {
  const BridgeParseResultDto({
    required this.workspaceId,
    required this.workspaceName,
    required this.loadedFileCount,
    required this.journalEntries,
    required this.accountNodes,
    required this.overview,
    required this.validationIssues,
    required this.openAccountCount,
    required this.closedAccountCount,
    this.reportResults = const <BridgeReportResultDto>[],
  });

  final String workspaceId;
  final String workspaceName;
  final int loadedFileCount;
  final List<BridgeJournalEntryDto> journalEntries;
  final List<BridgeAccountNodeDto> accountNodes;
  final BridgeOverviewDto overview;
  final List<BridgeValidationIssueDto> validationIssues;
  final int openAccountCount;
  final int closedAccountCount;
  final List<BridgeReportResultDto> reportResults;
}

class BridgeValidationIssueDto {
  const BridgeValidationIssueDto({
    required this.message,
    required this.location,
    required this.blocking,
  });

  final String message;
  final String location;
  final bool blocking;
}

class BridgeDocumentSummaryDto {
  const BridgeDocumentSummaryDto({
    required this.documentId,
    required this.fileName,
    required this.relativePath,
    required this.sizeBytes,
    required this.isEntry,
  });

  final String documentId;
  final String fileName;
  final String relativePath;
  final int sizeBytes;
  final bool isEntry;
}

class BridgeDocumentDto {
  const BridgeDocumentDto({
    required this.documentId,
    required this.fileName,
    required this.relativePath,
    required this.content,
    required this.sizeBytes,
    required this.isEntry,
  });

  final String documentId;
  final String fileName;
  final String relativePath;
  final String content;
  final int sizeBytes;
  final bool isEntry;
}

class BridgeReportResultDto {
  const BridgeReportResultDto({required this.key, required this.lines});

  final String key;
  final List<String> lines;
}

import '../dtos/bridge_dtos.dart';
import '../rust/api.dart';

class BridgeWorkspaceProjector {
  const BridgeWorkspaceProjector();

  BridgeParseResultDto project(RustLedgerSnapshot snapshot) {
    final tracker = _LedgerProjectionTracker();
    for (final directive in snapshot.directives) {
      tracker.record(directive);
    }

    final sortedDirectives = [...snapshot.directives]
      ..sort((left, right) {
        final dateCompare = DateTime.parse(
          right.dateIso8601,
        ).compareTo(DateTime.parse(left.dateIso8601));
        if (dateCompare != 0) {
          return dateCompare;
        }
        return right.sourceLocation.compareTo(left.sourceLocation);
      });

    final bridgeEntries = sortedDirectives
        .map((directive) => _mapJournalEntry(directive))
        .toList();
    final referenceDate = bridgeEntries.isNotEmpty
        ? bridgeEntries.first.date
        : DateTime.now();
    final overview = _buildOverview(
      referenceDate,
      snapshot.directives,
      tracker,
    );

    return BridgeParseResultDto(
      workspaceId: snapshot.workspaceId,
      workspaceName: snapshot.workspaceName,
      loadedFileCount: snapshot.loadedFileCount,
      journalEntries: bridgeEntries,
      accountNodes: _buildAccountTree(tracker),
      overview: overview,
      validationIssues: snapshot.diagnostics
          .map(
            (issue) => BridgeValidationIssueDto(
              message: issue.message,
              location: issue.location,
              blocking: issue.blocking,
            ),
          )
          .toList(),
      openAccountCount: tracker.openAccountCount,
      closedAccountCount: tracker.closedAccountCount,
      reportResults: _buildReports(overview),
    );
  }

  BridgeJournalEntryDto _mapJournalEntry(RustLedgerDirective directive) {
    final date = DateTime.parse(directive.dateIso8601);
    switch (directive.kind) {
      case RustLedgerDirectiveKind.transaction:
        final ordered = _orderedPostingsForDisplay(directive.postings);
        final primary = ordered.first.account;
        final secondary = ordered
            .map((posting) => posting.account)
            .where((account) => account != primary)
            .cast<String?>()
            .firstWhere((_) => true, orElse: () => null);
        final displayAmount = _selectDisplayAmount(ordered);
        return BridgeJournalEntryDto(
          date: date,
          type: BridgeJournalEntryType.transaction,
          title: directive.title ?? '',
          primaryAccount: primary,
          secondaryAccount: secondary,
          amount: displayAmount == null
              ? null
              : BridgeEntryAmountDto(
                  value: displayAmount.value,
                  commodity: displayAmount.commodity,
                  fractionDigits: displayAmount.fractionDigits,
                ),
          transactionFlag: switch (directive.transactionFlag) {
            RustTransactionFlag.pending => BridgeTransactionFlag.pending,
            RustTransactionFlag.cleared => BridgeTransactionFlag.cleared,
            null => null,
          },
        );
      case RustLedgerDirectiveKind.open:
        return BridgeJournalEntryDto(
          date: date,
          type: BridgeJournalEntryType.open,
          title: directive.account!,
          primaryAccount: directive.account!,
          detail: '账户已启用',
          status: '已启用',
        );
      case RustLedgerDirectiveKind.close:
        return BridgeJournalEntryDto(
          date: date,
          type: BridgeJournalEntryType.close,
          title: directive.account!,
          primaryAccount: directive.account!,
          detail: '账户已关闭',
          status: '已关闭',
        );
      case RustLedgerDirectiveKind.price:
        return BridgeJournalEntryDto(
          date: date,
          type: BridgeJournalEntryType.price,
          title: '${directive.baseCommodity}/${directive.quoteCommodity}',
          primaryAccount:
              '${directive.baseCommodity}/${directive.quoteCommodity}',
          amount: directive.amount == null
              ? null
              : BridgeEntryAmountDto(
                  value: directive.amount!.value,
                  commodity: directive.amount!.commodity,
                  fractionDigits: directive.amount!.fractionDigits,
                  displayStyle: BridgeEntryAmountDisplayStyle.suffix,
                ),
          detail: '价格记录',
        );
      case RustLedgerDirectiveKind.balance:
        return BridgeJournalEntryDto(
          date: date,
          type: BridgeJournalEntryType.balance,
          title: directive.account!,
          primaryAccount: directive.account!,
          amount: directive.amount == null
              ? null
              : BridgeEntryAmountDto(
                  value: directive.amount!.value,
                  commodity: directive.amount!.commodity,
                  fractionDigits: directive.amount!.fractionDigits,
                ),
          detail: '余额断言',
        );
    }
  }

  List<BridgeAccountNodeDto> _buildAccountTree(
    _LedgerProjectionTracker tracker,
  ) {
    final rootNodes = <String, _AccountTreeBuilder>{};

    for (final account in tracker.accountLifecycles.keys) {
      final segments = account.split(':');
      _AccountTreeBuilder? current;
      var currentPath = '';
      for (final segment in segments) {
        currentPath = currentPath.isEmpty ? segment : '$currentPath:$segment';
        final next = current == null
            ? rootNodes.putIfAbsent(
                segment,
                () => _AccountTreeBuilder(name: segment, fullPath: currentPath),
              )
            : current.children.putIfAbsent(
                segment,
                () => _AccountTreeBuilder(name: segment, fullPath: currentPath),
              );
        current = next;
      }
    }

    final nodes = rootNodes.values.toList()
      ..sort((left, right) => left.name.compareTo(right.name));
    return nodes.map((node) => _buildAccountNode(node, tracker)).toList();
  }

  BridgeAccountNodeDto _buildAccountNode(
    _AccountTreeBuilder builder,
    _LedgerProjectionTracker tracker,
  ) {
    final lifecycle = tracker.accountLifecycles[builder.fullPath];
    final childNodes =
        builder.children.values
            .map((child) => _buildAccountNode(child, tracker))
            .toList()
          ..sort((left, right) => left.name.compareTo(right.name));
    final subtitle = childNodes.isEmpty
        ? (lifecycle?.closeDate != null ? '已关闭' : '活跃')
        : '${childNodes.length} 个子账户';

    return BridgeAccountNodeDto(
      name: builder.name,
      subtitle: subtitle,
      balance: _formatBalanceSummary(
        _accountAggregate(builder.fullPath, tracker.accountBalances),
      ),
      isClosed: lifecycle?.closeDate != null,
      children: childNodes,
    );
  }

  BridgeOverviewDto _buildOverview(
    DateTime referenceDate,
    List<RustLedgerDirective> directives,
    _LedgerProjectionTracker tracker,
  ) {
    final assetBuckets = _aggregateAccountType(
      'Assets',
      tracker.accountBalances,
    );
    final liabilityBuckets = _aggregateAccountType(
      'Liabilities',
      tracker.accountBalances,
    );
    final netWorthBuckets = <String, num>{};
    assetBuckets.forEach((commodity, value) {
      netWorthBuckets[commodity] = (netWorthBuckets[commodity] ?? 0) + value;
    });
    liabilityBuckets.forEach((commodity, value) {
      netWorthBuckets[commodity] =
          (netWorthBuckets[commodity] ?? 0) - value.abs();
    });

    final monthTrend = _buildTrendSummary(
      label: '本月收支趋势',
      from: DateTime(referenceDate.year, referenceDate.month, 1),
      to: DateTime(referenceDate.year, referenceDate.month + 1, 1),
      directives: directives,
    );
    final weekStart = referenceDate.subtract(
      Duration(days: referenceDate.weekday - DateTime.monday),
    );
    final weekTrend = _buildTrendSummary(
      label: '本周收支趋势',
      from: DateTime(weekStart.year, weekStart.month, weekStart.day),
      to: DateTime(weekStart.year, weekStart.month, weekStart.day + 7),
      directives: directives,
    );
    final previousMonthTrend = _buildTrendSummary(
      label: '上月收支趋势',
      from: DateTime(referenceDate.year, referenceDate.month - 1, 1),
      to: DateTime(referenceDate.year, referenceDate.month, 1),
      directives: directives,
    );
    final changeCommodity = _dominantCommodity(netWorthBuckets);
    final changeDescription = changeCommodity == null
        ? '多币种账本'
        : '较上月 ${_signedAmountText(monthTrend.balance - previousMonthTrend.balance, changeCommodity)}';

    return BridgeOverviewDto(
      netWorth: _formatBalanceSummary(netWorthBuckets),
      totalAssets: _formatBalanceSummary(assetBuckets),
      totalLiabilities: _formatBalanceSummary(liabilityBuckets, absolute: true),
      changeDescription: changeDescription,
      weekTrend: weekTrend,
      monthTrend: monthTrend,
    );
  }

  List<BridgeReportResultDto> _buildReports(BridgeOverviewDto overview) {
    return <BridgeReportResultDto>[
      BridgeReportResultDto(
        key: 'income_expense',
        lines: <String>[
          '本周收入 ${_formatAmount(overview.weekTrend.income, '¥')}',
          '本周支出 ${_formatAmount(overview.weekTrend.expense, '¥')}',
          '本周结余 ${_formatAmount(overview.weekTrend.balance, '¥')}',
        ],
      ),
    ];
  }

  BridgeTrendSummaryDto _buildTrendSummary({
    required String label,
    required DateTime from,
    required DateTime to,
    required List<RustLedgerDirective> directives,
  }) {
    final incomeByCommodity = <String, num>{};
    final expenseByCommodity = <String, num>{};

    for (final directive in directives) {
      if (directive.kind != RustLedgerDirectiveKind.transaction) {
        continue;
      }
      final date = DateTime.parse(directive.dateIso8601);
      if (date.isBefore(from) || !date.isBefore(to)) {
        continue;
      }

      for (final posting in directive.postings) {
        final amount = posting.amount;
        if (amount == null) {
          continue;
        }

        final root = _accountRoot(posting.account);
        if (root == 'Income') {
          incomeByCommodity[amount.commodity] =
              (incomeByCommodity[amount.commodity] ?? 0) + amount.value.abs();
        } else if (root == 'Expenses') {
          expenseByCommodity[amount.commodity] =
              (expenseByCommodity[amount.commodity] ?? 0) + amount.value.abs();
        }
      }
    }

    final commodity =
        _dominantCommodity(
          incomeByCommodity,
          fallbackBuckets: expenseByCommodity,
        ) ??
        '¥';
    final income = incomeByCommodity[commodity] ?? 0;
    final expense = expenseByCommodity[commodity] ?? 0;

    return BridgeTrendSummaryDto(
      chartLabel: label,
      income: income,
      expense: expense,
      balance: income - expense,
    );
  }

  List<RustPosting> _orderedPostingsForDisplay(List<RustPosting> postings) {
    final ordered = [...postings];
    ordered.sort((left, right) {
      final score = _accountDisplayScore(
        left.account,
      ).compareTo(_accountDisplayScore(right.account));
      if (score != 0) {
        return score;
      }
      return left.account.compareTo(right.account);
    });
    return ordered;
  }

  RustAmount? _selectDisplayAmount(List<RustPosting> postings) {
    for (final posting in postings) {
      final amount = posting.amount;
      if (amount == null) {
        continue;
      }

      final normalizedValue = switch (_accountRoot(posting.account)) {
        'Expenses' => -amount.value.abs(),
        'Income' => amount.value.abs(),
        'Liabilities' => -amount.value.abs(),
        _ => amount.value,
      };

      return RustAmount(
        value: normalizedValue,
        commodity: amount.commodity,
        fractionDigits: amount.fractionDigits,
      );
    }

    return null;
  }

  Map<String, num> _aggregateAccountType(
    String rootType,
    Map<String, Map<String, num>> accountBalances,
  ) {
    final totals = <String, num>{};
    accountBalances.forEach((account, balances) {
      if (_accountRoot(account) != rootType) {
        return;
      }
      balances.forEach((commodity, value) {
        totals[commodity] = (totals[commodity] ?? 0) + value;
      });
    });
    return totals;
  }

  Map<String, num> _accountAggregate(
    String prefix,
    Map<String, Map<String, num>> accountBalances,
  ) {
    final totals = <String, num>{};
    accountBalances.forEach((account, balances) {
      if (account == prefix || account.startsWith('$prefix:')) {
        balances.forEach((commodity, value) {
          totals[commodity] = (totals[commodity] ?? 0) + value;
        });
      }
    });
    return totals;
  }

  String _formatBalanceSummary(
    Map<String, num> buckets, {
    bool absolute = false,
  }) {
    if (buckets.isEmpty) {
      return '--';
    }
    if (buckets.length == 1) {
      final commodity = buckets.keys.single;
      final value = absolute
          ? buckets.values.single.abs()
          : buckets.values.single;
      return _formatAmount(value, commodity);
    }
    return '${buckets.length} 币种';
  }

  String _formatAmount(num value, String commodity) {
    final isNegative = value < 0;
    final absolute = value.abs();
    final fractionDigits = absolute % 1 == 0 ? 0 : 2;
    final fixed = absolute.toStringAsFixed(fractionDigits);
    final parts = fixed.split('.');
    final integerPart = _groupThousands(parts.first);
    final numberText = fractionDigits == 0
        ? integerPart
        : '$integerPart.${parts.last}';
    final sign = isNegative ? '- ' : '';
    return '$sign$commodity $numberText';
  }

  String _signedAmountText(num value, String commodity) {
    final amountText = _formatAmount(value.abs(), commodity);
    final sign = value < 0 ? '-' : '+';
    return '$sign $amountText';
  }

  String _groupThousands(String digits) {
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      final remaining = digits.length - index;
      buffer.write(digits[index]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(',');
      }
    }
    return buffer.toString();
  }

  String? _dominantCommodity(
    Map<String, num> primaryBuckets, {
    Map<String, num> fallbackBuckets = const <String, num>{},
  }) {
    final combined = <String, num>{};
    primaryBuckets.forEach((commodity, value) {
      combined[commodity] = (combined[commodity] ?? 0) + value.abs();
    });
    fallbackBuckets.forEach((commodity, value) {
      combined[commodity] = (combined[commodity] ?? 0) + value.abs();
    });
    if (combined.isEmpty) {
      return null;
    }

    final sorted = combined.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    return sorted.first.key;
  }

  String _accountRoot(String account) {
    return account.split(':').first;
  }

  int _accountDisplayScore(String account) {
    return switch (_accountRoot(account)) {
      'Expenses' => 0,
      'Income' => 1,
      'Liabilities' => 2,
      'Assets' => 3,
      'Equity' => 4,
      _ => 5,
    };
  }
}

class _LedgerProjectionTracker {
  final Map<String, _AccountLifecycle> accountLifecycles =
      <String, _AccountLifecycle>{};
  final Map<String, Map<String, num>> accountBalances =
      <String, Map<String, num>>{};

  void record(RustLedgerDirective directive) {
    final date = DateTime.parse(directive.dateIso8601);
    switch (directive.kind) {
      case RustLedgerDirectiveKind.open:
        final lifecycle = accountLifecycles.putIfAbsent(
          directive.account!,
          () => _AccountLifecycle(directive.account!),
        );
        lifecycle.openDate ??= date;
        lifecycle.lastActivityDate = date;
      case RustLedgerDirectiveKind.close:
        final lifecycle = accountLifecycles.putIfAbsent(
          directive.account!,
          () => _AccountLifecycle(directive.account!),
        );
        lifecycle.closeDate = date;
        lifecycle.lastActivityDate = date;
      case RustLedgerDirectiveKind.balance:
        _touchAccount(directive.account!, date);
      case RustLedgerDirectiveKind.transaction:
        for (final posting in directive.postings) {
          _touchAccount(posting.account, date);
          final amount = posting.amount;
          if (amount == null) {
            continue;
          }
          final balances = accountBalances.putIfAbsent(
            posting.account,
            () => <String, num>{},
          );
          balances[amount.commodity] =
              (balances[amount.commodity] ?? 0) + amount.value;
        }
      case RustLedgerDirectiveKind.price:
        break;
    }
  }

  int get openAccountCount =>
      accountLifecycles.values.where((item) => item.openDate != null).length;

  int get closedAccountCount =>
      accountLifecycles.values.where((item) => item.closeDate != null).length;

  void _touchAccount(String account, DateTime date) {
    final lifecycle = accountLifecycles.putIfAbsent(
      account,
      () => _AccountLifecycle(account),
    );
    lifecycle.lastActivityDate = date;
  }
}

class _AccountLifecycle {
  _AccountLifecycle(this.account);

  final String account;
  DateTime? openDate;
  DateTime? closeDate;
  DateTime? lastActivityDate;
}

class _AccountTreeBuilder {
  _AccountTreeBuilder({required this.name, required this.fullPath});

  final String name;
  final String fullPath;
  final Map<String, _AccountTreeBuilder> children =
      <String, _AccountTreeBuilder>{};
}

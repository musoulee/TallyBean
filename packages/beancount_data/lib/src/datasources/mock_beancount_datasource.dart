import 'package:beancount_domain/beancount_domain.dart';

class MockBeancountDatasource {
  const MockBeancountDatasource();

  Ledger ledger() {
    return Ledger(
      id: 'household',
      name: 'Household Ledger',
      rootPath: '/storage/emulated/0/Documents/beancount',
      lastImportedAt: DateTime(2026, 4, 12, 9, 42),
      loadedFileCount: 12,
      status: LedgerStatus.ready,
      openAccountCount: 42,
      closedAccountCount: 8,
      operatingCurrencies: const ['CNY', 'USD'],
    );
  }

  OverviewSnapshot overviewSnapshot() {
    return OverviewSnapshot(
      netWorth: '¥ 128,420',
      totalAssets: '¥ 142,200',
      totalLiabilities: '¥ 13,780',
      changeDescription: '较上月 + ¥ 8,230',
      updatedAt: DateTime(2026, 4, 12, 9, 42),
      weekTrend: const TrendSnapshot(
        chartLabel: '本周收支趋势',
        income: 3280,
        expense: 860,
        balance: 2420,
      ),
      monthTrend: const TrendSnapshot(
        chartLabel: '本月收支趋势',
        income: 20000,
        expense: 5860,
        balance: 14140,
      ),
      recentTransactions: journalEntries()
          .where((entry) => entry.type == JournalEntryType.transaction)
          .toList(),
    );
  }

  List<JournalEntry> journalEntries() {
    return <JournalEntry>[
      JournalEntry(
        date: DateTime(2026, 4, 12),
        type: JournalEntryType.transaction,
        title: 'Market',
        primaryAccount: 'Expenses:Food',
        secondaryAccount: 'Assets:Cash',
        amount: EntryAmount(value: -86, commodity: '¥'),
        transactionFlag: TransactionFlag.cleared,
      ),
      JournalEntry(
        date: DateTime(2026, 4, 12),
        type: JournalEntryType.transaction,
        title: 'Salary',
        primaryAccount: 'Assets:Bank',
        secondaryAccount: 'Income:Salary',
        amount: EntryAmount(value: 20000, commodity: '¥'),
        transactionFlag: TransactionFlag.pending,
      ),
      JournalEntry(
        date: DateTime(2026, 4, 11),
        type: JournalEntryType.price,
        title: 'USD/CNY',
        primaryAccount: 'USD/CNY',
        detail: '收盘参考价',
        amount: EntryAmount(
          value: 7.242,
          commodity: 'CNY',
          fractionDigits: 3,
          displayStyle: EntryAmountDisplayStyle.suffix,
        ),
      ),
      JournalEntry(
        date: DateTime(2026, 4, 11),
        type: JournalEntryType.balance,
        title: 'Assets:Bank:Checking',
        primaryAccount: 'Assets:Bank:Checking',
        detail: '余额断言已匹配',
        amount: EntryAmount(value: 12480, commodity: '¥', fractionDigits: 0),
      ),
      JournalEntry(
        date: DateTime(2026, 4, 11),
        type: JournalEntryType.open,
        title: 'Expenses:Medical',
        primaryAccount: 'Expenses:Medical',
        detail: '新增医疗支出账户',
        status: '已启用',
      ),
      JournalEntry(
        date: DateTime(2026, 4, 10),
        type: JournalEntryType.close,
        title: 'Liabilities:Card:Old',
        primaryAccount: 'Liabilities:Card:Old',
        detail: '旧信用卡账户已关闭',
        status: '已归档',
      ),
    ];
  }

  List<AccountNode> accountTree() {
    return const <AccountNode>[
      AccountNode(
        name: 'Assets',
        subtitle: '活跃资产账户',
        balance: '¥ 128,200',
        children: <AccountNode>[
          AccountNode(name: 'Cash', subtitle: '本周 2 笔交易', balance: '¥ 3,420'),
          AccountNode(
            name: 'Bank',
            subtitle: '2 个子账户',
            balance: '¥ 42,880',
            children: <AccountNode>[
              AccountNode(
                name: 'Checking',
                subtitle: '最后变动 2h 前',
                balance: '¥ 12,480',
              ),
              AccountNode(
                name: 'Brokerage',
                subtitle: '多币种 · 4 holdings',
                balance: '¥ 81,900',
              ),
            ],
          ),
        ],
      ),
      AccountNode(
        name: 'Liabilities',
        subtitle: '负债账户',
        balance: '¥ 13,780',
        children: <AccountNode>[
          AccountNode(
            name: 'CreditCard',
            subtitle: '本期账单',
            balance: '¥ 13,780',
          ),
        ],
      ),
      AccountNode(
        name: 'Equity',
        subtitle: '权益账户',
        balance: '¥ 0',
        children: <AccountNode>[
          AccountNode(
            name: 'Opening-Balances',
            subtitle: '期初余额',
            balance: '¥ 0',
          ),
        ],
      ),
      AccountNode(
        name: 'Income',
        subtitle: '收入账户',
        balance: '¥ 20,120',
        children: <AccountNode>[
          AccountNode(name: 'Salary', subtitle: '工资收入', balance: '¥ 20,000'),
          AccountNode(name: 'Interest', subtitle: '利息收入', balance: '¥ 120'),
        ],
      ),
      AccountNode(
        name: 'Expenses',
        subtitle: '支出账户',
        balance: '¥ 5,860',
        children: <AccountNode>[
          AccountNode(name: 'Food', subtitle: '餐饮', balance: '¥ 1,820'),
          AccountNode(name: 'Rent', subtitle: '房租', balance: '¥ 4,500'),
          AccountNode(name: 'Transport', subtitle: '交通', balance: '¥ 640'),
        ],
      ),
    ];
  }

  Map<ReportCategory, List<ReportSummary>> reportSummaries() {
    return const <ReportCategory, List<ReportSummary>>{
      ReportCategory.incomeExpense: <ReportSummary>[
        ReportSummary(
          title: '月度收支趋势',
          lines: <String>['收入 ¥ 20,000', '支出 ¥ 5,860', '结余 ¥ 14,140'],
        ),
        ReportSummary(
          title: '支出分类排行',
          lines: <String>['Food  ¥ 1,820', 'Rent  ¥ 4,500', 'Transport  ¥ 640'],
        ),
        ReportSummary(
          title: '收入来源排行',
          lines: <String>['Salary  ¥ 20,000', 'Interest  ¥ 120'],
        ),
      ],
      ReportCategory.assets: <ReportSummary>[
        ReportSummary(
          title: '资产类别分布',
          lines: <String>['现金 25%', '投资 64%', '其他 11%'],
        ),
        ReportSummary(
          title: '账户资产占比',
          lines: <String>['Brokerage  ¥ 81,900', 'Checking  ¥ 12,480'],
        ),
        ReportSummary(
          title: '多币种资产摘要',
          lines: <String>['CNY  ¥ 108,420', 'USD  \$2,740', 'BTC  0.16'],
        ),
      ],
      ReportCategory.accountContribution: <ReportSummary>[
        ReportSummary(
          title: '收入贡献账户',
          lines: <String>['Income:Salary', 'Income:Interest'],
        ),
        ReportSummary(
          title: '支出贡献账户',
          lines: <String>[
            'Expenses:Rent',
            'Expenses:Food',
            'Expenses:Transport',
          ],
        ),
        ReportSummary(
          title: '余额变化最大账户',
          lines: <String>[
            'Assets:Brokerage  + ¥ 12,000',
            'Assets:Cash  - ¥ 860',
          ],
        ),
      ],
      ReportCategory.timeComparison: <ReportSummary>[
        ReportSummary(
          title: '本月 vs 上月',
          lines: <String>['收入 +12%', '支出 -4%', '结余 +18%'],
        ),
        ReportSummary(
          title: '本年 vs 去年同期',
          lines: <String>['净资产 +23%', '储蓄率 +6%'],
        ),
        ReportSummary(
          title: '关键变化说明',
          lines: <String>['本月工资到账较早', '房租续约后支出趋稳'],
        ),
      ],
    };
  }
}

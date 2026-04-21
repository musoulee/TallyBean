import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tally_design_system/tally_design_system.dart';

import 'package:tally_bean/app/bootstrap/app_bootstrap.dart';
import 'package:tally_bean/app/di/app_providers.dart';
import 'package:tally_bean/app/bootstrap/app_config.dart';
import 'package:tally_bean/app/session/quick_entry_session.dart';
import 'package:tally_bean/features/journal/presentation/pages/journal_page.dart';
import 'package:tally_bean/features/overview/presentation/pages/overview_page.dart';
import 'package:tally_bean/features/overview/presentation/widgets/trend_summary.dart';
import 'package:tally_bean/features/journal/application/journal_ui_models.dart';
import 'package:tally_bean/shared/formatters/journal_entry_display.dart';
import 'package:tally_bean/shared/widgets/async_error_view.dart';
import 'package:tally_bean/main.dart';

const _demoApp = TallyBeanApp(config: AppConfig(useDemoData: true));

void main() {
  test(
    'maps supported journal filters and entry markers to approved UI semantics',
    () {
      final priceEntry = JournalEntry(
        date: DateTime(2026, 4, 11),
        type: JournalEntryType.price,
        title: 'USD/CNY',
        primaryAccount: 'USD/CNY',
        detail: '收盘参考价',
        amount: const EntryAmount(
          value: 7.242,
          commodity: 'CNY',
          fractionDigits: 3,
          displayStyle: EntryAmountDisplayStyle.suffix,
        ),
      );
      final pendingTransaction = JournalEntry(
        date: DateTime(2026, 4, 12),
        type: JournalEntryType.transaction,
        title: 'Salary',
        primaryAccount: 'Assets:Bank',
        secondaryAccount: 'Income:Salary',
        amount: const EntryAmount(value: 20000, commodity: '¥'),
        transactionFlag: TransactionFlag.pending,
      );

      expect(JournalFilter.values.map((filter) => filter.label), [
        '全部',
        '交易',
        '开户',
        '闭户',
        '价格',
        '断言',
      ]);
      expect(journalEntryMarker(priceEntry), 'R');
      expect(journalEntryColor(priceEntry), const Color(0xFFA06A1C));
      expect(journalEntrySubtitle(priceEntry), '收盘参考价');
      expect(journalEntryTrailing(priceEntry), '7.242 CNY');
      expect(journalEntryMarker(pendingTransaction), '!');
      expect(journalEntryColor(pendingTransaction), const Color(0xFFB7791F));
      expect(
        journalEntrySubtitle(pendingTransaction),
        'Assets:Bank / Income:Salary',
      );
      expect(journalEntryTrailing(pendingTransaction), '+ ¥ 20,000.00');
    },
  );

  testWidgets(
    'shows Android-style app shell with five destinations and a global add action',
    (WidgetTester tester) async {
      await tester.pumpWidget(_demoApp);
      await tester.pumpAndSettle();

      final providerScope = find.byType(ProviderScope);
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      final navigationBar = find.byType(BottomNavigationBar);

      expect(providerScope, findsOneWidget);
      expect(app.debugShowCheckedModeBanner, isFalse);
      expect(app.routerConfig, isNotNull);
      expect(find.byType(AppBar), findsNothing);
      expect(
        find.descendant(of: navigationBar, matching: find.text('首页')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: navigationBar, matching: find.text('明细')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: navigationBar, matching: find.text('账户')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: navigationBar, matching: find.text('统计')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: navigationBar, matching: find.text('设置')),
        findsOneWidget,
      );
      final fab = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );

      expect(fab.tooltip, '记一笔');
      expect(fab.isExtended, isFalse);
      expect(find.text('记一笔'), findsNothing);
      expect(navigationBar, findsOneWidget);
    },
  );

  testWidgets('protects tab pages from the Android status bar cutout', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_demoApp);
    await tester.pumpAndSettle();

    final safeArea = tester.widget<SafeArea>(find.byType(SafeArea).first);

    expect(safeArea.top, isTrue);
    expect(safeArea.bottom, isFalse);
  });

  testWidgets('renders async error view with retry action', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AsyncErrorView(error: Exception('boom'), onRetry: () {}),
      ),
    );

    expect(find.text('加载失败'), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets(
    'renders merged homepage summary card, dual-period trend card, and recent transactions',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      tester.binding.platformDispatcher.textScaleFactorTestValue = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );

      await tester.pumpWidget(_demoApp);
      await tester.pumpAndSettle();

      expect(find.text('净资产'), findsOneWidget);
      expect(find.text('总资产'), findsOneWidget);
      expect(find.text('总负债'), findsOneWidget);
      expect(find.byType(TallyMetricCard), findsNothing);
      expect(find.text('近期收支趋势'), findsNothing);
      expect(find.text('收支趋势'), findsNothing);
      expect(find.textContaining('更新于'), findsNothing);
      expect(find.text('本周'), findsOneWidget);
      expect(find.text('本月'), findsOneWidget);
      expect(find.text('7天'), findsNothing);
      expect(find.text('30天'), findsNothing);
      expect(find.text('收入'), findsOneWidget);
      expect(find.text('支出'), findsOneWidget);
      expect(find.text('结余'), findsOneWidget);
      expect(find.text('¥ 3,280.00'), findsOneWidget);
      expect(find.text('¥ 860.00'), findsOneWidget);
      expect(find.text('¥ 2,420.00'), findsOneWidget);
      expect(find.byKey(const Key('overview-summary-card')), findsOneWidget);
      expect(find.byKey(const Key('overview-trend-card')), findsOneWidget);

      final overviewListView = tester.widget<ListView>(
        find.byType(ListView).first,
      );
      expect(overviewListView.physics, isA<AlwaysScrollableScrollPhysics>());
      expect(
        tester.getSize(find.byKey(const Key('overview-summary-card'))).height,
        lessThan(145),
      );
      expect(
        tester.getSize(find.byKey(const Key('overview-trend-card'))).height,
        lessThan(190),
      );

      final netWorthLabelTopLeft = tester.getTopLeft(find.text('净资产'));
      final totalAssetsLabelTopLeft = tester.getTopLeft(find.text('总资产'));
      final totalLiabilitiesLabelTopLeft = tester.getTopLeft(find.text('总负债'));
      final totalAssetsAmountTopRight = tester.getTopRight(
        find.text('¥ 142,200'),
      );
      final totalLiabilitiesAmountTopRight = tester.getTopRight(
        find.text('¥ 13,780'),
      );
      final trendComparisonBottom = tester
          .getBottomLeft(find.text('较上月 + ¥ 8,230'))
          .dy;
      final summaryCardBottom = tester
          .getBottomLeft(find.byKey(const Key('overview-summary-card')))
          .dy;
      final incomeLabelTopLeft = tester.getTopLeft(find.text('收入'));
      final expenseLabelTopLeft = tester.getTopLeft(find.text('支出'));
      final balanceLabelTopLeft = tester.getTopLeft(find.text('结余'));

      expect(
        totalAssetsLabelTopLeft.dx,
        greaterThan(netWorthLabelTopLeft.dx + 80),
      );
      expect(
        totalLiabilitiesLabelTopLeft.dx,
        greaterThan(netWorthLabelTopLeft.dx + 80),
      );
      expect(
        totalLiabilitiesLabelTopLeft.dy,
        greaterThan(totalAssetsLabelTopLeft.dy),
      );
      expect(
        (totalAssetsLabelTopLeft.dx - totalLiabilitiesLabelTopLeft.dx).abs(),
        lessThan(16),
      );
      expect(
        (totalAssetsAmountTopRight.dx - totalLiabilitiesAmountTopRight.dx)
            .abs(),
        lessThan(2),
      );
      expect(summaryCardBottom - trendComparisonBottom, lessThan(28));

      expect(
        (incomeLabelTopLeft.dy - expenseLabelTopLeft.dy).abs(),
        lessThan(8),
      );
      expect(
        (expenseLabelTopLeft.dy - balanceLabelTopLeft.dy).abs(),
        lessThan(8),
      );

      await tester.tap(find.text('本月'));
      await tester.pumpAndSettle();

      expect(find.text('¥ 20,000.00'), findsOneWidget);
      expect(find.text('¥ 5,860.00'), findsOneWidget);
      expect(find.text('¥ 14,140.00'), findsOneWidget);
      expect(find.text('本周收支趋势'), findsNothing);
      expect(find.text('本月收支趋势'), findsOneWidget);

      await tester.dragUntilVisible(
        find.text('最近交易'),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      expect(find.text('最近交易'), findsOneWidget);
      expect(find.text('*'), findsOneWidget);
      expect(find.text('Market'), findsOneWidget);
    },
  );

  testWidgets('trend summary stays usable on narrow Android widths', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 800),
            textScaler: TextScaler.linear(1.35),
          ),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 288,
                child: TrendSummary(
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
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('trend-metrics-wrap')), findsOneWidget);
    expect(find.byKey(const Key('trend-metrics-row')), findsNothing);

    await tester.tap(find.text('本月'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('trend-metrics-wrap')), findsOneWidget);
    expect(find.byKey(const Key('trend-metrics-row')), findsNothing);
  });

  testWidgets(
    'renders detail timeline with Chinese filter chips and beancount record types',
    (WidgetTester tester) async {
      await tester.pumpWidget(_demoApp);
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text('明细'),
        ),
      );
      await tester.pumpAndSettle();

      final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));

      expect(find.text('全部'), findsOneWidget);
      expect(find.text('交易'), findsAtLeastNWidgets(1));
      expect(find.text('开户'), findsAtLeastNWidgets(1));
      expect(find.text('闭户'), findsOneWidget);
      expect(find.text('价格'), findsAtLeastNWidgets(1));
      expect(find.text('断言'), findsAtLeastNWidgets(1));
      expect(find.text('事件'), findsNothing);
      expect(find.text('补齐'), findsNothing);
      expect(chips.every((chip) => chip.showCheckmark == false), isTrue);
      expect(find.text('*'), findsOneWidget);
      expect(find.text('!'), findsOneWidget);
      expect(find.text('R'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('O'), findsOneWidget);
      expect(find.text('Market'), findsOneWidget);
      expect(find.text('USD/CNY'), findsOneWidget);
      expect(find.text('Assets:Bank:Checking'), findsOneWidget);

      await tester.dragUntilVisible(
        find.text('C'),
        find.byType(ListView).first,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      expect(find.text('C'), findsOneWidget);
      expect(find.text('E'), findsNothing);
      expect(find.text('P'), findsNothing);
    },
  );

  testWidgets('shows ledger load error instead of empty ledger state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          beancountRepositoryProvider.overrideWithValue(
            _ThrowingLedgerRepository(),
          ),
        ],
        child: const MaterialApp(home: OverviewPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('账本加载失败'), findsOneWidget);
    expect(find.textContaining('ledger boom'), findsOneWidget);
    expect(find.text('还没有账本'), findsNothing);
  });

  testWidgets('renders account tree with balances and status summaries', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_demoApp);
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(BottomNavigationBar),
        matching: find.text('账户'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('开放账户'), findsOneWidget);
    expect(find.text('已关闭'), findsOneWidget);
    expect(find.text('Assets'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('Bank'), findsOneWidget);
    expect(find.text('Checking'), findsOneWidget);
    expect(find.text('Brokerage'), findsOneWidget);
    expect(find.text('最后变动 2h 前'), findsOneWidget);
  });

  testWidgets('renders statistics tabs for analysis drill-down', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_demoApp);
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(BottomNavigationBar),
        matching: find.text('统计'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('收支'), findsAtLeastNWidgets(1));
    expect(find.text('资产'), findsAtLeastNWidgets(1));
    expect(find.text('账户贡献'), findsAtLeastNWidgets(1));
    expect(find.text('时间对比'), findsAtLeastNWidgets(1));
    expect(find.text('支出分类排行'), findsOneWidget);
    expect(find.text('收入来源排行'), findsOneWidget);

    await tester.tap(find.text('资产').last);
    await tester.pumpAndSettle();

    expect(find.text('资产类别分布'), findsOneWidget);
    expect(find.text('多币种资产摘要'), findsOneWidget);
  });

  testWidgets('renders settings as ledger and advanced tools center', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_demoApp);
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(BottomNavigationBar),
        matching: find.text('设置'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('账本管理'), findsOneWidget);
    expect(find.text('账本一览'), findsOneWidget);
    expect(find.text('文本视图'), findsOneWidget);
    expect(find.text('高级工具'), findsOneWidget);
    expect(find.text('周期记账'), findsOneWidget);
    expect(find.text('通用偏好'), findsOneWidget);

    await tester.dragUntilVisible(
      find.text('显示密度'),
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    expect(find.text('显示密度'), findsOneWidget);
    expect(find.text('默认基准货币'), findsOneWidget);
  });

  testWidgets('compose page can return to the previous tab page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_demoApp);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('记一笔'));
    await tester.pumpAndSettle();

    expect(find.text('新建交易'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('净资产'), findsOneWidget);
    expect(find.text('新建交易'), findsNothing);
  });

  testWidgets('ledger page can return to settings', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_demoApp);
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(BottomNavigationBar),
        matching: find.text('设置'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('账本一览'));
    await tester.pumpAndSettle();

    expect(find.text('账本一览'), findsAtLeastNWidgets(1));

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('账本管理'), findsOneWidget);
  });

  testWidgets(
    'overview page highlights the saved transaction receipt and matching row',
    (WidgetTester tester) async {
      final receipt = QuickEntrySaveReceipt(
        date: DateTime(2026, 4, 19),
        summary: 'Coffee',
        amount: '18.50',
        commodity: 'CNY',
        primaryAccount: 'Expenses:Food',
        counterAccount: 'Assets:Cash',
        submittedAt: DateTime(2026, 4, 19, 9, 0),
      );
      final repository = _InteractiveQuickEntryRepository(
        journalEntries: <JournalEntry>[
          JournalEntry(
            date: DateTime(2026, 4, 19),
            type: JournalEntryType.transaction,
            title: 'Coffee',
            primaryAccount: 'Expenses:Food',
            secondaryAccount: 'Assets:Cash',
            amount: const EntryAmount(value: -18.5, commodity: 'CNY'),
            transactionFlag: TransactionFlag.cleared,
          ),
          JournalEntry(
            date: DateTime(2026, 4, 12),
            type: JournalEntryType.transaction,
            title: 'Market',
            primaryAccount: 'Expenses:Food',
            secondaryAccount: 'Assets:Cash',
            amount: const EntryAmount(value: -86, commodity: 'CNY'),
            transactionFlag: TransactionFlag.cleared,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            beancountRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(home: OverviewPage()),
        ),
      );
      await tester.pumpAndSettle();

      ProviderScope.containerOf(tester.element(find.byType(OverviewPage)))
          .read(quickEntrySessionStateProvider.notifier)
          .state = QuickEntrySessionState(
        latestSavedTransaction: receipt,
        recentAccountPairs: const <RecentAccountPair>[
          RecentAccountPair(
            primaryAccount: 'Expenses:Food',
            counterAccount: 'Assets:Cash',
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('quick-entry-feedback-banner')),
        findsOneWidget,
      );
      expect(find.text('刚刚记录'), findsAtLeastNWidgets(1));
      expect(find.text('Coffee'), findsAtLeastNWidgets(1));
      expect(
        find.byKey(const Key('recent-transaction-highlight')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'journal page surfaces the saved transaction feedback and matching row',
    (WidgetTester tester) async {
      final receipt = QuickEntrySaveReceipt(
        date: DateTime(2026, 4, 19),
        summary: 'Lunch',
        amount: '28.00',
        commodity: 'CNY',
        primaryAccount: 'Expenses:Food',
        counterAccount: 'Assets:Cash',
        submittedAt: DateTime(2026, 4, 19, 9, 30),
      );
      final repository = _InteractiveQuickEntryRepository(
        journalEntries: <JournalEntry>[
          JournalEntry(
            date: DateTime(2026, 4, 19),
            type: JournalEntryType.transaction,
            title: 'Lunch',
            primaryAccount: 'Expenses:Food',
            secondaryAccount: 'Assets:Cash',
            amount: const EntryAmount(value: -28, commodity: 'CNY'),
            transactionFlag: TransactionFlag.cleared,
          ),
          JournalEntry(
            date: DateTime(2026, 4, 12),
            type: JournalEntryType.transaction,
            title: 'Market',
            primaryAccount: 'Expenses:Food',
            secondaryAccount: 'Assets:Cash',
            amount: const EntryAmount(value: -86, commodity: 'CNY'),
            transactionFlag: TransactionFlag.cleared,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            beancountRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(home: Scaffold(body: JournalPage())),
        ),
      );
      await tester.pumpAndSettle();

      ProviderScope.containerOf(tester.element(find.byType(JournalPage)))
          .read(quickEntrySessionStateProvider.notifier)
          .state = QuickEntrySessionState(
        latestSavedTransaction: receipt,
        recentAccountPairs: const <RecentAccountPair>[
          RecentAccountPair(
            primaryAccount: 'Expenses:Food',
            counterAccount: 'Assets:Cash',
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('quick-entry-feedback-banner')),
        findsOneWidget,
      );
      expect(find.text('刚刚记录'), findsAtLeastNWidgets(1));
      expect(find.text('Lunch'), findsAtLeastNWidgets(1));
      expect(find.byKey(const Key('journal-entry-highlight')), findsOneWidget);
    },
  );
}

class _ThrowingLedgerRepository implements BeancountRepository {
  @override
  Future<void> appendTransaction(CreateTransactionInput input) async {
    throw UnimplementedError();
  }

  @override
  Future<void> createDefaultLedger() async {}

  @override
  Future<void> importLedger(String sourcePath) async {}

  @override
  Future<List<LedgerTextFile>> loadCurrentLedgerFiles() async {
    throw StateError('ledger files boom');
  }

  @override
  Future<void> reopenLedger(String ledgerId) async {}

  @override
  Future<void> renameLedger(String ledgerId, String newName) async {}

  @override
  Future<void> deleteLedger(String ledgerId) async {}

  @override
  Future<Ledger?> loadCurrentLedger() async {
    throw StateError('ledger boom');
  }

  @override
  Future<List<RecentLedger>> loadRecentLedgers() async {
    return const <RecentLedger>[];
  }

  @override
  Future<OverviewSnapshot> loadOverviewSnapshot() async {
    throw UnimplementedError();
  }

  @override
  Future<List<JournalEntry>> loadJournalEntries() async {
    throw UnimplementedError();
  }

  @override
  Future<List<AccountNode>> loadAccountTree() async {
    throw UnimplementedError();
  }

  @override
  Future<Map<ReportCategory, List<ReportSummary>>> loadReportSummaries() async {
    throw UnimplementedError();
  }

  @override
  Future<List<ValidationIssue>> loadValidationIssues() async {
    return const <ValidationIssue>[];
  }
}

class _InteractiveQuickEntryRepository implements BeancountRepository {
  _InteractiveQuickEntryRepository({List<JournalEntry>? journalEntries})
    : _journalEntries =
          journalEntries ??
          <JournalEntry>[
            JournalEntry(
              date: DateTime(2026, 4, 12),
              type: JournalEntryType.transaction,
              title: 'Market',
              primaryAccount: 'Expenses:Food',
              secondaryAccount: 'Assets:Cash',
              amount: const EntryAmount(value: -86, commodity: 'CNY'),
              transactionFlag: TransactionFlag.cleared,
            ),
          ];

  final List<JournalEntry> _journalEntries;

  @override
  Future<void> appendTransaction(CreateTransactionInput input) async {
    _journalEntries.insert(
      0,
      JournalEntry(
        date: input.date,
        type: JournalEntryType.transaction,
        title: input.summary,
        primaryAccount: input.primaryAccount,
        secondaryAccount: input.counterAccount,
        amount: EntryAmount(
          value: -num.parse(input.amount),
          commodity: input.commodity,
        ),
        transactionFlag: TransactionFlag.cleared,
      ),
    );
  }

  @override
  Future<void> createDefaultLedger() async {}

  @override
  Future<void> importLedger(String sourcePath) async {}

  @override
  Future<List<AccountNode>> loadAccountTree() async {
    return const <AccountNode>[
      AccountNode(
        name: 'Assets',
        subtitle: '活跃',
        balance: 'CNY 100',
        isPostable: false,
        children: <AccountNode>[
          AccountNode(name: 'Cash', subtitle: '活跃', balance: 'CNY 100'),
        ],
      ),
      AccountNode(
        name: 'Expenses',
        subtitle: '活跃',
        balance: 'CNY 0',
        isPostable: false,
        children: <AccountNode>[
          AccountNode(name: 'Food', subtitle: '活跃', balance: 'CNY 0'),
        ],
      ),
    ];
  }

  @override
  Future<Ledger?> loadCurrentLedger() async {
    return Ledger(
      id: 'w-1',
      name: 'Household',
      rootPath: '/ledger/household',
      lastImportedAt: DateTime(2026, 4, 18, 9, 0),
      loadedFileCount: 2,
      status: LedgerStatus.ready,
      openAccountCount: 3,
      closedAccountCount: 1,
    );
  }

  @override
  Future<List<LedgerTextFile>> loadCurrentLedgerFiles() async {
    return const <LedgerTextFile>[];
  }

  @override
  Future<List<JournalEntry>> loadJournalEntries() async {
    return List<JournalEntry>.unmodifiable(_journalEntries);
  }

  @override
  Future<OverviewSnapshot> loadOverviewSnapshot() async {
    return OverviewSnapshot(
      netWorth: 'CNY 128,420',
      totalAssets: 'CNY 142,200',
      totalLiabilities: 'CNY 13,780',
      changeDescription: '较上月 + CNY 8,230',
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
      recentTransactions: List<JournalEntry>.unmodifiable(_journalEntries),
    );
  }

  @override
  Future<List<RecentLedger>> loadRecentLedgers() async {
    return const <RecentLedger>[];
  }

  @override
  Future<Map<ReportCategory, List<ReportSummary>>> loadReportSummaries() async {
    return const <ReportCategory, List<ReportSummary>>{
      ReportCategory.incomeExpense: <ReportSummary>[
        ReportSummary(title: '支出分类排行', lines: <String>['Food  CNY 1,820']),
      ],
    };
  }

  @override
  Future<List<ValidationIssue>> loadValidationIssues() async {
    return const <ValidationIssue>[];
  }

  @override
  Future<void> reopenLedger(String ledgerId) async {}

  @override
  Future<void> renameLedger(String ledgerId, String newName) async {}

  @override
  Future<void> deleteLedger(String ledgerId) async {}
}

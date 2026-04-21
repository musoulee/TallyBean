import 'package:beancount_bridge/beancount_bridge.dart';
import 'package:beancount_bridge/src/native/api.dart';
import 'package:beancount_bridge/src/native/rust_ledger_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'rust facade opens sessions and serves query data through the runtime',
    () async {
      final runtime = _FakeRustLedgerRuntime();
      final bridge = RustBeancountBridgeFacade(runtime: runtime);

      final session = await bridge.openLedger(
        '/ledger',
        '/ledger/main.beancount',
      );
      final diagnostics = await bridge.listDiagnostics(session.handle);
      final entries = await bridge.getJournalEntries(session.handle);
      final accountNodes = await bridge.getAccountTree(session.handle);
      final reports = await bridge.getReportSnapshot(session.handle);
      final documents = await bridge.listDocuments(session.handle);
      final document = await bridge.getDocument(
        session.handle,
        documents.single.documentId,
      );

      expect(runtime.openCalls, 1);
      expect(runtime.lastRootPath, '/ledger');
      expect(runtime.lastEntryFilePath, '/ledger/main.beancount');
      expect(session.summary.ledgerId, 'ledger');
      expect(session.summary.netWorth, 'CNY 1,000');
      expect(diagnostics, hasLength(1));
      expect(entries.single.title, 'Salary');
      expect(accountNodes.nodes.single.name, 'Assets');
      expect(accountNodes.nodes.single.isPostable, isFalse);
      expect(reports.single.key, 'income_expense');
      expect(documents.single.relativePath, 'main.beancount');
      expect(document.content, contains('open Assets:Cash CNY'));
    },
  );

  test('rust facade refreshes and closes sessions', () async {
    final runtime = _FakeRustLedgerRuntime();
    final bridge = RustBeancountBridgeFacade(runtime: runtime);

    final session = await bridge.openLedger(
      '/ledger',
      '/ledger/main.beancount',
    );
    final refreshed = await bridge.refreshLedger(session.handle);
    await bridge.closeLedger(session.handle);

    expect(runtime.refreshCalls, 1);
    expect(runtime.closedHandles, <int>[7]);
    expect(refreshed.summary.closedAccountCount, 1);
  });

  test('rust facade evicts cached sessions even when close throws', () async {
    final runtime = _FakeRustLedgerRuntime(
      closeError: StateError('close failed'),
    );
    final bridge = RustBeancountBridgeFacade(runtime: runtime);

    final first = await bridge.openLedger('/ledger', '/ledger/main.beancount');

    await expectLater(
      bridge.closeLedger(first.handle),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('close failed'),
        ),
      ),
    );

    final reopened = await bridge.openLedger(
      '/ledger',
      '/ledger/main.beancount',
    );

    expect(runtime.openCalls, 2);
    expect(reopened.handle, isNot(first.handle));
    expect(runtime.closedHandles, <int>[first.handle]);
  });

  test(
    'rust facade loads every journal page instead of truncating after the first page',
    () async {
      final entries = List<RustJournalEntry>.generate(
        5001,
        (index) => RustJournalEntry(
          dateIso8601: '2026-04-02T00:00:00.000',
          entryType: RustJournalEntryType.transaction,
          title: 'Entry $index',
          primaryAccount: 'Assets:Cash',
          secondaryAccount: 'Income:Salary',
        ),
        growable: false,
      );
      final runtime = _FakeRustLedgerRuntime(journalEntries: entries);
      final bridge = RustBeancountBridgeFacade(runtime: runtime);

      final loaded = await bridge.getJournalEntries(7);

      expect(loaded, hasLength(5001));
      expect(loaded.first.title, 'Entry 0');
      expect(loaded.last.title, 'Entry 5000');
      expect(runtime.seenJournalQueries, const <RustJournalQuery>[
        RustJournalQuery(pageSize: 5000, offset: 0),
        RustJournalQuery(pageSize: 5000, offset: 5000),
      ]);
    },
  );

  test(
    'rust facade keeps price entry amounts in suffix display mode',
    () async {
      final runtime = _FakeRustLedgerRuntime(
        journalEntries: const <RustJournalEntry>[
          RustJournalEntry(
            dateIso8601: '2026-04-02T00:00:00.000',
            entryType: RustJournalEntryType.price,
            title: 'USD/CNY',
            primaryAccount: 'USD/CNY',
            amount: RustAmount(
              value: 7.242,
              commodity: 'CNY',
              fractionDigits: 3,
            ),
          ),
        ],
      );
      final bridge = RustBeancountBridgeFacade(runtime: runtime);

      final entries = await bridge.getJournalEntries(7);

      expect(
        entries.single.amount?.displayStyle,
        BridgeEntryAmountDisplayStyle.suffix,
      );
    },
  );

  test(
    'parseLedger refreshes cached ledgers and keeps follow-up queries available',
    () async {
      final runtime = _FakeRustLedgerRuntime(
        summaryForState: (handle, refreshCalls) => RustLedgerSummary(
          ledgerId: 'ledger',
          ledgerName: 'Ledger $handle',
          loadedFileCount: 2 + refreshCalls,
          openAccountCount: 2,
          closedAccountCount: 0,
          netWorth: 'CNY ${1000 + refreshCalls}',
          totalAssets: 'CNY ${1000 + refreshCalls}',
          totalLiabilities: '--',
          changeDescription: '较上月 + CNY ${1000 + refreshCalls}',
          weekTrend: RustTrendSummary(
            chartLabel: '本周收支趋势',
            income: (1000 + refreshCalls).toDouble(),
            expense: 0,
            balance: (1000 + refreshCalls).toDouble(),
          ),
          monthTrend: RustTrendSummary(
            chartLabel: '本月收支趋势',
            income: (1000 + refreshCalls).toDouble(),
            expense: 0,
            balance: (1000 + refreshCalls).toDouble(),
          ),
        ),
      );
      final bridge = RustBeancountBridgeFacade(runtime: runtime);

      final first = await bridge.parseLedger(
        '/ledger',
        '/ledger/main.beancount',
      );
      final second = await bridge.parseLedger(
        '/ledger',
        '/ledger/main.beancount',
      );
      final issues = await bridge.validateLedger(second.ledgerId);
      final reports = await bridge.buildReports(second.ledgerId);

      expect(runtime.openCalls, 1);
      expect(runtime.refreshCalls, 1);
      expect(runtime.closedHandles, isEmpty);
      expect(first.loadedFileCount, 2);
      expect(second.loadedFileCount, 3);
      expect(first.overview.netWorth, 'CNY 1000');
      expect(second.overview.netWorth, 'CNY 1001');
      expect(issues, hasLength(1));
      expect(reports.single.key, 'income_expense');
    },
  );
}

class _FakeRustLedgerRuntime implements RustLedgerRuntime {
  _FakeRustLedgerRuntime({
    List<RustJournalEntry>? journalEntries,
    RustLedgerSummary Function(int handle, int refreshCalls)? summaryForState,
    this.closeError,
  }) : _journalEntries = journalEntries ?? _defaultJournalEntries,
       _summaryForState = summaryForState;

  static const List<RustJournalEntry> _defaultJournalEntries =
      <RustJournalEntry>[
        RustJournalEntry(
          dateIso8601: '2026-04-02T00:00:00.000',
          entryType: RustJournalEntryType.transaction,
          title: 'Salary',
          primaryAccount: 'Assets:Cash',
          secondaryAccount: 'Income:Salary',
          transactionFlag: RustTransactionFlag.cleared,
        ),
      ];

  int openCalls = 0;
  int refreshCalls = 0;
  String? lastRootPath;
  String? lastEntryFilePath;
  final List<int> closedHandles = <int>[];
  final Object? closeError;
  final List<RustJournalQuery> seenJournalQueries = <RustJournalQuery>[];
  final List<RustJournalEntry> _journalEntries;
  final RustLedgerSummary Function(int handle, int refreshCalls)?
  _summaryForState;
  int _nextHandle = 7;

  @override
  Future<void> closeLedgerSession({required int handle}) async {
    closedHandles.add(handle);
    if (closeError != null) {
      throw closeError!;
    }
  }

  @override
  Future<RustAccountTree> getAccountTree({
    required int handle,
    required RustAccountTreeQuery query,
  }) async {
    return const RustAccountTree(
      nodes: <RustAccountNode>[
        RustAccountNode(
          name: 'Assets',
          subtitle: '活跃',
          balance: 'CNY 1,000',
          isClosed: false,
          isPostable: false,
          children: <RustAccountNode>[],
        ),
      ],
    );
  }

  @override
  Future<RustDocument> getDocument({
    required int handle,
    required String documentId,
  }) async {
    return const RustDocument(
      documentId: 'main.beancount',
      fileName: 'main.beancount',
      relativePath: 'main.beancount',
      content: '2026-04-01 open Assets:Cash CNY',
      sizeBytes: 31,
      isEntry: true,
    );
  }

  @override
  Future<RustJournalPage> getJournalPage({
    required int handle,
    required RustJournalQuery query,
  }) async {
    seenJournalQueries.add(query);
    final offset = query.offset < 0 ? 0 : query.offset;
    final pageSize = query.pageSize < 0 ? 0 : query.pageSize;
    final pageEntries = offset >= _journalEntries.length || pageSize == 0
        ? const <RustJournalEntry>[]
        : _journalEntries.skip(offset).take(pageSize).toList(growable: false);
    return RustJournalPage(
      totalCount: _journalEntries.length,
      entries: pageEntries,
    );
  }

  @override
  Future<List<RustLedgerDiagnostic>> listDiagnostics({
    required int handle,
    required RustDiagnosticQuery query,
  }) async {
    return const <RustLedgerDiagnostic>[
      RustLedgerDiagnostic(
        message: '暂不支持 note 指令，已跳过',
        location: 'main.beancount:3',
        blocking: false,
      ),
    ];
  }

  @override
  Future<List<RustDocumentSummary>> listDocuments({required int handle}) async {
    return const <RustDocumentSummary>[
      RustDocumentSummary(
        documentId: 'main.beancount',
        fileName: 'main.beancount',
        relativePath: 'main.beancount',
        sizeBytes: 31,
        isEntry: true,
      ),
    ];
  }

  @override
  Future<int> openLedgerSession({
    required String rootPath,
    required String entryFilePath,
  }) async {
    openCalls += 1;
    lastRootPath = rootPath;
    lastEntryFilePath = entryFilePath;
    return _nextHandle++;
  }

  @override
  Future<RustLedgerSnapshot> parseLedger({
    required String rootPath,
    required String entryFilePath,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<RustRefreshResult> refreshLedgerSession({required int handle}) async {
    refreshCalls += 1;
    return RustRefreshResult(
      summary:
          _summaryForState?.call(handle, refreshCalls) ??
          _summary(closedAccountCount: 1),
      diagnosticsCount: 0,
    );
  }

  @override
  Future<RustReportSnapshot> getReportSnapshot({
    required int handle,
    required RustReportQuery query,
  }) async {
    return const RustReportSnapshot(
      results: <RustReportResult>[
        RustReportResult(
          key: 'income_expense',
          lines: <String>['本周收入 ¥ 1,000'],
        ),
      ],
    );
  }

  @override
  Future<RustLedgerSummary> getLedgerSummary({required int handle}) async {
    return _summaryForState?.call(handle, refreshCalls) ?? _summary();
  }

  RustLedgerSummary _summary({int closedAccountCount = 0}) {
    return RustLedgerSummary(
      ledgerId: 'ledger',
      ledgerName: 'Household Ledger',
      loadedFileCount: 2,
      openAccountCount: 2,
      closedAccountCount: closedAccountCount,
      netWorth: 'CNY 1,000',
      totalAssets: 'CNY 1,000',
      totalLiabilities: '--',
      changeDescription: '较上月 + CNY 1,000',
      weekTrend: const RustTrendSummary(
        chartLabel: '本周收支趋势',
        income: 1000,
        expense: 0,
        balance: 1000,
      ),
      monthTrend: const RustTrendSummary(
        chartLabel: '本月收支趋势',
        income: 1000,
        expense: 0,
        balance: 1000,
      ),
    );
  }
}

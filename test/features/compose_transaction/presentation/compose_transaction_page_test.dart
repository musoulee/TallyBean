import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tally_bean/app/bootstrap/app_config.dart';
import 'package:tally_bean/app/di/app_providers.dart';
import 'package:tally_bean/features/compose_transaction/presentation/pages/compose_transaction_page.dart';

void main() {
  testWidgets('renders compose form and keeps save disabled until valid', (
    tester,
  ) async {
    final repository = _FakeComposeRepository();

    await tester.pumpWidget(_host(repository: repository));
    await tester.pumpAndSettle();

    expect(find.text('新建交易'), findsOneWidget);
    expect(find.textContaining('日期'), findsAtLeastNWidgets(1));
    expect(find.textContaining('摘要'), findsAtLeastNWidgets(1));
    expect(find.textContaining('金额'), findsAtLeastNWidgets(1));
    expect(find.textContaining('记到账户'), findsAtLeastNWidgets(1));
    expect(find.textContaining('从账户'), findsAtLeastNWidgets(1));

    final finder = find.byKey(const Key('compose-submit-button'));
    await tester.dragUntilVisible(
      finder,
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    expect(_saveButton(tester).onPressed, isNull);
  });

  testWidgets(
    'account picker shows open postable accounts and hides invalid nodes',
    (tester) async {
      final repository = _FakeComposeRepository(
        accounts: const <AccountNode>[
          AccountNode(
            name: 'Assets',
            subtitle: '活跃',
            balance: 'CNY 0',
            isPostable: false,
            children: <AccountNode>[
              AccountNode(
                name: 'Bank',
                subtitle: '1 个子账户',
                balance: 'CNY 0',
                isPostable: true,
                children: <AccountNode>[
                  AccountNode(
                    name: 'Checking',
                    subtitle: '活跃',
                    balance: 'CNY 0',
                  ),
                  AccountNode(
                    name: 'Old',
                    subtitle: '已关闭',
                    balance: 'CNY 0',
                    isClosed: true,
                  ),
                ],
              ),
              AccountNode(
                name: 'Archived',
                subtitle: '已关闭',
                balance: 'CNY 0',
                isClosed: true,
                children: <AccountNode>[
                  AccountNode(
                    name: 'ShouldStayHidden',
                    subtitle: '活跃',
                    balance: 'CNY 0',
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(_host(repository: repository));
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.byKey(const Key('compose-primary-account-field')),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('compose-primary-account-field')));
      await tester.pumpAndSettle();

      expect(find.text('Assets'), findsNothing);
      expect(find.text('Assets:Bank'), findsOneWidget);
      expect(find.text('Assets:Bank:Checking'), findsOneWidget);
      expect(find.text('Assets:Bank:Old'), findsNothing);
      expect(find.text('Assets:Archived'), findsNothing);
      expect(find.text('Assets:Archived:ShouldStayHidden'), findsNothing);
    },
  );

  testWidgets('save stays disabled for Rust-incompatible amount formats', (
    tester,
  ) async {
    final repository = _FakeComposeRepository();

    await tester.pumpWidget(_host(repository: repository));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('compose-summary-field')),
      'Coffee',
    );
    await tester.pump();

    await tester.ensureVisible(
      find.byKey(const Key('compose-primary-account-field')),
    );
    await tester.tap(find.byKey(const Key('compose-primary-account-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expenses:Food').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('compose-counter-account-field')),
    );
    await tester.tap(find.byKey(const Key('compose-counter-account-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assets:Cash').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('compose-amount-field')),
      '1e3',
    );
    await tester.pump();
    
    final finder = find.byKey(const Key('compose-submit-button'));
    await tester.dragUntilVisible(
      finder,
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    expect(_saveButton(tester).onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('compose-amount-field')),
      '18.',
    );
    await tester.pump();
    expect(_saveButton(tester).onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('compose-amount-field')),
      '18.50',
    );
    await tester.pumpAndSettle();
    
    await tester.ensureVisible(find.byKey(const Key('compose-submit-button')));
    await tester.pumpAndSettle();
    
    expect(_saveButton(tester).onPressed, isNotNull);
  });

  testWidgets('save stays disabled when summary contains double quotes', (
    tester,
  ) async {
    final repository = _FakeComposeRepository();

    await tester.pumpWidget(_host(repository: repository));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('compose-summary-field')),
      'He said "hi"',
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('compose-amount-field')),
      '18.50',
    );
    await tester.pump();

    await tester.ensureVisible(
      find.byKey(const Key('compose-primary-account-field')),
    );
    await tester.tap(find.byKey(const Key('compose-primary-account-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expenses:Food').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('compose-counter-account-field')),
    );
    await tester.tap(find.byKey(const Key('compose-counter-account-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assets:Cash').last);
    await tester.pumpAndSettle();

    final finder = find.byKey(const Key('compose-submit-button'));
    await tester.dragUntilVisible(
      finder,
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    expect(_saveButton(tester).onPressed, isNull);
    expect(find.text('摘要暂不支持双引号'), findsOneWidget);
  });

  testWidgets(
    'successful submit pops back and forwards the entered transaction',
    (tester) async {
      final repository = _FakeComposeRepository();

      await tester.pumpWidget(_launchHost(repository: repository));
      await tester.pumpAndSettle();

      await tester.tap(find.text('打开记一笔'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('compose-summary-field')),
        'Coffee',
      );
      await tester.enterText(
        find.byKey(const Key('compose-amount-field')),
        '18.50',
      );

      await tester.ensureVisible(
        find.byKey(const Key('compose-primary-account-field')),
      );
      await tester.tap(find.byKey(const Key('compose-primary-account-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Expenses:Food').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('compose-counter-account-field')),
      );
      await tester.tap(find.byKey(const Key('compose-counter-account-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Assets:Cash').last);
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.byKey(const Key('compose-submit-button')),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('compose-submit-button')));
      await tester.pumpAndSettle();

      expect(find.text('主页'), findsOneWidget);
      expect(find.text('新建交易'), findsNothing);
      expect(repository.appendedInputs, hasLength(1));
      expect(repository.appendedInputs.single.summary, 'Coffee');
      expect(repository.appendedInputs.single.postings.first.amount, '18.50');
      expect(
        repository.appendedInputs.single.postings.first.account,
        'Expenses:Food',
      );
      expect(
        repository.appendedInputs.single.postings.last.account,
        'Assets:Cash',
      );
    },
  );

  testWidgets(
    'failed submit keeps the compose page open and shows the repository error',
    (tester) async {
      final repository = _FakeComposeRepository(
        appendError: StateError('Transaction 不平衡'),
      );

      await tester.pumpWidget(_host(repository: repository));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('compose-summary-field')),
        'Coffee',
      );
      await tester.enterText(
        find.byKey(const Key('compose-amount-field')),
        '18.50',
      );

      await tester.ensureVisible(
        find.byKey(const Key('compose-primary-account-field')),
      );
      await tester.tap(find.byKey(const Key('compose-primary-account-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Expenses:Food').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('compose-counter-account-field')),
      );
      await tester.tap(find.byKey(const Key('compose-counter-account-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Assets:Cash').last);
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.byKey(const Key('compose-submit-button')),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('compose-submit-button')));
      await tester.pumpAndSettle();

      expect(find.text('新建交易'), findsOneWidget);
      expect(find.textContaining('Transaction 不平衡'), findsOneWidget);
    },
  );

  testWidgets('dirty draft asks for confirmation before leaving the page', (
    tester,
  ) async {
    final repository = _FakeComposeRepository();

    await tester.pumpWidget(_launchHost(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('打开记一笔'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('compose-summary-field')),
      'Coffee',
    );
    await tester.pump();
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('放弃这次录入？'), findsOneWidget);
    expect(find.text('保留内容'), findsOneWidget);
    expect(find.text('放弃'), findsOneWidget);
    expect(find.text('新建交易'), findsOneWidget);

    await tester.tap(find.text('保留内容'));
    await tester.pumpAndSettle();

    expect(find.text('新建交易'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃'));
    await tester.pumpAndSettle();

    expect(find.text('主页'), findsOneWidget);
    expect(find.text('新建交易'), findsNothing);
  });

  testWidgets(
    'successful submit seeds recent pair shortcuts and recent account sections',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _FakeComposeRepository();

      await tester.pumpWidget(_launchHost(repository: repository));
      await tester.pumpAndSettle();

      await tester.tap(find.text('打开记一笔'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('compose-summary-field')),
        'Coffee',
      );
      await tester.enterText(
        find.byKey(const Key('compose-amount-field')),
        '18.50',
      );

      await tester.ensureVisible(
        find.byKey(const Key('compose-primary-account-field')),
      );
      await tester.tap(find.byKey(const Key('compose-primary-account-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Expenses:Food').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('compose-counter-account-field')),
      );
      await tester.tap(find.byKey(const Key('compose-counter-account-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Assets:Cash').last);
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.byKey(const Key('compose-submit-button')),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('compose-submit-button')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('打开记一笔'));
      await tester.pumpAndSettle();

      final chipFinder = find.byKey(const Key('compose-recent-pair-chip-0'));
      await tester.dragUntilVisible(
        chipFinder,
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      await tester.tap(chipFinder);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('compose-primary-account-field')),
          matching: find.text('Expenses:Food'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('compose-counter-account-field')),
          matching: find.text('Assets:Cash'),
        ),
        findsOneWidget,
      );

      await tester.ensureVisible(
        find.byKey(const Key('compose-primary-account-field')),
      );
      await tester.tap(find.byKey(const Key('compose-primary-account-field')));
      await tester.pumpAndSettle();

      expect(find.text('最近使用'), findsOneWidget);
      expect(find.text('Expenses:Food'), findsAtLeastNWidgets(1));
    },
  );

  testWidgets('demo mode stays read-only and keeps submit disabled', (
    tester,
  ) async {
    final repository = _FakeComposeRepository();

    await tester.pumpWidget(
      _host(repository: repository, config: const AppConfig(useDemoData: true)),
    );
    await tester.pumpAndSettle();

    expect(find.text('演示数据模式当前为只读，不能保存新交易。'), findsOneWidget);
    
    final finder = find.byKey(const Key('compose-submit-button'));
    await tester.dragUntilVisible(
      finder,
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    
    expect(_saveButton(tester).onPressed, isNull);
  });
}

FilledButton _saveButton(WidgetTester tester) {
  return tester.widget<FilledButton>(
    find.byKey(const Key('compose-submit-button')),
  );
}

Widget _host({
  required BeancountRepository repository,
  AppConfig config = defaultAppConfig,
}) {
  return ProviderScope(
    overrides: [
      beancountRepositoryProvider.overrideWithValue(repository),
      appConfigProvider.overrideWithValue(config),
    ],
    child: const MaterialApp(home: ComposeTransactionPage()),
  );
}

Widget _launchHost({required BeancountRepository repository}) {
  return ProviderScope(
    overrides: [beancountRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('主页'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ComposeTransactionPage(),
                      ),
                    );
                  },
                  child: const Text('打开记一笔'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _FakeComposeRepository implements BeancountRepository {
  _FakeComposeRepository({
    this.appendError,
    this.accounts = const <AccountNode>[
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
    ],
  });

  final Object? appendError;
  final List<AccountNode> accounts;
  final List<CreateTransactionInput> appendedInputs =
      <CreateTransactionInput>[];

  @override
  Future<void> appendTransaction(CreateTransactionInput input) async {
    if (appendError != null) {
      throw appendError!;
    }
    appendedInputs.add(input);
  }

  @override
  Future<void> createDefaultLedger() async {}

  @override
  Future<void> importLedger(String sourcePath) async {}

  @override
  Future<OverviewSnapshot> loadOverviewSnapshot() {
    throw UnimplementedError();
  }

  @override
  Future<List<AccountNode>> loadAccountTree() async => accounts;

  @override
  Future<Ledger?> loadCurrentLedger() async => _ledger;

  @override
  Future<List<LedgerTextFile>> loadCurrentLedgerFiles() async {
    return const <LedgerTextFile>[];
  }

  @override
  Future<List<JournalEntry>> loadJournalEntries() async {
    return const <JournalEntry>[];
  }

  @override
  Future<List<RecentLedger>> loadRecentLedgers() async {
    return const <RecentLedger>[];
  }

  @override
  Future<Map<ReportCategory, List<ReportSummary>>> loadReportSummaries() async {
    return const <ReportCategory, List<ReportSummary>>{};
  }

  @override
  Future<List<ValidationIssue>> loadValidationIssues() async {
    return const <ValidationIssue>[];
  }

  @override
  Future<void> reopenLedger(String ledgerId) async {}

  @override
  Future<void> deleteLedger(String ledgerId) async {}
}

final _ledger = Ledger(
  id: 'w-1',
  name: 'Household',
  rootPath: '/ledger/household',
  lastImportedAt: DateTime(2026, 4, 18, 9, 0),
  loadedFileCount: 2,
  status: LedgerStatus.ready,
  openAccountCount: 3,
  closedAccountCount: 1,
);

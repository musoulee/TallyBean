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
    expect(find.text('日期'), findsOneWidget);
    expect(find.text('摘要'), findsOneWidget);
    expect(find.text('金额'), findsOneWidget);
    expect(find.text('币种'), findsOneWidget);
    expect(find.text('记到账户'), findsOneWidget);
    expect(find.text('对方账户'), findsOneWidget);

    final saveButton = tester.widget<FilledButton>(
      find.byKey(const Key('compose-submit-button')),
    );
    expect(saveButton.onPressed, isNull);
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

    await tester.tap(find.byKey(const Key('compose-primary-account-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expenses:Food').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('compose-counter-account-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assets:Cash').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('compose-amount-field')),
      '1e3',
    );
    await tester.pump();
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
    await tester.pump();
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

      await tester.tap(find.byKey(const Key('compose-primary-account-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Expenses:Food').last);
      await tester.pumpAndSettle();

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
      expect(repository.appendedInputs.single.amount, '18.50');
      expect(repository.appendedInputs.single.primaryAccount, 'Expenses:Food');
      expect(repository.appendedInputs.single.counterAccount, 'Assets:Cash');
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

      await tester.tap(find.byKey(const Key('compose-primary-account-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Expenses:Food').last);
      await tester.pumpAndSettle();

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

  testWidgets('demo mode stays read-only and keeps submit disabled', (
    tester,
  ) async {
    final repository = _FakeComposeRepository();

    await tester.pumpWidget(
      _host(repository: repository, config: const AppConfig(useDemoData: true)),
    );
    await tester.pumpAndSettle();

    expect(find.text('演示数据模式当前为只读，不能保存新交易。'), findsOneWidget);
    final saveButton = tester.widget<FilledButton>(
      find.byKey(const Key('compose-submit-button')),
    );
    expect(saveButton.onPressed, isNull);
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
  Future<void> createDefaultWorkspace() async {}

  @override
  Future<void> importWorkspace(String sourcePath) async {}

  @override
  Future<OverviewSnapshot> loadOverviewSnapshot() {
    throw UnimplementedError();
  }

  @override
  Future<List<AccountNode>> loadAccountTree() async => accounts;

  @override
  Future<Workspace?> loadCurrentWorkspace() async => _workspace;

  @override
  Future<List<WorkspaceTextFile>> loadCurrentWorkspaceFiles() async {
    return const <WorkspaceTextFile>[];
  }

  @override
  Future<List<JournalEntry>> loadJournalEntries() async {
    return const <JournalEntry>[];
  }

  @override
  Future<List<RecentWorkspace>> loadRecentWorkspaces() async {
    return const <RecentWorkspace>[];
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
  Future<void> reopenWorkspace(String workspaceId) async {}

  @override
  Future<void> renameWorkspace(String workspaceId, String newName) async {}
}

final _workspace = Workspace(
  id: 'w-1',
  name: 'Household',
  rootPath: '/workspace/household',
  lastImportedAt: DateTime(2026, 4, 18, 9, 0),
  loadedFileCount: 2,
  status: WorkspaceStatus.ready,
  openAccountCount: 3,
  closedAccountCount: 1,
);

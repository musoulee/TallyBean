import 'dart:async';

import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tally_bean/app/bootstrap/app_config.dart';
import 'package:tally_bean/app/di/app_providers.dart';
import 'package:tally_bean/app/session/quick_entry_session.dart';
import 'package:tally_bean/features/compose_transaction/presentation/pages/compose_transaction_page.dart';

void main() {
  testWidgets('renders compose form and keeps save disabled until valid', (
    tester,
  ) async {
    final repository = _FakeComposeRepository();

    await tester.pumpWidget(_host(repository: repository));
    await tester.pumpAndSettle();

    expect(find.byType(ComposeTransactionPage), findsOneWidget);
    expect(find.textContaining('摘要'), findsAtLeastNWidgets(1));
    expect(find.textContaining('金额'), findsAtLeastNWidgets(1));
    expect(
      find.byKey(const Key('compose-primary-account-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('compose-counter-account-field')),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, '保存'), findsNothing);

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
    'expense submit treats left account as source and right account as destination',
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
      await tester.tap(find.text('Assets:Cash').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('compose-counter-account-field')),
      );
      await tester.tap(find.byKey(const Key('compose-counter-account-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Expenses:Food').last);
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
      expect(repository.appendedInputs, hasLength(1));
      expect(repository.appendedInputs.single.summary, 'Coffee');
      expect(repository.appendedInputs.single.postings.first.amount, isNull);
      expect(repository.appendedInputs.single.postings.first.commodity, isNull);
      expect(
        repository.appendedInputs.single.postings.first.account,
        'Assets:Cash',
      );
      expect(repository.appendedInputs.single.postings.last.amount, '18.50');
      expect(repository.appendedInputs.single.postings.last.commodity, 'CNY');
      expect(
        repository.appendedInputs.single.postings.last.account,
        'Expenses:Food',
      );
    },
  );

  testWidgets(
    'income submit treats left account as source and right account as destination',
    (tester) async {
      final repository = _FakeComposeRepository(
        accounts: const <AccountNode>[
          AccountNode(
            name: 'Income',
            subtitle: '活跃',
            balance: 'CNY 0',
            isPostable: false,
            children: <AccountNode>[
              AccountNode(name: 'Salary', subtitle: '活跃', balance: 'CNY 0'),
            ],
          ),
          AccountNode(
            name: 'Assets',
            subtitle: '活跃',
            balance: 'CNY 100',
            isPostable: false,
            children: <AccountNode>[
              AccountNode(name: 'Cash', subtitle: '活跃', balance: 'CNY 100'),
            ],
          ),
        ],
      );

      await tester.pumpWidget(_launchHost(repository: repository));
      await tester.pumpAndSettle();

      await tester.tap(find.text('打开记一笔'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('收入'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('compose-summary-field')),
        'Salary',
      );
      await tester.enterText(
        find.byKey(const Key('compose-amount-field')),
        '5000',
      );

      await tester.ensureVisible(
        find.byKey(const Key('compose-primary-account-field')),
      );
      await tester.tap(find.byKey(const Key('compose-primary-account-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Income:Salary').last);
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

      expect(repository.appendedInputs, hasLength(1));
      expect(
        repository.appendedInputs.single.postings.first.account,
        'Income:Salary',
      );
      expect(repository.appendedInputs.single.postings.first.amount, isNull);
      expect(repository.appendedInputs.single.postings.first.commodity, isNull);
      expect(
        repository.appendedInputs.single.postings.last.account,
        'Assets:Cash',
      );
      expect(repository.appendedInputs.single.postings.last.amount, '5000');
      expect(repository.appendedInputs.single.postings.last.commodity, 'CNY');
    },
  );

  testWidgets('simple submit can use a non-first operating currency', (
    tester,
  ) async {
    final repository = _FakeComposeRepository(
      ledger: _ledgerWithOperatingCurrencies(const ['CNY', 'USD']),
    );

    await tester.pumpWidget(_host(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('CNY').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('USD').last);
    await tester.pumpAndSettle();

    await _fillSimpleValidTransaction(tester);

    await tester.tap(find.byKey(const Key('compose-submit-button')));
    await tester.pumpAndSettle();

    expect(repository.appendedInputs.single.postings.last.commodity, 'USD');
  });

  testWidgets('preview button shows the current transaction text', (
    tester,
  ) async {
    final repository = _FakeComposeRepository();

    await tester.pumpWidget(_host(repository: repository));
    await tester.pumpAndSettle();

    await _fillSimpleValidTransaction(tester);

    await tester.tap(find.byKey(const Key('compose-preview-button')));
    await tester.pumpAndSettle();

    expect(find.text('交易预览'), findsOneWidget);
    expect(find.textContaining('* "Coffee"'), findsOneWidget);
    expect(find.textContaining('  Assets:Cash  -18.50 CNY'), findsOneWidget);
    expect(find.textContaining('  Expenses:Food  18.50 CNY'), findsOneWidget);
    expect(repository.appendedInputs, isEmpty);
  });

  testWidgets('preview button responds for an incomplete draft', (
    tester,
  ) async {
    final repository = _FakeComposeRepository();

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

    await tester.tap(find.byKey(const Key('compose-preview-button')));
    await tester.pumpAndSettle();

    expect(find.text('交易预览'), findsOneWidget);
    expect(find.textContaining('* "Coffee"'), findsOneWidget);
    expect(find.textContaining('18.50 CNY'), findsOneWidget);
  });

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
      await tester.tap(find.text('Assets:Cash').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('compose-counter-account-field')),
      );
      await tester.tap(find.byKey(const Key('compose-counter-account-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Expenses:Food').last);
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.byKey(const Key('compose-submit-button')),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('compose-submit-button')));
      await tester.pumpAndSettle();

      expect(find.byType(ComposeTransactionPage), findsOneWidget);
      expect(find.textContaining('Transaction 不平衡'), findsOneWidget);
    },
  );

  testWidgets('back is blocked while submit is in progress', (tester) async {
    final appendCompleter = Completer<void>();
    final repository = _FakeComposeRepository(appendCompleter: appendCompleter);

    await tester.pumpWidget(_launchHost(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('打开记一笔'));
    await tester.pumpAndSettle();

    await _fillSimpleValidTransaction(tester);
    await tester.tap(find.byKey(const Key('compose-submit-button')));
    await tester.pump();

    await tester.pageBack();
    await tester.pump();

    expect(find.text('放弃这次录入？'), findsNothing);
    expect(find.byType(ComposeTransactionPage), findsOneWidget);

    appendCompleter.complete();
    await tester.pumpAndSettle();

    expect(find.text('主页'), findsOneWidget);
  });

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
    expect(find.byType(ComposeTransactionPage), findsOneWidget);

    await tester.tap(find.text('保留内容'));
    await tester.pumpAndSettle();

    expect(find.byType(ComposeTransactionPage), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃'));
    await tester.pumpAndSettle();

    expect(find.text('主页'), findsOneWidget);
  });

  testWidgets(
    'amount-only draft asks for confirmation before leaving the page',
    (tester) async {
      final repository = _FakeComposeRepository();

      await tester.pumpWidget(_launchHost(repository: repository));
      await tester.pumpAndSettle();

      await tester.tap(find.text('打开记一笔'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('compose-amount-field')));
      await tester.enterText(
        find.byKey(const Key('compose-amount-field')),
        '18.50',
      );
      await tester.pump();

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('放弃这次录入？'), findsOneWidget);
      expect(find.byType(ComposeTransactionPage), findsOneWidget);
    },
  );

  testWidgets('tags links and metadata can be added and submitted', (
    tester,
  ) async {
    final repository = _FakeComposeRepository();

    await tester.pumpWidget(_host(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('扩展属性'));
    await tester.pumpAndSettle();

    await _tapVisibleAddIcon(tester, 0);
    expect(find.text('新建标签'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'travel shopping');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    expect(find.text('#travel'), findsOneWidget);
    expect(find.text('#shopping'), findsOneWidget);

    await _tapVisibleAddIcon(tester, 1);
    expect(find.text('新建链接'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField).last,
      'receipt-123 invoice-456',
    );
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    expect(find.text('^receipt-123'), findsOneWidget);
    expect(find.text('^invoice-456'), findsOneWidget);

    await _tapVisibleAddIcon(tester, 2);
    await tester.enterText(find.widgetWithText(TextField, 'Key'), 'location');
    await tester.enterText(find.widgetWithText(TextField, 'Value'), 'London');
    await _fillSimpleValidTransaction(tester);

    await tester.tap(find.byKey(const Key('compose-submit-button')));
    await tester.pumpAndSettle();

    final input = repository.appendedInputs.single;
    expect(input.tags, const ['travel', 'shopping']);
    expect(input.links, const ['receipt-123', 'invoice-456']);
    expect(input.metadata, const {'location': 'London'});
  });

  testWidgets('advanced mode requires at least one valid amount', (
    tester,
  ) async {
    final repository = _FakeComposeRepository();

    await tester.pumpWidget(_host(repository: repository));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('compose-summary-field')),
      'Split bill',
    );
    await tester.tap(find.text('专业'));
    await tester.pumpAndSettle();

    await _selectNextAdvancedAccount(tester, 0, 'Expenses:Food');
    await _selectNextAdvancedAccount(tester, 1, 'Assets:Cash');
    await _showSubmitButton(tester);

    expect(_saveButton(tester).onPressed, isNull);

    await tester.enterText(_advancedAmountField(0), '1e3');
    await tester.pumpAndSettle();
    expect(_saveButton(tester).onPressed, isNull);

    await tester.enterText(_advancedAmountField(0), '18.50');
    await tester.pumpAndSettle();
    expect(_saveButton(tester).onPressed, isNotNull);
  });

  testWidgets(
    'advanced submit does not seed quick-entry receipt or shortcuts',
    (tester) async {
      final repository = _FakeComposeRepository();

      await tester.pumpWidget(_launchHost(repository: repository));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.text('主页')),
      );

      await tester.tap(find.text('打开记一笔'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('compose-summary-field')),
        'Split bill',
      );
      await tester.tap(find.text('专业'));
      await tester.pumpAndSettle();

      await _selectNextAdvancedAccount(tester, 0, 'Expenses:Food');
      await _selectNextAdvancedAccount(tester, 1, 'Assets:Cash');
      await tester.enterText(_advancedAmountField(0), '18.50');
      await _showSubmitButton(tester);

      await tester.tap(find.byKey(const Key('compose-submit-button')));
      await tester.pumpAndSettle();

      final state = container.read(quickEntrySessionStateProvider);
      expect(find.text('主页'), findsOneWidget);
      expect(repository.appendedInputs, hasLength(1));
      expect(repository.appendedInputs.single.postings.first.commodity, 'CNY');
      expect(state.latestSavedTransaction, isNull);
      expect(state.recentAccountPairs, isEmpty);
    },
  );

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
      final container = ProviderScope.containerOf(
        tester.element(find.text('主页')),
      );

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
      await tester.tap(find.text('Assets:Cash').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('compose-counter-account-field')),
      );
      await tester.tap(find.byKey(const Key('compose-counter-account-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Expenses:Food').last);
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.byKey(const Key('compose-submit-button')),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('compose-submit-button')));
      await tester.pumpAndSettle();

      final state = container.read(quickEntrySessionStateProvider);
      expect(state.latestSavedTransaction?.amount, '18.50');
      expect(state.latestSavedTransaction?.commodity, 'CNY');
      expect(state.latestSavedTransaction?.primaryAccount, 'Assets:Cash');
      expect(state.latestSavedTransaction?.counterAccount, 'Expenses:Food');

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
          matching: find.text('Assets:Cash'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('compose-counter-account-field')),
          matching: find.text('Expenses:Food'),
        ),
        findsOneWidget,
      );

      await tester.ensureVisible(
        find.byKey(const Key('compose-primary-account-field')),
      );
      await tester.tap(find.byKey(const Key('compose-primary-account-field')));
      await tester.pumpAndSettle();

      expect(find.text('最近使用'), findsOneWidget);
      expect(find.text('Assets:Cash'), findsAtLeastNWidgets(1));
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

Future<void> _showSubmitButton(WidgetTester tester) async {
  await tester.dragUntilVisible(
    find.byKey(const Key('compose-submit-button')),
    find.byType(Scrollable).first,
    const Offset(0, -200),
  );
  await tester.pumpAndSettle();
}

Finder _advancedAmountField(int index) {
  return find.byType(TextField).at(index);
}

Future<void> _tapVisibleAddIcon(WidgetTester tester, int index) async {
  final finder = find.byIcon(Icons.add_circle_outline).at(index);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _selectNextAdvancedAccount(
  WidgetTester tester,
  int index,
  String account,
) async {
  final accountButton = find.byIcon(Icons.edit_outlined).at(index);
  await tester.ensureVisible(accountButton);
  await tester.pumpAndSettle();
  await tester.tap(accountButton);
  await tester.pumpAndSettle();
  await tester.tap(find.text(account).last);
  await tester.pumpAndSettle();
}

Future<void> _fillSimpleValidTransaction(WidgetTester tester) async {
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
  await tester.tap(find.text('Assets:Cash').last);
  await tester.pumpAndSettle();

  await tester.ensureVisible(
    find.byKey(const Key('compose-counter-account-field')),
  );
  await tester.tap(find.byKey(const Key('compose-counter-account-field')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Expenses:Food').last);
  await tester.pumpAndSettle();

  await _showSubmitButton(tester);
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
    this.appendCompleter,
    Ledger? ledger,
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
  }) : _ledger = ledger ?? _defaultLedger;

  final Object? appendError;
  final Completer<void>? appendCompleter;
  final Ledger _ledger;
  final List<AccountNode> accounts;
  final List<CreateTransactionInput> appendedInputs =
      <CreateTransactionInput>[];

  @override
  Future<void> appendTransaction(CreateTransactionInput input) async {
    if (appendError != null) {
      throw appendError!;
    }
    appendedInputs.add(input);
    await appendCompleter?.future;
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

Ledger _ledgerWithOperatingCurrencies(List<String> operatingCurrencies) {
  return Ledger(
    id: 'w-1',
    name: 'Household',
    rootPath: '/ledger/household',
    lastImportedAt: DateTime(2026, 4, 18, 9, 0),
    loadedFileCount: 2,
    status: LedgerStatus.ready,
    openAccountCount: 3,
    closedAccountCount: 1,
    operatingCurrencies: operatingCurrencies,
  );
}

final _defaultLedger = _ledgerWithOperatingCurrencies(const ['CNY']);

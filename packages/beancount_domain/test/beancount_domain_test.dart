import 'package:beancount_domain/beancount_domain.dart';
import 'package:test/test.dart';

void main() {
  test('exposes minimal stable beancount domain models', () {
    final workspace = Workspace(
      id: 'household',
      name: 'Household Ledger',
      rootPath: '/ledger',
      lastImportedAt: DateTime(2026, 4, 12, 9, 42),
      loadedFileCount: 12,
      status: WorkspaceStatus.ready,
      openAccountCount: 8,
      closedAccountCount: 2,
    );

    const issue = ValidationIssue(
      message: 'Unknown account',
      location: 'journal.beancount:12',
      blocking: true,
    );
    final transactionInput = CreateTransactionInput(
      date: DateTime(2026, 4, 19),
      summary: 'Coffee',
      amount: '18.50',
      commodity: 'CNY',
      primaryAccount: 'Expenses:Food',
      counterAccount: 'Assets:Cash',
    );
    const accountNode = AccountNode(
      name: 'Assets',
      subtitle: '活跃资产',
      balance: '¥ 0',
      isClosed: true,
      isPostable: false,
    );

    expect(workspace.name, 'Household Ledger');
    expect(workspace.openAccountCount, 8);
    expect(issue.blocking, isTrue);
    expect(transactionInput.primaryAccount, 'Expenses:Food');
    expect(accountNode.isClosed, isTrue);
    expect(accountNode.isPostable, isFalse);
    expect(JournalEntryType.values, contains(JournalEntryType.transaction));
  });
}

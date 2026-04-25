import 'package:beancount_domain/beancount_domain.dart';
import 'package:test/test.dart';

void main() {
  test('exposes minimal stable beancount domain models', () {
    final ledger = Ledger(
      id: 'household',
      name: 'Household Ledger',
      rootPath: '/ledger',
      lastImportedAt: DateTime(2026, 4, 12, 9, 42),
      loadedFileCount: 12,
      status: LedgerStatus.ready,
      openAccountCount: 8,
      closedAccountCount: 2,
      operatingCurrencies: const ['CNY'],
    );

    const issue = ValidationIssue(
      message: 'Unknown account',
      location: 'journal.beancount:12',
      blocking: true,
    );
    final transactionInput = CreateTransactionInput(
      date: DateTime(2026, 4, 19),
      summary: 'Coffee',
      postings: const [
        PostingInput(
          account: 'Expenses:Food',
          amount: '18.50',
          commodity: 'CNY',
        ),
        PostingInput(account: 'Assets:Cash'),
      ],
    );
    const accountNode = AccountNode(
      name: 'Assets',
      subtitle: '活跃资产',
      balance: '¥ 0',
      isClosed: true,
      isPostable: false,
    );

    expect(ledger.name, 'Household Ledger');
    expect(ledger.openAccountCount, 8);
    expect(issue.blocking, isTrue);
    expect(transactionInput.postings.first.account, 'Expenses:Food');
    expect(accountNode.isClosed, isTrue);
    expect(accountNode.isPostable, isFalse);
    expect(JournalEntryType.values, contains(JournalEntryType.transaction));
  });

  test(
    'serializes auto-balanced posting with explicit matching-scale amount',
    () {
      final text = serializeTransactionInput(
        CreateTransactionInput(
          date: DateTime(2026, 4, 19),
          summary: 'Coffee',
          postings: const [
            PostingInput(
              account: 'Expenses:Food',
              amount: '18.5',
              commodity: 'CNY',
            ),
            PostingInput(account: 'Assets:Cash'),
          ],
        ),
      );

      expect(
        text,
        '2026-04-19 * "Coffee"\n'
        '  Expenses:Food  18.5 CNY\n'
        '  Assets:Cash  -18.5 CNY\n',
      );
    },
  );
}

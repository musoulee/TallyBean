import 'package:beancount_bridge/beancount_bridge.dart';
import 'package:beancount_bridge/src/ledger/bridge_workspace_projector.dart';
import 'package:beancount_bridge/src/rust/api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('projects a normalized ledger snapshot into bridge DTOs', () {
    const projector = BridgeWorkspaceProjector();

    final result = projector.project(
      RustLedgerSnapshot(
        workspaceId: 'ledger',
        workspaceName: 'Household Ledger',
        loadedFileCount: 2,
        diagnostics: const <RustLedgerDiagnostic>[
          RustLedgerDiagnostic(
            message: '暂不支持 note 指令，已跳过',
            location: 'main.beancount:3',
            blocking: false,
          ),
        ],
        directives: <RustLedgerDirective>[
          RustLedgerDirective(
            kind: RustLedgerDirectiveKind.open,
            dateIso8601: '2026-04-01T00:00:00.000',
            sourceLocation: 'main.beancount:1',
            account: 'Assets:Cash',
            postings: const <RustPosting>[],
          ),
          RustLedgerDirective(
            kind: RustLedgerDirectiveKind.open,
            dateIso8601: '2026-04-01T00:00:00.000',
            sourceLocation: 'main.beancount:2',
            account: 'Income:Salary',
            postings: const <RustPosting>[],
          ),
          RustLedgerDirective(
            kind: RustLedgerDirectiveKind.transaction,
            dateIso8601: '2026-04-02T00:00:00.000',
            sourceLocation: 'journal.beancount:1',
            title: 'Salary',
            transactionFlag: RustTransactionFlag.cleared,
            postings: const <RustPosting>[
              RustPosting(
                account: 'Assets:Cash',
                amount: RustAmount(
                  value: 1000,
                  commodity: 'CNY',
                  fractionDigits: 0,
                ),
              ),
              RustPosting(
                account: 'Income:Salary',
                amount: RustAmount(
                  value: -1000,
                  commodity: 'CNY',
                  fractionDigits: 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    expect(result.workspaceId, 'ledger');
    expect(result.workspaceName, 'Household Ledger');
    expect(result.loadedFileCount, 2);
    expect(result.validationIssues, hasLength(1));
    expect(result.validationIssues.single.message, '暂不支持 note 指令，已跳过');

    expect(result.journalEntries, hasLength(3));
    expect(
      result.journalEntries.first.type,
      BridgeJournalEntryType.transaction,
    );
    expect(result.journalEntries.first.title, 'Salary');
    expect(result.journalEntries.first.amount?.commodity, 'CNY');
    expect(result.journalEntries.first.amount?.value, 1000);

    expect(result.accountNodes, hasLength(2));
    expect(result.accountNodes.first.name, 'Assets');
    expect(result.accountNodes.first.balance, 'CNY 1,000');
    expect(result.accountNodes.last.name, 'Income');
    expect(result.accountNodes.last.balance, '- CNY 1,000');

    expect(result.overview.netWorth, 'CNY 1,000');
    expect(result.overview.totalAssets, 'CNY 1,000');
    expect(result.overview.totalLiabilities, '--');
    expect(result.overview.changeDescription, '较上月 + CNY 1,000');
    expect(result.overview.weekTrend.balance, 1000);
    expect(result.overview.monthTrend.income, 1000);

    expect(result.reportResults, hasLength(1));
    expect(result.reportResults.single.key, 'income_expense');
    expect(result.reportResults.single.lines, <String>[
      '本周收入 ¥ 1,000',
      '本周支出 ¥ 0',
      '本周结余 ¥ 1,000',
    ]);
    expect(result.openAccountCount, 2);
    expect(result.closedAccountCount, 0);
  });
}

import 'package:beancount_bridge/beancount_bridge.dart';
import 'package:beancount_bridge/src/rust/api.dart';
import 'package:beancount_bridge/src/rust/rust_ledger_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'rust facade projects runtime snapshots and caches workspace results',
    () async {
      final runtime = _FakeRustLedgerRuntime();
      final bridge = RustBeancountBridgeFacade(runtime: runtime);

      final result = await bridge.parseWorkspace(
        '/ledger',
        '/ledger/main.beancount',
      );
      final issues = await bridge.validateWorkspace('ledger');
      final reports = await bridge.buildReports('ledger');

      expect(runtime.parseCalls, 1);
      expect(runtime.seenRootPath, '/ledger');
      expect(runtime.seenEntryFilePath, '/ledger/main.beancount');
      expect(result.workspaceId, 'ledger');
      expect(issues, hasLength(1));
      expect(issues.single.message, '暂不支持 note 指令，已跳过');
      expect(reports, hasLength(1));
      expect(reports.single.key, 'income_expense');
    },
  );
}

class _FakeRustLedgerRuntime implements RustLedgerRuntime {
  int parseCalls = 0;
  String? seenRootPath;
  String? seenEntryFilePath;

  @override
  Future<RustLedgerSnapshot> parseWorkspace({
    required String rootPath,
    required String entryFilePath,
  }) async {
    parseCalls += 1;
    seenRootPath = rootPath;
    seenEntryFilePath = entryFilePath;
    return RustLedgerSnapshot(
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
    );
  }
}

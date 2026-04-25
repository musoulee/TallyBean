import 'dart:io';

import 'package:beancount_bridge/beancount_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'rust facade parses included directives through the FRB runtime',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tally_bean_frb_bridge_test',
      );
      addTearDown(() => sandbox.delete(recursive: true));

      final root = Directory('${sandbox.path}/ledger');
      await root.create(recursive: true);

      await File('${root.path}/main.beancount').writeAsString(
        'include "journal.beancount"\n'
        '2026-04-01 open Assets:Cash CNY\n'
        '2026-04-01 open Income:Salary CNY\n',
      );
      await File('${root.path}/journal.beancount').writeAsString(
        '2026-04-02 * "Salary"\n'
        '  Assets:Cash  1000 CNY\n'
        '  Income:Salary\n',
      );

      final bridge = RustBeancountBridgeFacade();
      final result = await bridge.parseLedger(
        root.path,
        '${root.path}/main.beancount',
      );

      expect(result.ledgerId, 'ledger');
      expect(result.loadedFileCount, 2);
      expect(result.validationIssues, isEmpty);
      expect(
        result.journalEntries.map((entry) => entry.type),
        contains(BridgeJournalEntryType.transaction),
      );
    },
  );

  test('rust facade parses auto-balanced transactions with metadata', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'tally_bean_frb_metadata_test',
    );
    addTearDown(() => sandbox.delete(recursive: true));

    final root = Directory('${sandbox.path}/ledger');
    await root.create(recursive: true);

    await File('${root.path}/main.beancount').writeAsString(
      '2026-04-01 open Assets:Cash CNY\n'
      '2026-04-01 open Expenses:Food CNY\n'
      '2026-04-19 * "Coffee"\n'
      '  receipt/no: "123"\n'
      '  Expenses:Food  18.50 CNY\n'
      '  Assets:Cash\n',
    );

    final bridge = RustBeancountBridgeFacade();
    final result = await bridge.parseLedger(
      root.path,
      '${root.path}/main.beancount',
    );

    expect(result.validationIssues, isEmpty);
    expect(
      result.journalEntries.map((entry) => entry.type),
      contains(BridgeJournalEntryType.transaction),
    );
  });
}

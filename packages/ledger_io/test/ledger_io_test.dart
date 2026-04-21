import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_io/ledger_io.dart';

void main() {
  test('memory ledger io returns recent ledgers', () async {
    const facade = MemoryLedgerIoFacade();

    final recent = await facade.loadRecentLedgers();

    expect(recent.single.name, 'Household Ledger');
  });
}

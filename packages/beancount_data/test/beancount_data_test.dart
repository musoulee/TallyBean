import 'package:beancount_data/beancount_data.dart';
import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('demo repository exposes fixture-backed ledger data', () async {
    final repository = createDemoBeancountRepository();

    final ledger = await repository.loadCurrentLedger();
    final entries = await repository.loadJournalEntries();
    final reports = await repository.loadReportSummaries();

    expect(ledger, isNotNull);
    expect(ledger!.status, LedgerStatus.ready);
    expect(entries, isNotEmpty);
    expect(reports, isNotEmpty);
  });
}

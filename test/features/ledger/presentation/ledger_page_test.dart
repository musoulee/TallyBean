import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tally_bean/app/di/app_providers.dart';
import 'package:tally_bean/features/ledger/presentation/pages/ledger_page.dart';

void main() {
  testWidgets(
    'does not auto initialize default ledger when ledger loading fails',
    (tester) async {
      final repository = _FakeLedgerRepository(
        ledgerError: StateError('ledger boom'),
        recentLedgers: const <RecentLedger>[],
      );

      await tester.pumpWidget(_host(repository));
      await tester.pumpAndSettle();

      expect(find.text('账本加载失败'), findsOneWidget);
      expect(find.textContaining('ledger boom'), findsOneWidget);
      expect(repository.createDefaultCalls, 0);
    },
  );
}

Widget _host(BeancountRepository repository) {
  return ProviderScope(
    overrides: [beancountRepositoryProvider.overrideWithValue(repository)],
    child: const MaterialApp(home: LedgerPage()),
  );
}

class _FakeLedgerRepository implements BeancountRepository {
  _FakeLedgerRepository({this.ledgerError, required this.recentLedgers});

  final Object? ledgerError;
  final List<RecentLedger> recentLedgers;
  int createDefaultCalls = 0;

  @override
  Future<void> appendTransaction(CreateTransactionInput input) async {}

  @override
  Future<void> createDefaultLedger() async {
    createDefaultCalls += 1;
  }

  @override
  Future<void> importLedger(String sourcePath) async {}

  @override
  Future<void> renameLedger(String ledgerId, String newName) async {}

  @override
  Future<void> deleteLedger(String ledgerId) async {}

  @override
  Future<void> reopenLedger(String ledgerId) async {}

  @override
  Future<Ledger?> loadCurrentLedger() async {
    if (ledgerError != null) {
      throw ledgerError!;
    }
    return null;
  }

  @override
  Future<List<RecentLedger>> loadRecentLedgers() async {
    return recentLedgers;
  }

  @override
  Future<OverviewSnapshot> loadOverviewSnapshot() {
    throw UnimplementedError();
  }

  @override
  Future<List<JournalEntry>> loadJournalEntries() {
    throw UnimplementedError();
  }

  @override
  Future<List<AccountNode>> loadAccountTree() {
    throw UnimplementedError();
  }

  @override
  Future<Map<ReportCategory, List<ReportSummary>>> loadReportSummaries() {
    throw UnimplementedError();
  }

  @override
  Future<List<ValidationIssue>> loadValidationIssues() async {
    return const <ValidationIssue>[];
  }

  @override
  Future<List<LedgerTextFile>> loadCurrentLedgerFiles() async {
    return const <LedgerTextFile>[];
  }
}

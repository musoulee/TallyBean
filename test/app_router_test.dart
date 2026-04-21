import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tally_bean/app/bootstrap/app_bootstrap.dart';
import 'package:tally_bean/app/bootstrap/app_config.dart';
import 'package:tally_bean/app/di/package_registrations.dart';

void main() {
  testWidgets(
    'uses overview as initial route when local data mode is enabled',
    (tester) async {
      const config = AppConfig(useDemoData: false);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appConfigProvider.overrideWithValue(config),
            beancountRepositoryProvider.overrideWithValue(
              _NoLedgerRepository(),
            ),
          ],
          child: const AppBootstrap(config: config),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('还没有账本'), findsOneWidget);
      expect(find.text('账本一览'), findsNothing);
    },
  );
}

class _NoLedgerRepository implements BeancountRepository {
  @override
  Future<void> appendTransaction(CreateTransactionInput input) async {}

  @override
  Future<void> createDefaultLedger() async {}

  @override
  Future<void> importLedger(String sourcePath) async {}

  @override
  Future<List<AccountNode>> loadAccountTree() async => const <AccountNode>[];

  @override
  Future<Ledger?> loadCurrentLedger() async => null;

  @override
  Future<List<LedgerTextFile>> loadCurrentLedgerFiles() async =>
      const <LedgerTextFile>[];

  @override
  Future<List<JournalEntry>> loadJournalEntries() async =>
      const <JournalEntry>[];

  @override
  Future<OverviewSnapshot> loadOverviewSnapshot() async =>
      throw UnimplementedError();

  @override
  Future<List<RecentLedger>> loadRecentLedgers() async =>
      const <RecentLedger>[];

  @override
  Future<Map<ReportCategory, List<ReportSummary>>>
  loadReportSummaries() async => const <ReportCategory, List<ReportSummary>>{};

  @override
  Future<List<ValidationIssue>> loadValidationIssues() async =>
      const <ValidationIssue>[];

  @override
  Future<void> renameLedger(String ledgerId, String newName) async {}

  @override
  Future<void> deleteLedger(String ledgerId) async {}

  @override
  Future<void> reopenLedger(String ledgerId) async {}
}

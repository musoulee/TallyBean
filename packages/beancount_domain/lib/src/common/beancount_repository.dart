import '../accounts/account_node.dart';
import '../journal/journal_entry.dart';
import '../reports/report_summary.dart';
import '../transactions/create_transaction_input.dart';
import '../ledger/overview_snapshot.dart';
import '../ledger/recent_ledger.dart';
import '../ledger/ledger.dart';
import '../ledger/ledger_text_file.dart';
import 'report_category.dart';
import 'validation_issue.dart';

abstract interface class BeancountRepository {
  Future<void> appendTransaction(CreateTransactionInput input);
  Future<void> importLedger(String sourcePath);
  Future<void> createDefaultLedger();
  Future<void> renameLedger(String ledgerId, String newName);
  Future<void> deleteLedger(String ledgerId);
  Future<void> reopenLedger(String ledgerId);
  Future<Ledger?> loadCurrentLedger();
  Future<List<RecentLedger>> loadRecentLedgers();
  Future<OverviewSnapshot> loadOverviewSnapshot();
  Future<List<JournalEntry>> loadJournalEntries();
  Future<List<AccountNode>> loadAccountTree();
  Future<Map<ReportCategory, List<ReportSummary>>> loadReportSummaries();
  Future<List<ValidationIssue>> loadValidationIssues();
  Future<List<LedgerTextFile>> loadCurrentLedgerFiles();
}

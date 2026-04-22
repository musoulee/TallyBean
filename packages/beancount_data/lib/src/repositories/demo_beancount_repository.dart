import 'package:beancount_domain/beancount_domain.dart';
import 'package:ledger_io/ledger_io.dart';

import '../datasources/mock_beancount_datasource.dart';
import '../mappers/recent_ledger_mapper.dart';

class DemoBeancountRepository implements BeancountRepository {
  DemoBeancountRepository({
    required MockBeancountDatasource datasource,
    required LedgerIoFacade ledgerIo,
  }) : _datasource = datasource,
       _ledgerIo = ledgerIo;

  final MockBeancountDatasource _datasource;
  final LedgerIoFacade _ledgerIo;

  @override
  Future<void> appendTransaction(CreateTransactionInput input) {
    throw UnsupportedError('演示数据模式不支持保存交易');
  }

  @override
  Future<void> importLedger(String sourcePath) async {}

  @override
  Future<void> createDefaultLedger() async {}

  @override
  Future<void> deleteLedger(String ledgerId) async {
    await _ledgerIo.deleteLedger(ledgerId);
  }

  @override
  Future<List<AccountNode>> loadAccountTree() async {
    return _datasource.accountTree();
  }

  @override
  Future<Ledger?> loadCurrentLedger() async {
    return _datasource.ledger();
  }

  @override
  Future<List<JournalEntry>> loadJournalEntries() async {
    return _datasource.journalEntries();
  }

  @override
  Future<OverviewSnapshot> loadOverviewSnapshot() async {
    return _datasource.overviewSnapshot();
  }

  @override
  Future<List<RecentLedger>> loadRecentLedgers() async {
    final recent = await _ledgerIo.loadRecentLedgers();
    return recent.map(mapRecentLedgerRecord).toList();
  }

  @override
  Future<Map<ReportCategory, List<ReportSummary>>> loadReportSummaries() async {
    return _datasource.reportSummaries();
  }

  @override
  Future<List<ValidationIssue>> loadValidationIssues() async {
    return const <ValidationIssue>[];
  }

  @override
  Future<void> reopenLedger(String ledgerId) async {}

  @override
  Future<List<LedgerTextFile>> loadCurrentLedgerFiles() async {
    final current = await _ledgerIo.loadCurrentLedger();
    if (current == null) {
      return const <LedgerTextFile>[];
    }

    final files = await _ledgerIo.loadLedgerFiles(current.path);
    return files
        .map(
          (file) => LedgerTextFile(
            fileName: file.relativePath.split('/').last,
            relativePath: file.relativePath,
            content: file.content,
            sizeBytes: file.sizeBytes,
          ),
        )
        .toList();
  }
}

import 'package:beancount_domain/beancount_domain.dart';
import 'package:ledger_io/ledger_io.dart';

RecentLedger mapRecentLedgerRecord(RecentLedgerRecord record) {
  return RecentLedger(
    id: record.id,
    name: record.name,
    path: record.path,
    lastOpenedAt: record.lastOpenedAt,
  );
}

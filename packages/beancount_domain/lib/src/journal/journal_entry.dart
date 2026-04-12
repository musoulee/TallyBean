enum JournalEntryType { transaction, open, close, price, balance, event, pad }

enum TransactionFlag { cleared, pending }

enum EntryAmountDisplayStyle { prefix, suffix }

class EntryAmount {
  const EntryAmount({
    required this.value,
    required this.commodity,
    this.fractionDigits = 2,
    this.displayStyle = EntryAmountDisplayStyle.prefix,
  });

  final num value;
  final String commodity;
  final int fractionDigits;
  final EntryAmountDisplayStyle displayStyle;
}

class JournalEntry {
  const JournalEntry({
    required this.date,
    required this.type,
    required this.title,
    required this.primaryAccount,
    this.secondaryAccount,
    this.detail,
    this.amount,
    this.status,
    this.transactionFlag,
  });

  final DateTime date;
  final JournalEntryType type;
  final String title;
  final String primaryAccount;
  final String? secondaryAccount;
  final String? detail;
  final EntryAmount? amount;
  final String? status;
  final TransactionFlag? transactionFlag;
}

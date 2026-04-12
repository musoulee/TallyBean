import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter/material.dart';

String journalEntryMarker(JournalEntry entry) {
  if (entry.type == JournalEntryType.transaction) {
    return entry.transactionFlag == TransactionFlag.pending ? '!' : '*';
  }

  switch (entry.type) {
    case JournalEntryType.transaction:
      return '*';
    case JournalEntryType.open:
      return 'O';
    case JournalEntryType.close:
      return 'C';
    case JournalEntryType.price:
      return 'R';
    case JournalEntryType.balance:
      return 'B';
    case JournalEntryType.event:
      return 'E';
    case JournalEntryType.pad:
      return 'P';
  }
}

String journalEntrySubtitle(JournalEntry entry) {
  if (entry.type == JournalEntryType.transaction) {
    if (entry.secondaryAccount == null || entry.secondaryAccount!.isEmpty) {
      return entry.primaryAccount;
    }
    return '${entry.primaryAccount} / ${entry.secondaryAccount}';
  }

  return entry.detail ?? entry.primaryAccount;
}

String journalEntryTrailing(JournalEntry entry) {
  final amount = entry.amount;
  if (amount != null) {
    return formatEntryAmount(
      amount,
      includeSign: entry.type == JournalEntryType.transaction,
    );
  }

  return entry.status ?? '';
}

String formatEntryAmount(EntryAmount amount, {bool includeSign = false}) {
  final absoluteValue = amount.value.abs();
  final numberText = _formatNumericValue(absoluteValue, amount.fractionDigits);
  final baseText = amount.displayStyle == EntryAmountDisplayStyle.prefix
      ? '${amount.commodity} $numberText'
      : '$numberText ${amount.commodity}';

  if (!includeSign) {
    return baseText;
  }

  final sign = amount.value < 0 ? '-' : '+';
  return '$sign $baseText';
}

String _formatNumericValue(num value, int fractionDigits) {
  final fixed = value.toStringAsFixed(fractionDigits);
  final parts = fixed.split('.');
  final integerPart = _groupThousands(parts.first);

  if (fractionDigits == 0) {
    return integerPart;
  }

  return '$integerPart.${parts.last}';
}

String _groupThousands(String digits) {
  final buffer = StringBuffer();

  for (var index = 0; index < digits.length; index++) {
    final remaining = digits.length - index;
    buffer.write(digits[index]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(',');
    }
  }

  return buffer.toString();
}

Color journalEntryColor(JournalEntry entry) {
  if (entry.type == JournalEntryType.transaction &&
      entry.transactionFlag == TransactionFlag.pending) {
    return const Color(0xFFB7791F);
  }

  switch (entry.type) {
    case JournalEntryType.transaction:
      return const Color(0xFF2F6B4F);
    case JournalEntryType.open:
      return const Color(0xFF2B7A78);
    case JournalEntryType.close:
      return const Color(0xFF7A6252);
    case JournalEntryType.price:
      return const Color(0xFFA06A1C);
    case JournalEntryType.balance:
      return const Color(0xFF4C6583);
    case JournalEntryType.event:
      return const Color(0xFFA35D4F);
    case JournalEntryType.pad:
      return const Color(0xFF6E7C3A);
  }
}

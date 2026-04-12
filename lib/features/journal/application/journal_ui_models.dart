import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter/material.dart';

enum JournalFilter {
  all('全部', Color(0xFF8C6A3D), null),
  transaction('交易', Color(0xFF2F6B4F), JournalEntryType.transaction),
  open('开户', Color(0xFF2B7A78), JournalEntryType.open),
  close('闭户', Color(0xFF7A6252), JournalEntryType.close),
  price('价格', Color(0xFFA06A1C), JournalEntryType.price),
  balance('断言', Color(0xFF4C6583), JournalEntryType.balance);

  const JournalFilter(this.label, this.color, this.type);

  final String label;
  final Color color;
  final JournalEntryType? type;

  bool matches(JournalEntry entry) => type == null || entry.type == type;
}

import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class QuickEntrySaveReceipt {
  const QuickEntrySaveReceipt({
    required this.date,
    required this.summary,
    required this.amount,
    required this.commodity,
    required this.primaryAccount,
    required this.counterAccount,
    required this.submittedAt,
  });

  factory QuickEntrySaveReceipt.fromInput(
    CreateTransactionInput input, {
    required DateTime submittedAt,
  }) {
    final firstPosting = input.postings.isNotEmpty
        ? input.postings.first
        : null;
    final secondPosting = input.postings.length > 1 ? input.postings[1] : null;
    PostingInput? amountPosting;
    for (final posting in input.postings) {
      if ((posting.amount ?? '').isNotEmpty) {
        amountPosting = posting;
        break;
      }
    }

    return QuickEntrySaveReceipt(
      date: input.date,
      summary: input.summary,
      amount: amountPosting?.amount ?? '0',
      commodity: amountPosting?.commodity ?? '',
      primaryAccount: firstPosting?.account ?? '',
      counterAccount: secondPosting?.account ?? '',
      submittedAt: submittedAt,
    );
  }

  final DateTime date;
  final String summary;
  final String amount;
  final String commodity;
  final String primaryAccount;
  final String counterAccount;
  final DateTime submittedAt;

  String get pairLabel => '$primaryAccount / $counterAccount';

  String get amountLabel => '$commodity $amount';

  bool matches(JournalEntry entry) {
    final entryAmount = entry.amount;
    final parsedAmount = num.tryParse(amount);
    if (entry.type != JournalEntryType.transaction ||
        entryAmount == null ||
        parsedAmount == null) {
      return false;
    }

    return _isSameDate(entry.date, date) &&
        entry.title == summary &&
        entry.primaryAccount == primaryAccount &&
        entry.secondaryAccount == counterAccount &&
        entryAmount.commodity == commodity &&
        (entryAmount.value.abs() - parsedAmount).abs() < 0.000001;
  }

  static bool _isSameDate(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}

@immutable
class RecentAccountPair {
  const RecentAccountPair({
    required this.primaryAccount,
    required this.counterAccount,
  });

  final String primaryAccount;
  final String counterAccount;

  String get label => '$primaryAccount / $counterAccount';

  @override
  bool operator ==(Object other) {
    return other is RecentAccountPair &&
        other.primaryAccount == primaryAccount &&
        other.counterAccount == counterAccount;
  }

  @override
  int get hashCode => Object.hash(primaryAccount, counterAccount);
}

@immutable
class QuickEntrySessionState {
  const QuickEntrySessionState({
    this.latestSavedTransaction,
    this.recentAccountPairs = const <RecentAccountPair>[],
  });

  const QuickEntrySessionState.empty()
    : latestSavedTransaction = null,
      recentAccountPairs = const <RecentAccountPair>[];

  final QuickEntrySaveReceipt? latestSavedTransaction;
  final List<RecentAccountPair> recentAccountPairs;

  QuickEntrySessionState copyWith({
    QuickEntrySaveReceipt? latestSavedTransaction,
    List<RecentAccountPair>? recentAccountPairs,
  }) {
    return QuickEntrySessionState(
      latestSavedTransaction:
          latestSavedTransaction ?? this.latestSavedTransaction,
      recentAccountPairs: recentAccountPairs ?? this.recentAccountPairs,
    );
  }
}

final quickEntrySessionStateProvider = StateProvider<QuickEntrySessionState>((
  ref,
) {
  return const QuickEntrySessionState.empty();
});

final latestSavedTransactionProvider = Provider<QuickEntrySaveReceipt?>((ref) {
  return ref.watch(quickEntrySessionStateProvider).latestSavedTransaction;
});

final recentAccountPairsProvider = Provider<List<RecentAccountPair>>((ref) {
  return ref.watch(quickEntrySessionStateProvider).recentAccountPairs;
});

final recentPrimaryAccountsProvider = Provider<List<String>>((ref) {
  return _uniquePaths(
    ref
        .watch(recentAccountPairsProvider)
        .map((pair) => pair.primaryAccount)
        .toList(),
  );
});

final recentCounterAccountsProvider = Provider<List<String>>((ref) {
  return _uniquePaths(
    ref
        .watch(recentAccountPairsProvider)
        .map((pair) => pair.counterAccount)
        .toList(),
  );
});

final quickEntrySessionControllerProvider =
    Provider<QuickEntrySessionController>((ref) {
      return QuickEntrySessionController(ref);
    });

class QuickEntrySessionController {
  QuickEntrySessionController(this._ref);

  final Ref _ref;

  void recordSuccessfulSave(QuickEntrySaveReceipt receipt) {
    final current = _ref.read(quickEntrySessionStateProvider);
    final nextPairs = <RecentAccountPair>[
      RecentAccountPair(
        primaryAccount: receipt.primaryAccount,
        counterAccount: receipt.counterAccount,
      ),
      ...current.recentAccountPairs.where(
        (pair) =>
            pair.primaryAccount != receipt.primaryAccount ||
            pair.counterAccount != receipt.counterAccount,
      ),
    ].take(4).toList(growable: false);

    _ref.read(quickEntrySessionStateProvider.notifier).state = current.copyWith(
      latestSavedTransaction: receipt,
      recentAccountPairs: nextPairs,
    );
  }
}

List<String> _uniquePaths(List<String> values) {
  final unique = <String>[];
  for (final value in values) {
    if (!unique.contains(value)) {
      unique.add(value);
    }
  }
  return List<String>.unmodifiable(unique.take(4));
}

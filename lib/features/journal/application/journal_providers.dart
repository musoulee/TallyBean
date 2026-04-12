import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tally_bean/app/di/app_providers.dart';
import 'package:tally_bean/features/journal/application/journal_ui_models.dart';

final journalFilterProvider = StateProvider<JournalFilter>((ref) {
  return JournalFilter.all;
});

final journalEntriesProvider = FutureProvider<List<JournalEntry>>((ref) {
  return ref.watch(beancountRepositoryProvider).loadJournalEntries();
});

final filteredJournalEntriesProvider = Provider<AsyncValue<List<JournalEntry>>>(
  (ref) {
    final filter = ref.watch(journalFilterProvider);
    final entries = ref.watch(journalEntriesProvider);

    return entries.whenData(
      (items) => items.where((entry) => filter.matches(entry)).toList(),
    );
  },
);

import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/app_providers.dart';

final currentLedgerProvider = FutureProvider<Ledger?>((ref) {
  return ref.watch(beancountRepositoryProvider).loadCurrentLedger();
});

final recentLedgersProvider = FutureProvider<List<RecentLedger>>((ref) {
  return ref.watch(beancountRepositoryProvider).loadRecentLedgers();
});

final validationIssuesProvider = FutureProvider<List<ValidationIssue>>((ref) {
  return ref.watch(beancountRepositoryProvider).loadValidationIssues();
});

final ledgerTextFilesProvider = FutureProvider<List<LedgerTextFile>>((ref) {
  return ref.watch(beancountRepositoryProvider).loadCurrentLedgerFiles();
});

final ledgerActionControllerProvider =
    StateNotifierProvider<LedgerActionController, AsyncValue<void>>((ref) {
      return LedgerActionController(ref);
    });

class LedgerActionController extends StateNotifier<AsyncValue<void>> {
  LedgerActionController(this._ref) : super(const AsyncData(null));

  final Ref _ref;

  Future<void> importLedger(String sourcePath) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _ref.read(beancountRepositoryProvider).importLedger(sourcePath),
    );
    if (!state.hasError) {
      _invalidateLedgerState();
    }
  }

  Future<void> initializeDefaultLedger() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _ref.read(beancountRepositoryProvider).createDefaultLedger(),
    );
    if (!state.hasError) {
      _invalidateLedgerState();
    }
  }

  Future<void> reopenLedger(String ledgerId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _ref.read(beancountRepositoryProvider).reopenLedger(ledgerId),
    );
    if (!state.hasError) {
      _invalidateLedgerState();
    }
  }

  Future<void> renameLedger(String ledgerId, String newName) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _ref
          .read(beancountRepositoryProvider)
          .renameLedger(ledgerId, newName),
    );
    if (!state.hasError) {
      _invalidateLedgerState();
    }
  }

  Future<void> deleteLedger(String ledgerId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _ref.read(beancountRepositoryProvider).deleteLedger(ledgerId),
    );
    if (!state.hasError) {
      _invalidateLedgerState();
    }
  }

  void clearError() {
    state = const AsyncData(null);
  }

  void _invalidateLedgerState() {
    _ref.invalidate(currentLedgerProvider);
    _ref.invalidate(recentLedgersProvider);
    _ref.invalidate(validationIssuesProvider);
    _ref.invalidate(ledgerTextFilesProvider);
  }
}

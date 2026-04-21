import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tally_bean/app/session/quick_entry_session.dart';
import 'package:tally_bean/app/di/app_providers.dart';
import 'package:tally_bean/features/accounts/application/accounts_providers.dart';
import 'package:tally_bean/features/journal/application/journal_providers.dart';
import 'package:tally_bean/features/overview/application/overview_providers.dart';
import 'package:tally_bean/features/reports/application/reports_providers.dart';
import 'package:tally_bean/features/ledger/application/ledger_providers.dart';

final composeTransactionTitleProvider = Provider<String>((ref) {
  return '新建交易';
});

final composeTransactionAccountOptionsProvider =
    Provider<AsyncValue<List<ComposeAccountOption>>>((ref) {
      final accountTree = ref.watch(accountTreeProvider);
      return accountTree.whenData(_flattenAccountOptions);
    });

final composeTransactionActionControllerProvider =
    StateNotifierProvider<ComposeTransactionActionController, AsyncValue<void>>(
      (ref) {
        return ComposeTransactionActionController(ref);
      },
    );

class ComposeTransactionActionController
    extends StateNotifier<AsyncValue<void>> {
  ComposeTransactionActionController(this._ref) : super(const AsyncData(null));

  final Ref _ref;

  Future<QuickEntrySaveReceipt?> submit(CreateTransactionInput input) async {
    state = const AsyncLoading();
    final receipt = QuickEntrySaveReceipt.fromInput(
      input,
      submittedAt: DateTime.now(),
    );
    state = await AsyncValue.guard(
      () => _ref.read(beancountRepositoryProvider).appendTransaction(input),
    );
    if (state.hasError) {
      return null;
    }

    _ref
        .read(quickEntrySessionControllerProvider)
        .recordSuccessfulSave(receipt);
    _invalidateLedgerState();
    return receipt;
  }

  void clearError() {
    if (state.hasError) {
      state = const AsyncData(null);
    }
  }

  void _invalidateLedgerState() {
    _ref.invalidate(currentLedgerProvider);
    _ref.invalidate(validationIssuesProvider);
    _ref.invalidate(ledgerTextFilesProvider);
    _ref.invalidate(journalEntriesProvider);
    _ref.invalidate(accountTreeProvider);
    _ref.invalidate(overviewSnapshotProvider);
    _ref.invalidate(reportSummariesProvider);
    _ref.invalidate(composeTransactionAccountOptionsProvider);
  }
}

class ComposeAccountOption {
  const ComposeAccountOption({required this.fullPath});

  final String fullPath;
}

List<ComposeAccountOption> _flattenAccountOptions(List<AccountNode> nodes) {
  final options = <ComposeAccountOption>[];

  void visit(AccountNode node, List<String> ancestors) {
    if (node.isClosed) {
      return;
    }
    final pathSegments = <String>[...ancestors, node.name];
    if (node.isPostable) {
      options.add(ComposeAccountOption(fullPath: pathSegments.join(':')));
    }
    for (final child in node.children) {
      visit(child, pathSegments);
    }
  }

  for (final node in nodes) {
    visit(node, const <String>[]);
  }

  return List<ComposeAccountOption>.unmodifiable(options);
}

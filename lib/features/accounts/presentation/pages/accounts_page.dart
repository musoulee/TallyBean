import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tally_design_system/tally_design_system.dart';

import 'package:tally_bean/features/accounts/application/accounts_providers.dart';
import 'package:tally_bean/features/accounts/presentation/widgets/account_tree.dart';
import 'package:tally_bean/features/ledger/application/ledger_providers.dart';
import 'package:tally_bean/shared/widgets/async_error_view.dart';
import 'package:tally_bean/shared/widgets/async_loading_view.dart';
import 'package:tally_bean/shared/widgets/ledger_gate_view.dart';
import 'package:beancount_domain/beancount_domain.dart';

class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerState = ref.watch(currentLedgerProvider);
    final ledger = ledgerState.asData?.value;
    if (ledgerState.hasError && ledger == null) {
      return AsyncErrorView(
        error: ledgerState.error!,
        message: '账本加载失败',
        onRetry: () => ref.invalidate(currentLedgerProvider),
      );
    }
    if (ledgerState.isLoading) {
      return const AsyncLoadingView();
    }
    if (ledger == null) {
      return const LedgerGateView(title: '还没有账本', message: '导入账本后，账户树和余额才会显示。');
    }
    if (ledger.status == LedgerStatus.issuesFirst) {
      return const LedgerGateView(
        title: '账户页已锁定',
        message: '当前账本存在阻塞性问题，请先到账本页处理 issues。',
      );
    }

    final accountTree = ref.watch(accountTreeProvider);

    return accountTree.when(
      data: (nodes) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Row(
            children: [
              Expanded(
                child: TallyMetricCard(
                  label: '开放账户',
                  value: '${ledger.openAccountCount}',
                  accent: Color(0xFF4E6A40),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: TallyMetricCard(
                  label: '已关闭',
                  value: '${ledger.closedAccountCount}',
                  accent: Color(0xFF8C6A3D),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TallySectionCard(
            title: '账户树',
            child: AccountTree(nodes: nodes),
          ),
        ],
      ),
      loading: () => const AsyncLoadingView(),
      error: (error, _) => Center(child: Text('账户加载失败: $error')),
    );
  }
}

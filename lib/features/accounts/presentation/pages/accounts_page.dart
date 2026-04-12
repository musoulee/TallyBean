import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tally_design_system/tally_design_system.dart';

import 'package:tally_bean/features/accounts/application/accounts_providers.dart';
import 'package:tally_bean/features/accounts/presentation/widgets/account_tree.dart';
import 'package:tally_bean/shared/widgets/async_loading_view.dart';

class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountTree = ref.watch(accountTreeProvider);

    return accountTree.when(
      data: (nodes) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          const Row(
            children: [
              Expanded(
                child: TallyMetricCard(
                  label: '开放账户',
                  value: '42',
                  accent: Color(0xFF4E6A40),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: TallyMetricCard(
                  label: '已关闭',
                  value: '8',
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tally_design_system/tally_design_system.dart';

import 'package:tally_bean/features/accounts/application/accounts_providers.dart';
import 'package:tally_bean/features/accounts/presentation/widgets/account_tree.dart';
import 'package:tally_bean/features/workspace/application/workspace_providers.dart';
import 'package:tally_bean/shared/widgets/async_error_view.dart';
import 'package:tally_bean/shared/widgets/async_loading_view.dart';
import 'package:tally_bean/shared/widgets/workspace_gate_view.dart';
import 'package:beancount_domain/beancount_domain.dart';

class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaceState = ref.watch(currentWorkspaceProvider);
    final workspace = workspaceState.asData?.value;
    if (workspaceState.hasError && workspace == null) {
      return AsyncErrorView(
        error: workspaceState.error!,
        message: '工作区加载失败',
        onRetry: () => ref.invalidate(currentWorkspaceProvider),
      );
    }
    if (workspaceState.isLoading) {
      return const AsyncLoadingView();
    }
    if (workspace == null) {
      return const WorkspaceGateView(
        title: '还没有账本',
        message: '导入工作区后，账户树和余额才会显示。',
      );
    }
    if (workspace.status == WorkspaceStatus.issuesFirst) {
      return const WorkspaceGateView(
        title: '账户页已锁定',
        message: '当前账本存在阻塞性问题，请先到工作区处理 issues。',
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
                  value: '${workspace.openAccountCount}',
                  accent: Color(0xFF4E6A40),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: TallyMetricCard(
                  label: '已关闭',
                  value: '${workspace.closedAccountCount}',
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

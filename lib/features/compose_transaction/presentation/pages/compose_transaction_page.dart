import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tally_design_system/tally_design_system.dart';

import 'package:tally_bean/features/compose_transaction/application/compose_transaction_providers.dart';
import 'package:tally_bean/features/workspace/application/workspace_providers.dart';
import 'package:tally_bean/shared/widgets/async_error_view.dart';
import 'package:tally_bean/shared/widgets/workspace_gate_view.dart';
import 'package:beancount_domain/beancount_domain.dart';

class ComposeTransactionPage extends ConsumerWidget {
  const ComposeTransactionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaceState = ref.watch(currentWorkspaceProvider);
    final workspace = workspaceState.asData?.value;
    final title = ref.watch(composeTransactionTitleProvider);

    if (workspaceState.hasError && workspace == null) {
      return Scaffold(
        body: AsyncErrorView(
          error: workspaceState.error!,
          message: '工作区加载失败',
          onRetry: () => ref.invalidate(currentWorkspaceProvider),
        ),
      );
    }
    if (workspaceState.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (workspace == null) {
      return const Scaffold(
        body: WorkspaceGateView(title: '还没有账本', message: '导入工作区后才能开始录入交易。'),
      );
    }
    if (workspace.status == WorkspaceStatus.issuesFirst) {
      return const Scaffold(
        body: WorkspaceGateView(
          title: '录入已锁定',
          message: '当前账本存在阻塞性问题，请先前往工作区处理 issues。',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          TallySectionCard(
            title: '交易草稿',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('这里将承接新增/编辑交易的表单、草稿和保存流程。'),
                SizedBox(height: 8),
                Text('第一阶段保持结构骨架，后续再接真实录入能力。'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

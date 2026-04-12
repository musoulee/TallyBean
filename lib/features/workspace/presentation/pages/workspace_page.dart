import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tally_design_system/tally_design_system.dart';

import 'package:tally_bean/features/workspace/application/workspace_providers.dart';
import 'package:tally_bean/shared/formatters/date_label_formatter.dart';
import 'package:tally_bean/shared/widgets/async_loading_view.dart';

class WorkspacePage extends ConsumerWidget {
  const WorkspacePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(currentWorkspaceProvider);
    final recent = ref.watch(recentWorkspacesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('工作区')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          workspace.when(
            data: (data) => TallySectionCard(
              title: '当前工作区',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('账本名称  ${data.name}'),
                  const SizedBox(height: 8),
                  Text('路径  ${data.rootPath}'),
                  const SizedBox(height: 8),
                  Text('最后导入  ${formatDateLabel(data.lastImportedAt)}'),
                  const SizedBox(height: 8),
                  Text('数据状态  已加载 ${data.loadedFileCount} 个文件'),
                ],
              ),
            ),
            loading: () =>
                const SizedBox(height: 160, child: AsyncLoadingView()),
            error: (error, _) =>
                TallySectionCard(title: '当前工作区', child: Text('加载失败: $error')),
          ),
          const SizedBox(height: 16),
          recent.when(
            data: (items) => TallySectionCard(
              title: '最近工作区',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: items
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text('${item.name} · ${item.path}'),
                      ),
                    )
                    .toList(),
              ),
            ),
            loading: () =>
                const SizedBox(height: 160, child: AsyncLoadingView()),
            error: (error, _) =>
                TallySectionCard(title: '最近工作区', child: Text('加载失败: $error')),
          ),
        ],
      ),
    );
  }
}

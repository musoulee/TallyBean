import 'package:file_picker/file_picker.dart';
import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tally_design_system/tally_design_system.dart';

import 'package:tally_bean/app/router/route_names.dart';
import 'package:tally_bean/features/workspace/application/workspace_providers.dart';
import 'package:tally_bean/features/workspace/presentation/pages/workspace_file_picker_policy.dart';
import 'package:tally_bean/shared/formatters/date_label_formatter.dart';
import 'package:tally_bean/shared/widgets/async_loading_view.dart';

class WorkspacePage extends ConsumerWidget {
  const WorkspacePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(currentWorkspaceProvider);
    final recent = ref.watch(recentWorkspacesProvider);
    final issues = ref.watch(validationIssuesProvider);
    final actionState = ref.watch(workspaceActionControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('工作区')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (actionState.isLoading) const LinearProgressIndicator(),
          if (actionState.hasError) ...[
            TallySectionCard(
              title: '操作失败',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${actionState.error}'),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: () {
                      ref
                          .read(workspaceActionControllerProvider.notifier)
                          .clearError();
                    },
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          workspace.when(
            data: (data) => data == null
                ? _EmptyWorkspaceCard(
                    onImport: () => _pickAndImportWorkspace(context, ref),
                  )
                : _CurrentWorkspaceCard(
                    name: data.name,
                    path: data.rootPath,
                    lastImportedAt: data.lastImportedAt,
                    loadedFileCount: data.loadedFileCount,
                    issuesFirst: data.status == WorkspaceStatus.issuesFirst,
                    onOpenOverview: () =>
                        context.go(AppRouteNames.overviewPath),
                    onReimport: () => _pickAndImportWorkspace(context, ref),
                  ),
            loading: () =>
                const SizedBox(height: 180, child: AsyncLoadingView()),
            error: (error, _) => Column(
              children: [
                _EmptyWorkspaceCard(
                  onImport: () => _pickAndImportWorkspace(context, ref),
                ),
                const SizedBox(height: 16),
                TallySectionCard(title: '工作区加载失败', child: Text('$error')),
              ],
            ),
          ),
          const SizedBox(height: 16),
          issues.when(
            data: (items) {
              if (items.isEmpty) {
                return const SizedBox.shrink();
              }

              return TallySectionCard(
                title: '账本问题',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: items
                      .map(
                        (issue) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                issue.blocking
                                    ? Icons.error_outline_rounded
                                    : Icons.info_outline_rounded,
                                size: 18,
                                color: issue.blocking
                                    ? Theme.of(context).colorScheme.error
                                    : Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(issue.message),
                                    const SizedBox(height: 2),
                                    Text(
                                      issue.location,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),
          recent.when(
            data: (items) => TallySectionCard(
              title: '最近工作区',
              child: items.isEmpty
                  ? const Text('还没有最近打开的账本')
                  : Column(
                      children: items
                          .map(
                            (item) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(item.name),
                              subtitle: Text(
                                '${item.path}\n最后打开 ${formatDateLabel(item.lastOpenedAt)}',
                              ),
                              isThreeLine: true,
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () async {
                                await ref
                                    .read(
                                      workspaceActionControllerProvider
                                          .notifier,
                                    )
                                    .reopenWorkspace(item.id);
                              },
                            ),
                          )
                          .toList(),
                    ),
            ),
            loading: () =>
                const SizedBox(height: 120, child: AsyncLoadingView()),
            error: (error, _) =>
                TallySectionCard(title: '最近工作区', child: Text('加载失败: $error')),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndImportWorkspace(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final platform = Theme.of(context).platform;
    final result = await FilePicker.platform.pickFiles(
      type: workspaceImportPickerType(platform),
      allowedExtensions: workspaceImportAllowedExtensions(platform),
      allowMultiple: false,
      dialogTitle: '选择主 beancount 文件',
    );

    final selectedPath = result?.files.single.path;
    if (selectedPath == null || !context.mounted) {
      return;
    }
    if (!isBeancountEntryFilePath(selectedPath)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请选择一个 .beancount 文件')));
      return;
    }

    await ref
        .read(workspaceActionControllerProvider.notifier)
        .importWorkspace(selectedPath);
  }
}

class _EmptyWorkspaceCard extends StatelessWidget {
  const _EmptyWorkspaceCard({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return TallySectionCard(
      title: '未打开账本',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('选择一个主 .beancount 文件，应用会复制其所在目录到私有工作区。'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.file_open_rounded),
            label: const Text('导入账本'),
          ),
        ],
      ),
    );
  }
}

class _CurrentWorkspaceCard extends StatelessWidget {
  const _CurrentWorkspaceCard({
    required this.name,
    required this.path,
    required this.lastImportedAt,
    required this.loadedFileCount,
    required this.issuesFirst,
    required this.onOpenOverview,
    required this.onReimport,
  });

  final String name;
  final String path;
  final DateTime lastImportedAt;
  final int loadedFileCount;
  final bool issuesFirst;
  final VoidCallback onOpenOverview;
  final VoidCallback onReimport;

  @override
  Widget build(BuildContext context) {
    return TallySectionCard(
      title: '当前工作区',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('账本名称  $name'),
          const SizedBox(height: 8),
          Text('路径  $path'),
          const SizedBox(height: 8),
          Text('最后导入  ${formatDateLabel(lastImportedAt)}'),
          const SizedBox(height: 8),
          Text('数据状态  已加载 $loadedFileCount 个文件'),
          if (issuesFirst) ...[
            const SizedBox(height: 8),
            Text(
              '当前账本存在阻塞性问题，已进入 issues-first 模式。',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!issuesFirst)
                FilledButton.tonal(
                  onPressed: onOpenOverview,
                  child: const Text('进入账本'),
                ),
              OutlinedButton.icon(
                onPressed: onReimport,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重新导入'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

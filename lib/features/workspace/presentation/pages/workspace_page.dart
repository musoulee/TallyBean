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
      appBar: AppBar(title: const Text('账本一览')),
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

          // 统一账本列表
          _buildUnifiedLedgerList(context, ref, workspace, recent),

          const SizedBox(height: 16),

          // 账本问题
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

          // 底部操作区
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => ref
                      .read(workspaceActionControllerProvider.notifier)
                      .initializeDefaultWorkspace(),
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('生成默认账本'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _pickAndImportWorkspace(context, ref),
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('导入账本'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUnifiedLedgerList(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<Workspace?> workspace,
    AsyncValue<List<RecentWorkspace>> recent,
  ) {
    // 加载中
    if (workspace.isLoading && !workspace.hasValue) {
      return const SizedBox(height: 180, child: AsyncLoadingView());
    }

    // 首次启动无数据触发初始化
    final currentData = workspace.valueOrNull;
    final recentItems = recent.valueOrNull ?? [];

    if (currentData == null && recentItems.isEmpty) {
      return const _InitializingWorkspaceCard();
    }

    return TallySectionCard(
      title: '所有账本',
      child: Column(
        children: [
          // 当前账本（高亮）
          if (currentData != null)
            Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 3,
                  ),
                ),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.only(left: 12),
                title: Row(
                  children: [
                    Flexible(
                      child: Text(
                        currentData.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '当前',
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  '最后操作 ${formatDateLabel(currentData.lastImportedAt)} · ${currentData.loadedFileCount} 个文件',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: '管理账本',
                  onPressed: () => _showManageSheet(
                    context,
                    ref,
                    currentData,
                  ),
                ),
                onTap: currentData.status == WorkspaceStatus.issuesFirst
                    ? null
                    : () => context.go(AppRouteNames.overviewPath),
              ),
            ),

          // 历史账本
          ...recentItems
              .where((item) => item.id != currentData?.id)
              .map(
                (item) => Column(
                  children: [
                    const Divider(height: 1),
                    ListTile(
                      contentPadding: const EdgeInsets.only(left: 16),
                      title: Text(item.name),
                      subtitle: Text(
                        '最后打开 ${formatDateLabel(item.lastOpenedAt)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            tooltip: '编辑账本名称',
                            onPressed: () => _showRenameSheet(
                              context,
                              ref,
                              item.id,
                              item.name,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.download_outlined, size: 20),
                            tooltip: '加载此账本',
                            onPressed: () => _showLoadConfirmSheet(
                              context,
                              ref,
                              item,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Future<void> _showManageSheet(
    BuildContext context,
    WidgetRef ref,
    Workspace workspace,
  ) async {
    final textController = TextEditingController(text: workspace.name);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('管理账本', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                controller: textController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '账本名称',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  final newName = textController.text.trim();
                  Navigator.pop(ctx);
                  if (newName.isNotEmpty && newName != workspace.name) {
                    await ref
                        .read(workspaceActionControllerProvider.notifier)
                        .renameWorkspace(workspace.id, newName);
                  }
                },
                child: const Text('保存名称'),
              ),
              const SizedBox(height: 8),
              if (workspace.status != WorkspaceStatus.issuesFirst)
                FilledButton.tonal(
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.go(AppRouteNames.overviewPath);
                  },
                  child: const Text('进入账本'),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _pickAndImportWorkspace(context, ref);
                },
                icon: const Icon(Icons.refresh_outlined),
                label: const Text('重新导入'),
              ),
            ],
          ),
        );
      },
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
      ).showSnackBar(const SnackBar(content: Text('请选择一个 .beancount 或 .bean 文件')));
      return;
    }

    await ref
        .read(workspaceActionControllerProvider.notifier)
        .importWorkspace(selectedPath);
  }

  Future<void> _showRenameSheet(
    BuildContext context,
    WidgetRef ref,
    String workspaceId,
    String currentName,
  ) async {
    final textController = TextEditingController(text: currentName);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('编辑账本名称', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                controller: textController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '账本名称',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  final newName = textController.text.trim();
                  Navigator.pop(ctx);
                  if (newName.isNotEmpty && newName != currentName) {
                    await ref
                        .read(workspaceActionControllerProvider.notifier)
                        .renameWorkspace(workspaceId, newName);
                  }
                },
                child: const Text('保存'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showLoadConfirmSheet(
    BuildContext context,
    WidgetRef ref,
    RecentWorkspace item,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('加载确认', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 16),
                Text('您即将切换到账本「${item.name}」，当前账本将被挂起。'),
                const SizedBox(height: 8),
                Text(
                  '路径: ${item.path}',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    ref
                        .read(workspaceActionControllerProvider.notifier)
                        .reopenWorkspace(item.id);
                  },
                  child: const Text('确认加载'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InitializingWorkspaceCard extends ConsumerStatefulWidget {
  const _InitializingWorkspaceCard();

  @override
  ConsumerState<_InitializingWorkspaceCard> createState() =>
      _InitializingWorkspaceCardState();
}

class _InitializingWorkspaceCardState
    extends ConsumerState<_InitializingWorkspaceCard> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        ref
            .read(workspaceActionControllerProvider.notifier)
            .initializeDefaultWorkspace();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const TallySectionCard(
      title: '为您配置专属账本...',
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 32.0),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在生成初始化账户与结构'),
            ],
          ),
        ),
      ),
    );
  }
}

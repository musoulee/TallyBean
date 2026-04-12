import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tally_design_system/tally_design_system.dart';

import 'package:tally_bean/app/router/route_names.dart';
import 'package:tally_bean/features/settings/application/settings_providers.dart';
import 'package:tally_bean/features/workspace/application/workspace_providers.dart';
import 'package:tally_bean/shared/formatters/date_label_formatter.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(currentWorkspaceProvider);
    final density = ref.watch(settingsDensityProvider);
    final currency = ref.watch(settingsBaseCurrencyProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        workspace.when(
          data: (data) => TallySectionCard(
            title: '当前工作区',
            child: InkWell(
              onTap: () => context.push(AppRouteNames.workspacePath),
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
          ),
          loading: () =>
              const TallySectionCard(title: '当前工作区', child: Text('工作区加载中')),
          error: (error, _) =>
              TallySectionCard(title: '当前工作区', child: Text('工作区加载失败: $error')),
        ),
        const SizedBox(height: 16),
        const TallySectionCard(
          title: '高级工具',
          child: Column(
            children: [
              TallySettingsItem(
                icon: Icons.repeat_on_outlined,
                title: '周期记账',
                subtitle: '管理模板和固定周期分录',
              ),
              Divider(height: 24),
              TallySettingsItem(
                icon: Icons.import_export_outlined,
                title: '数据导入导出',
                subtitle: '导入账本目录或导出当前工作区',
              ),
              Divider(height: 24),
              TallySettingsItem(
                icon: Icons.code_outlined,
                title: '纯文本编辑',
                subtitle: '直接查看或编辑 beancount 文本',
              ),
              Divider(height: 24),
              TallySettingsItem(
                icon: Icons.account_tree_outlined,
                title: '版本控制',
                subtitle: '查看变更、提交记录和分支状态',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TallySectionCard(
          title: '通用偏好',
          child: Column(
            children: [
              TallySettingsItem(
                icon: Icons.space_dashboard_outlined,
                title: '显示密度',
                subtitle: density,
              ),
              const Divider(height: 24),
              TallySettingsItem(
                icon: Icons.currency_exchange_outlined,
                title: '默认基准货币',
                subtitle: currency,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

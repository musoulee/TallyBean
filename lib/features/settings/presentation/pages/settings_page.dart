import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tally_design_system/tally_design_system.dart';

import 'package:tally_bean/app/router/route_names.dart';
import 'package:tally_bean/features/settings/application/settings_providers.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final density = ref.watch(settingsDensityProvider);
    final currency = ref.watch(settingsBaseCurrencyProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        TallySectionCard(
          title: '账本管理',
          child: Column(
            children: [
              InkWell(
                onTap: () => context.push(AppRouteNames.workspacePath),
                child: const TallySettingsItem(
                  icon: Icons.menu_book_outlined,
                  title: '账本一览',
                  subtitle: '查看、切换、重命名、导入导出账本',
                ),
              ),
              const Divider(height: 24),
              InkWell(
                onTap: () => context.push(AppRouteNames.textViewPath),
                child: const TallySettingsItem(
                  icon: Icons.description_outlined,
                  title: '文本视图',
                  subtitle: '查看当前账本的 beancount 源文件',
                ),
              ),
            ],
          ),
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

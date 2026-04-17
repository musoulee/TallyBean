import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/workspace/application/workspace_providers.dart';
import 'app_fab_controller.dart';
import 'bottom_nav_shell.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(currentWorkspaceProvider).asData?.value;
    final showFab =
        workspace != null && workspace.status == WorkspaceStatus.ready;

    return Scaffold(
      body: SafeArea(bottom: false, child: navigationShell),
      floatingActionButton: showFab
          ? FloatingActionButton.extended(
              onPressed: () => context.push(composeTransactionFab.routePath),
              label: Text(composeTransactionFab.label),
              icon: Icon(composeTransactionFab.icon),
            )
          : null,
      bottomNavigationBar: BottomNavShell(navigationShell: navigationShell),
    );
  }
}

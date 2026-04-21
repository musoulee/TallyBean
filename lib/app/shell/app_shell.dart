import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/ledger/application/ledger_providers.dart';
import 'app_fab_controller.dart';
import 'bottom_nav_shell.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(currentLedgerProvider).asData?.value;
    final showFab = ledger != null && ledger.status == LedgerStatus.ready;

    return Scaffold(
      body: SafeArea(bottom: false, child: navigationShell),
      floatingActionButton: showFab
          ? FloatingActionButton(
              onPressed: () => context.push(composeTransactionFab.routePath),
              tooltip: composeTransactionFab.label,
              child: Icon(composeTransactionFab.icon),
            )
          : null,
      bottomNavigationBar: BottomNavShell(navigationShell: navigationShell),
    );
  }
}

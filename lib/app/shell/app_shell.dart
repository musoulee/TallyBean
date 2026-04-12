import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_fab_controller.dart';
import 'bottom_nav_shell.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(bottom: false, child: navigationShell),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(composeTransactionFab.routePath),
        label: Text(composeTransactionFab.label),
        icon: Icon(composeTransactionFab.icon),
      ),
      bottomNavigationBar: BottomNavShell(navigationShell: navigationShell),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class BottomNavShell extends StatelessWidget {
  const BottomNavShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: navigationShell.currentIndex,
      type: BottomNavigationBarType.fixed,
      onTap: (index) {
        navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        );
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: '首页'),
        BottomNavigationBarItem(
          icon: Icon(Icons.receipt_long_outlined),
          label: '明细',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.account_tree_outlined),
          label: '账户',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.bar_chart_outlined),
          label: '统计',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings_outlined),
          label: '设置',
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../router/route_names.dart';

class AppFabController {
  const AppFabController({
    required this.label,
    required this.icon,
    required this.routePath,
  });

  final String label;
  final IconData icon;
  final String routePath;
}

const composeTransactionFab = AppFabController(
  label: '记一笔',
  icon: Icons.add,
  routePath: AppRouteNames.composeTransactionPath,
);

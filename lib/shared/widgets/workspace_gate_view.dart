import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/route_names.dart';

class WorkspaceGateView extends StatelessWidget {
  const WorkspaceGateView({
    super.key,
    required this.title,
    required this.message,
    this.buttonLabel = '前往工作区',
  });

  final String title;
  final String message;
  final String buttonLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () => context.go(AppRouteNames.workspacePath),
              child: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}

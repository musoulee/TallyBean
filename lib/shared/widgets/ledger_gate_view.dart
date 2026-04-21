import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/route_names.dart';

class LedgerGateView extends StatelessWidget {
  const LedgerGateView({
    super.key,
    required this.title,
    required this.message,
    this.buttonLabel = '前往账本页',
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
              onPressed: () => context.go(AppRouteNames.ledgerPath),
              child: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}

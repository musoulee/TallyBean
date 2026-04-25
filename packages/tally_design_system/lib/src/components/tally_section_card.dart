import 'package:flutter/material.dart';

class TallySectionCard extends StatelessWidget {
  const TallySectionCard({
    super.key,
    this.title,
    required this.child,
    this.trailing,
  });

  final String? title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null || trailing != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (title != null)
                    Expanded(
                      child: Text(title!, style: theme.textTheme.titleMedium),
                    )
                  else
                    const Spacer(),
                  if (title != null && trailing != null)
                    const SizedBox(width: 8),
                  // ignore: use_null_aware_elements
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

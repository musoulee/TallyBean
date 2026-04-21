import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tally_bean/features/ledger/application/ledger_providers.dart';
import 'package:tally_bean/shared/widgets/async_error_view.dart';
import 'package:tally_bean/shared/widgets/async_loading_view.dart';
import 'package:tally_bean/shared/widgets/ledger_gate_view.dart';

class TextViewPage extends ConsumerWidget {
  const TextViewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerState = ref.watch(currentLedgerProvider);
    final ledger = ledgerState.asData?.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('文本视图'),
        actions: const [
          Padding(padding: EdgeInsets.only(right: 12), child: _ReadOnlyBadge()),
        ],
      ),
      body: _buildBody(context, ref, ledgerState, ledger),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<Ledger?> ledgerState,
    Ledger? ledger,
  ) {
    if (ledgerState.hasError && ledger == null) {
      return AsyncErrorView(
        error: ledgerState.error!,
        message: '账本加载失败',
        onRetry: () => ref.invalidate(currentLedgerProvider),
      );
    }

    if (ledgerState.isLoading && ledger == null) {
      return const AsyncLoadingView();
    }

    if (ledger == null) {
      return const LedgerGateView(
        title: '还没有账本',
        message: '导入账本后，文本视图才会显示 beancount 源文件。',
      );
    }

    final filesState = ref.watch(ledgerTextFilesProvider);
    return filesState.when(
      data: (files) {
        if (files.isEmpty) {
          return const LedgerGateView(
            title: '没有可显示的账本文件',
            message: '当前账本未找到 .bean 或 .beancount 文件。',
          );
        }

        if (files.length == 1) {
          return _FilePane(file: files.first);
        }

        return DefaultTabController(
          length: files.length,
          child: Column(
            children: [
              Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: files
                      .map((file) => Tab(text: file.fileName))
                      .toList(growable: false),
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: files
                      .map((file) => _FilePane(file: file))
                      .toList(growable: false),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const AsyncLoadingView(),
      error: (error, _) => AsyncErrorView(
        error: error,
        message: '文本加载失败',
        onRetry: () => ref.invalidate(ledgerTextFilesProvider),
      ),
    );
  }
}

class _ReadOnlyBadge extends StatelessWidget {
  const _ReadOnlyBadge();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '只读',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colors.onSecondaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _FilePane extends StatelessWidget {
  const _FilePane({required this.file});

  final LedgerTextFile file;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _FileBanner(file: file),
        Expanded(child: _BeancountCodeView(content: file.content)),
      ],
    );
  }
}

class _FileBanner extends StatelessWidget {
  const _FileBanner({required this.file});

  final LedgerTextFile file;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Row(
        children: [
          const Icon(Icons.description_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.fileName,
                  style: Theme.of(context).textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
                if (file.relativePath != file.fileName)
                  Text(
                    file.relativePath,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _formatBytes(file.sizeBytes),
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}

class _BeancountCodeView extends StatelessWidget {
  const _BeancountCodeView({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final lines = content.split('\n');
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final codeStyle = textTheme.bodyMedium?.copyWith(
      fontFamily: 'monospace',
      height: 1.35,
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: colorScheme.surfaceContainerLowest,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: lines.length,
        itemBuilder: (context, index) {
          final line = lines[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 36,
                  child: Text(
                    '${index + 1}',
                    textAlign: TextAlign.right,
                    style: textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    _highlightLine(
                      line: line,
                      baseStyle: codeStyle,
                      colorScheme: colorScheme,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

TextSpan _highlightLine({
  required String line,
  required TextStyle? baseStyle,
  required ColorScheme colorScheme,
}) {
  if (line.isEmpty) {
    return TextSpan(text: ' ', style: baseStyle);
  }

  final patterns = <_HighlightPattern>[
    _HighlightPattern(
      regex: RegExp(r'^;.*$'),
      style: TextStyle(color: colorScheme.tertiary),
    ),
    _HighlightPattern(
      regex: RegExp(r'^\d{4}-\d{2}-\d{2}'),
      style: TextStyle(color: colorScheme.primary),
    ),
    _HighlightPattern(
      regex: RegExp(r'\b(option|open|close|balance|price|note|event)\b'),
      style: TextStyle(
        color: colorScheme.secondary,
        fontWeight: FontWeight.w600,
      ),
    ),
    _HighlightPattern(
      regex: RegExp(
        r'\b(Assets|Liabilities|Equity|Income|Expenses)(:[A-Z][A-Za-z0-9-]*)+\b',
      ),
      style: TextStyle(color: colorScheme.primary),
    ),
    _HighlightPattern(
      regex: RegExp(r'"[^"]*"'),
      style: TextStyle(color: colorScheme.tertiary),
    ),
  ];

  final matches = <_HighlightSegment>[];
  for (final pattern in patterns) {
    for (final match in pattern.regex.allMatches(line)) {
      matches.add(
        _HighlightSegment(
          start: match.start,
          end: match.end,
          style: pattern.style,
        ),
      );
    }
  }
  matches.sort((left, right) {
    if (left.start != right.start) {
      return left.start.compareTo(right.start);
    }
    return right.end.compareTo(left.end);
  });

  var cursor = 0;
  final spans = <InlineSpan>[];
  for (final match in matches) {
    if (match.start < cursor) {
      continue;
    }
    if (match.start > cursor) {
      spans.add(
        TextSpan(text: line.substring(cursor, match.start), style: baseStyle),
      );
    }
    spans.add(
      TextSpan(
        text: line.substring(match.start, match.end),
        style: baseStyle?.merge(match.style) ?? match.style,
      ),
    );
    cursor = match.end;
  }

  if (cursor < line.length) {
    spans.add(TextSpan(text: line.substring(cursor), style: baseStyle));
  }

  return TextSpan(children: spans, style: baseStyle);
}

String _formatBytes(int sizeBytes) {
  if (sizeBytes < 1024) {
    return '$sizeBytes B';
  }
  final kiloBytes = sizeBytes / 1024;
  if (kiloBytes < 1024) {
    return '${kiloBytes.toStringAsFixed(1)} KB';
  }
  final megaBytes = kiloBytes / 1024;
  return '${megaBytes.toStringAsFixed(1)} MB';
}

class _HighlightPattern {
  const _HighlightPattern({required this.regex, required this.style});

  final RegExp regex;
  final TextStyle style;
}

class _HighlightSegment {
  const _HighlightSegment({
    required this.start,
    required this.end,
    required this.style,
  });

  final int start;
  final int end;
  final TextStyle style;
}

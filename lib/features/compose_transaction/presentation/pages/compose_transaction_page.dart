import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tally_design_system/tally_design_system.dart';

import 'package:tally_bean/features/compose_transaction/application/compose_transaction_providers.dart';

class ComposeTransactionPage extends ConsumerWidget {
  const ComposeTransactionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = ref.watch(composeTransactionTitleProvider);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          TallySectionCard(
            title: '交易草稿',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('这里将承接新增/编辑交易的表单、草稿和保存流程。'),
                SizedBox(height: 8),
                Text('第一阶段保持结构骨架，后续再接真实录入能力。'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

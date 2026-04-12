import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter/material.dart';

class AccountTree extends StatelessWidget {
  const AccountTree({super.key, required this.nodes});

  final List<AccountNode> nodes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: Column(
        children: nodes.map((node) => _AccountTreeNode(node: node)).toList(),
      ),
    );
  }
}

class _AccountTreeNode extends StatelessWidget {
  const _AccountTreeNode({required this.node});

  final AccountNode node;

  @override
  Widget build(BuildContext context) {
    if (node.children.isEmpty) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(node.name),
        subtitle: Text(node.subtitle),
        trailing: Text(node.balance),
      );
    }

    return ExpansionTile(
      initiallyExpanded: true,
      tilePadding: EdgeInsets.zero,
      title: Text(node.name),
      subtitle: Text(node.subtitle),
      trailing: Text(node.balance),
      childrenPadding: const EdgeInsets.only(left: 12),
      children: node.children
          .map((child) => _AccountTreeNode(node: child))
          .toList(),
    );
  }
}

class AccountNode {
  const AccountNode({
    required this.name,
    required this.subtitle,
    required this.balance,
    this.children = const <AccountNode>[],
  });

  final String name;
  final String subtitle;
  final String balance;
  final List<AccountNode> children;
}

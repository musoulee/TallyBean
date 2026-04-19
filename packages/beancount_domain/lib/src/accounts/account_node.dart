class AccountNode {
  const AccountNode({
    required this.name,
    required this.subtitle,
    required this.balance,
    this.isClosed = false,
    this.isPostable = true,
    this.children = const <AccountNode>[],
  });

  final String name;
  final String subtitle;
  final String balance;
  final bool isClosed;
  final bool isPostable;
  final List<AccountNode> children;
}

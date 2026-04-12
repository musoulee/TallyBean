class RecentWorkspace {
  const RecentWorkspace({
    required this.id,
    required this.name,
    required this.path,
    required this.lastOpenedAt,
  });

  final String id;
  final String name;
  final String path;
  final DateTime lastOpenedAt;
}

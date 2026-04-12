import 'package:beancount_domain/beancount_domain.dart';
import 'package:workspace_io/workspace_io.dart';

RecentWorkspace mapRecentWorkspaceRecord(RecentWorkspaceRecord record) {
  return RecentWorkspace(
    id: record.id,
    name: record.name,
    path: record.path,
    lastOpenedAt: record.lastOpenedAt,
  );
}

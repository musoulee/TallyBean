import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/app_providers.dart';

final currentWorkspaceProvider = FutureProvider<Workspace>((ref) {
  return ref.watch(beancountRepositoryProvider).loadCurrentWorkspace();
});

final recentWorkspacesProvider = FutureProvider<List<RecentWorkspace>>((ref) {
  return ref.watch(beancountRepositoryProvider).loadRecentWorkspaces();
});

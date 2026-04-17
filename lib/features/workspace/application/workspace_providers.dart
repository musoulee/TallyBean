import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/app_providers.dart';

final currentWorkspaceProvider = FutureProvider<Workspace?>((ref) {
  return ref.watch(beancountRepositoryProvider).loadCurrentWorkspace();
});

final recentWorkspacesProvider = FutureProvider<List<RecentWorkspace>>((ref) {
  return ref.watch(beancountRepositoryProvider).loadRecentWorkspaces();
});

final validationIssuesProvider = FutureProvider<List<ValidationIssue>>((ref) {
  return ref.watch(beancountRepositoryProvider).loadValidationIssues();
});

final workspaceActionControllerProvider =
    StateNotifierProvider<WorkspaceActionController, AsyncValue<void>>((ref) {
      return WorkspaceActionController(ref);
    });

class WorkspaceActionController extends StateNotifier<AsyncValue<void>> {
  WorkspaceActionController(this._ref) : super(const AsyncData(null));

  final Ref _ref;

  Future<void> importWorkspace(String sourcePath) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _ref.read(beancountRepositoryProvider).importWorkspace(sourcePath),
    );
    if (!state.hasError) {
      _invalidateWorkspaceState();
    }
  }

  Future<void> reopenWorkspace(String workspaceId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _ref.read(beancountRepositoryProvider).reopenWorkspace(workspaceId),
    );
    if (!state.hasError) {
      _invalidateWorkspaceState();
    }
  }

  void clearError() {
    state = const AsyncData(null);
  }

  void _invalidateWorkspaceState() {
    _ref.invalidate(currentWorkspaceProvider);
    _ref.invalidate(recentWorkspacesProvider);
    _ref.invalidate(validationIssuesProvider);
  }
}

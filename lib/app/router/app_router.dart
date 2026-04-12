import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:tally_bean/app/router/route_names.dart';
import 'package:tally_bean/app/shell/app_shell.dart';
import 'package:tally_bean/features/accounts/presentation/pages/accounts_page.dart';
import 'package:tally_bean/features/compose_transaction/presentation/pages/compose_transaction_page.dart';
import 'package:tally_bean/features/journal/presentation/pages/journal_page.dart';
import 'package:tally_bean/features/overview/presentation/pages/overview_page.dart';
import 'package:tally_bean/features/reports/presentation/pages/reports_page.dart';
import 'package:tally_bean/features/settings/presentation/pages/settings_page.dart';
import 'package:tally_bean/features/workspace/presentation/pages/workspace_page.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRouteNames.overviewPath,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRouteNames.overviewPath,
                name: AppRouteNames.overview,
                builder: (context, state) => const OverviewPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRouteNames.journalPath,
                name: AppRouteNames.journal,
                builder: (context, state) => const JournalPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRouteNames.accountsPath,
                name: AppRouteNames.accounts,
                builder: (context, state) => const AccountsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRouteNames.reportsPath,
                name: AppRouteNames.reports,
                builder: (context, state) => const ReportsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRouteNames.settingsPath,
                name: AppRouteNames.settings,
                builder: (context, state) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRouteNames.workspacePath,
        name: AppRouteNames.workspace,
        builder: (context, state) => const WorkspacePage(),
      ),
      GoRoute(
        path: AppRouteNames.composeTransactionPath,
        name: AppRouteNames.composeTransaction,
        builder: (context, state) => const ComposeTransactionPage(),
      ),
    ],
  );
});

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../router/app_router.dart';
import '../theme/app_theme_adapter.dart';
import 'app_config.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.config = defaultAppConfig});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(child: AppBootstrap(config: config));
  }
}

class AppBootstrap extends ConsumerWidget {
  const AppBootstrap({super.key, required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: config.title,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: router,
    );
  }
}

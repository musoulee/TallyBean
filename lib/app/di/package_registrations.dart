import 'package:beancount_data/beancount_data.dart';
import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bootstrap/app_config.dart';

final appConfigProvider = Provider<AppConfig>((ref) => defaultAppConfig);

final beancountRepositoryProvider = Provider<BeancountRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  return config.useDemoData
      ? createDemoBeancountRepository()
      : createLocalBeancountRepository();
});

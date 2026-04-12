import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tally_bean/app/di/app_providers.dart';

final accountTreeProvider = FutureProvider<List<AccountNode>>((ref) {
  return ref.watch(beancountRepositoryProvider).loadAccountTree();
});

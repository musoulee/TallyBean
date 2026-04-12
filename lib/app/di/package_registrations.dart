import 'package:beancount_data/beancount_data.dart';
import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final beancountRepositoryProvider = Provider<BeancountRepository>((ref) {
  return createDemoBeancountRepository();
});

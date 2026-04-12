import 'package:flutter_riverpod/flutter_riverpod.dart';

final settingsDensityProvider = Provider<String>((ref) {
  return '标准';
});

final settingsBaseCurrencyProvider = Provider<String>((ref) {
  return 'CNY';
});

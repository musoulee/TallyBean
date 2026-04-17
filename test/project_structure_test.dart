import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('monorepo skeleton and local package entrypoints exist', () {
    const expectedPaths = [
      'melos.yaml',
      'integration_test',
      'packages/tally_design_system/pubspec.yaml',
      'packages/tally_design_system/lib/tally_design_system.dart',
      'packages/beancount_domain/pubspec.yaml',
      'packages/beancount_domain/lib/beancount_domain.dart',
      'packages/beancount_data/pubspec.yaml',
      'packages/beancount_data/lib/beancount_data.dart',
      'packages/workspace_io/pubspec.yaml',
      'packages/workspace_io/lib/workspace_io.dart',
      'packages/beancount_bridge/pubspec.yaml',
      'packages/beancount_bridge/lib/beancount_bridge.dart',
      'lib/app/bootstrap/app_bootstrap.dart',
      'lib/app/router/app_router.dart',
      'lib/app/shell/app_shell.dart',
      'lib/app/di/app_providers.dart',
      'lib/features/journal/presentation/pages/journal_page.dart',
      'lib/features/compose_transaction/presentation/pages/compose_transaction_page.dart',
      'lib/features/workspace/presentation/pages/workspace_page.dart',
    ];

    for (final path in expectedPaths) {
      expect(
        FileSystemEntity.typeSync(path),
        isNot(FileSystemEntityType.notFound),
        reason: path,
      );
    }
  });

  test('root pubspec wires path packages and product dependencies', () {
    const pubspecPath = 'pubspec.yaml';
    final pubspec = File(pubspecPath).readAsStringSync();

    expect(pubspec, contains('go_router:'));
    expect(pubspec, contains('flutter_riverpod:'));
    expect(pubspec, contains('riverpod_annotation:'));
    expect(pubspec, contains('freezed_annotation:'));
    expect(pubspec, contains('tally_design_system:'));
    expect(pubspec, contains('beancount_domain:'));
    expect(pubspec, contains('beancount_data:'));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workspace_io/workspace_io.dart';

void main() {
  test(
    'importWorkspace copies the selected ledger into app storage and persists current/recent workspace state',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tally_bean_workspace_io_test',
      );
      addTearDown(() => sandbox.delete(recursive: true));

      final sourceRoot = Directory('${sandbox.path}/source/household');
      await sourceRoot.create(recursive: true);

      final mainFile = File('${sourceRoot.path}/main.beancount');
      await mainFile.writeAsString('2026-04-01 open Assets:Cash CNY\n');

      final supportRoot = Directory('${sandbox.path}/app-support');
      final facade = LocalWorkspaceIoFacade(appSupportPath: supportRoot.path);

      final summary = await facade.importWorkspace(mainFile.path);
      final current = await facade.loadCurrentWorkspace();
      final recent = await facade.loadRecentWorkspaces();

      expect(summary.workspaceId, isNotEmpty);
      expect(current, isNotNull);
      expect(current!.id, summary.workspaceId);
      expect(current.path.startsWith(supportRoot.path), isTrue);
      expect(current.entryFilePath, '${current.path}/main.beancount');
      expect(File(current.entryFilePath).existsSync(), isTrue);
      expect(recent, hasLength(1));
      expect(recent.single.id, current.id);
      expect(recent.single.path, current.path);

      final reopenedFacade = LocalWorkspaceIoFacade(
        appSupportPath: supportRoot.path,
      );
      final reopenedCurrent = await reopenedFacade.loadCurrentWorkspace();
      final reopenedRecent = await reopenedFacade.loadRecentWorkspaces();

      expect(reopenedCurrent?.id, current.id);
      expect(reopenedCurrent?.path, current.path);
      expect(reopenedRecent, hasLength(1));
      expect(reopenedRecent.single.id, current.id);
    },
  );

  test(
    'importWorkspace keeps ledgers with identical folder names as separate workspaces',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tally_bean_workspace_io_test',
      );
      addTearDown(() => sandbox.delete(recursive: true));

      final sourceRootA = Directory('${sandbox.path}/source_a/household');
      final sourceRootB = Directory('${sandbox.path}/source_b/household');
      await sourceRootA.create(recursive: true);
      await sourceRootB.create(recursive: true);

      final mainA = File('${sourceRootA.path}/main.beancount');
      final mainB = File('${sourceRootB.path}/main.beancount');
      await mainA.writeAsString('2026-04-01 open Assets:Cash CNY\n');
      await mainB.writeAsString('2026-04-01 open Assets:Bank CNY\n');

      final supportRoot = Directory('${sandbox.path}/app-support');
      final facade = LocalWorkspaceIoFacade(appSupportPath: supportRoot.path);

      final summaryA = await facade.importWorkspace(mainA.path);
      final summaryB = await facade.importWorkspace(mainB.path);
      final recent = await facade.loadRecentWorkspaces();

      expect(summaryA.workspaceId, isNot(summaryB.workspaceId));
      expect(summaryA.path, isNot(summaryB.path));
      expect(Directory(summaryA.path).existsSync(), isTrue);
      expect(Directory(summaryB.path).existsSync(), isTrue);
      expect(recent, hasLength(2));
      expect(
        recent.map((record) => record.id),
        containsAll([summaryA.workspaceId, summaryB.workspaceId]),
      );
    },
  );
}

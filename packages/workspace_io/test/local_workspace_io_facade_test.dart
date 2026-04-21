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

  test(
    'importWorkspace rejects re-importing an already imported ledger path',
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

      await facade.importWorkspace(mainFile.path);

      await expectLater(
        facade.importWorkspace(mainFile.path),
        throwsA(
          isA<FileSystemException>().having(
            (error) => error.message,
            'message',
            contains('该账本已经导入'),
          ),
        ),
      );
    },
  );

  test(
    'loadWorkspaceFiles recursively loads only .bean/.beancount files with deterministic relative paths',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tally_bean_workspace_io_test',
      );
      addTearDown(() => sandbox.delete(recursive: true));

      final sourceRoot = Directory('${sandbox.path}/source/household');
      final nested = Directory('${sourceRoot.path}/sub');
      await nested.create(recursive: true);

      final mainFile = File('${sourceRoot.path}/main.beancount');
      final nestedBean = File('${nested.path}/2026.bean');
      final ignore = File('${sourceRoot.path}/notes.txt');
      await mainFile.writeAsString('option "title" "Household"\n');
      await nestedBean.writeAsString('2026-04-01 open Assets:Cash CNY\n');
      await ignore.writeAsString('not a beancount file');

      final supportRoot = Directory('${sandbox.path}/app-support');
      final facade = LocalWorkspaceIoFacade(appSupportPath: supportRoot.path);

      await facade.importWorkspace(mainFile.path);
      final current = await facade.loadCurrentWorkspace();
      final files = await facade.loadWorkspaceFiles(current!.path);

      expect(files.map((item) => item.relativePath), <String>[
        'main.beancount',
        'sub/2026.bean',
      ]);
      expect(files.first.content, 'option "title" "Household"\n');
      expect(files.first.sizeBytes, greaterThan(0));
      expect(files.last.content, '2026-04-01 open Assets:Cash CNY\n');
    },
  );

  test(
    'renameWorkspace remains compatible with legacy metadata filename',
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

      await facade.importWorkspace(mainFile.path);
      final current = await facade.loadCurrentWorkspace();
      expect(current, isNotNull);

      final jsonMetadataFile = File(
        '${current!.path}/.tally_bean_workspace.json',
      );
      final legacyMetadataFile = File('${current.path}/.tally_bean_workspace');

      await legacyMetadataFile.writeAsString(
        await jsonMetadataFile.readAsString(),
      );
      await jsonMetadataFile.delete();

      await facade.renameWorkspace(current.id, 'Renamed Ledger');
      final renamed = await facade.loadCurrentWorkspace();

      expect(renamed?.name, 'Renamed Ledger');
      expect(legacyMetadataFile.existsSync(), isTrue);
    },
  );

  test(
    'deleteWorkspace removes workspace files and updates current/recent state',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tally_bean_workspace_io_test',
      );
      addTearDown(() => sandbox.delete(recursive: true));

      final sourceRootA = Directory('${sandbox.path}/source_a/household');
      final sourceRootB = Directory('${sandbox.path}/source_b/archives');
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
      expect((await facade.loadCurrentWorkspace())?.id, summaryB.workspaceId);

      await facade.deleteWorkspace(summaryB.workspaceId);
      expect(Directory(summaryB.path).existsSync(), isFalse);
      expect((await facade.loadCurrentWorkspace())?.id, summaryA.workspaceId);
      expect(
        (await facade.loadRecentWorkspaces()).map((item) => item.id),
        <String>[summaryA.workspaceId],
      );

      await facade.deleteWorkspace(summaryA.workspaceId);
      expect(Directory(summaryA.path).existsSync(), isFalse);
      expect(await facade.loadCurrentWorkspace(), isNull);
      expect(await facade.loadRecentWorkspaces(), isEmpty);
    },
  );

  test(
    'createDefaultWorkspace is idempotent and does not overwrite existing ledger files',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tally_bean_workspace_io_test',
      );
      addTearDown(() => sandbox.delete(recursive: true));

      final supportRoot = Directory('${sandbox.path}/app-support');
      final facade = LocalWorkspaceIoFacade(appSupportPath: supportRoot.path);

      final first = await facade.createDefaultWorkspace();
      final entryFile = File(first.entryFilePath);
      expect(entryFile.existsSync(), isTrue);

      await entryFile.writeAsString('option "title" "custom"\n');
      final extraLedgerFile = File('${first.path}/archives/2026.bean');
      await extraLedgerFile.parent.create(recursive: true);
      await extraLedgerFile.writeAsString('2026-04-01 open Assets:Cash CNY\n');

      final second = await facade.createDefaultWorkspace();
      final secondEntry = File(second.entryFilePath);

      expect(second.workspaceId, first.workspaceId);
      expect(second.path, first.path);
      expect(await secondEntry.readAsString(), 'option "title" "custom"\n');
      expect(extraLedgerFile.existsSync(), isTrue);
      expect(second.fileCount, greaterThanOrEqualTo(2));
    },
  );

  test(
    'writeFileContent overwrites ledger file content for save and rollback flows',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tally_bean_workspace_io_test',
      );
      addTearDown(() => sandbox.delete(recursive: true));

      final sourceRoot = Directory('${sandbox.path}/source/household');
      await sourceRoot.create(recursive: true);

      final mainFile = File('${sourceRoot.path}/main.beancount');
      await mainFile.writeAsString('option "title" "Household"\n');

      final supportRoot = Directory('${sandbox.path}/app-support');
      final facade = LocalWorkspaceIoFacade(appSupportPath: supportRoot.path);

      await facade.importWorkspace(mainFile.path);
      final current = await facade.loadCurrentWorkspace();
      expect(current, isNotNull);

      await facade.writeFileContent(
        current!.entryFilePath,
        '2026-04-19 * "Lunch"\n  Expenses:Food  32 CNY\n  Assets:Cash\n',
      );
      expect(
        await File(current.entryFilePath).readAsString(),
        '2026-04-19 * "Lunch"\n  Expenses:Food  32 CNY\n  Assets:Cash\n',
      );

      await facade.writeFileContent(
        current.entryFilePath,
        'option "title" "Household"\n',
      );
      expect(
        await File(current.entryFilePath).readAsString(),
        'option "title" "Household"\n',
      );
    },
  );
}

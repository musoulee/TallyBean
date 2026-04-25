import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_io/ledger_io.dart';

void main() {
  test(
    'importLedger copies the selected ledger into app storage and persists current/recent ledger state',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tally_bean_ledger_io_test',
      );
      addTearDown(() => sandbox.delete(recursive: true));

      final sourceRoot = Directory('${sandbox.path}/source/household');
      await sourceRoot.create(recursive: true);

      final mainFile = File('${sourceRoot.path}/main.beancount');
      await mainFile.writeAsString('2026-04-01 open Assets:Cash CNY\n');

      final supportRoot = Directory('${sandbox.path}/app-support');
      final facade = LocalLedgerIoFacade(appSupportPath: supportRoot.path);

      final summary = await facade.importLedger(mainFile.path);
      final current = await facade.loadCurrentLedger();
      final recent = await facade.loadRecentLedgers();

      expect(summary.ledgerId, isNotEmpty);
      expect(current, isNotNull);
      expect(current!.id, summary.ledgerId);
      expect(current.path.startsWith(supportRoot.path), isTrue);
      expect(current.entryFilePath, '${current.path}/main.beancount');
      expect(File(current.entryFilePath).existsSync(), isTrue);
      expect(recent, hasLength(1));
      expect(recent.single.id, current.id);
      expect(recent.single.path, current.path);

      final reopenedFacade = LocalLedgerIoFacade(
        appSupportPath: supportRoot.path,
      );
      final reopenedCurrent = await reopenedFacade.loadCurrentLedger();
      final reopenedRecent = await reopenedFacade.loadRecentLedgers();

      expect(reopenedCurrent?.id, current.id);
      expect(reopenedCurrent?.path, current.path);
      expect(reopenedRecent, hasLength(1));
      expect(reopenedRecent.single.id, current.id);
    },
  );

  test(
    'importLedger keeps ledgers with identical folder names as separate ledgers',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tally_bean_ledger_io_test',
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
      final facade = LocalLedgerIoFacade(appSupportPath: supportRoot.path);

      final summaryA = await facade.importLedger(mainA.path);
      final summaryB = await facade.importLedger(mainB.path);
      final recent = await facade.loadRecentLedgers();

      expect(summaryA.ledgerId, isNot(summaryB.ledgerId));
      expect(summaryA.path, isNot(summaryB.path));
      expect(Directory(summaryA.path).existsSync(), isTrue);
      expect(Directory(summaryB.path).existsSync(), isTrue);
      expect(recent, hasLength(2));
      expect(
        recent.map((record) => record.id),
        containsAll([summaryA.ledgerId, summaryB.ledgerId]),
      );
    },
  );

  test(
    'importLedger refreshes an already imported ledger path in place',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tally_bean_ledger_io_test',
      );
      addTearDown(() => sandbox.delete(recursive: true));

      final sourceRoot = Directory('${sandbox.path}/source/household');
      await sourceRoot.create(recursive: true);

      final mainFile = File('${sourceRoot.path}/main.beancount');
      await mainFile.writeAsString('2026-04-01 open Assets:Cash CNY\n');

      final supportRoot = Directory('${sandbox.path}/app-support');
      final facade = LocalLedgerIoFacade(appSupportPath: supportRoot.path);

      final firstImport = await facade.importLedger(mainFile.path);
      expect(
        await File('${firstImport.path}/main.beancount').readAsString(),
        '2026-04-01 open Assets:Cash CNY\n',
      );

      await mainFile.writeAsString(
        'option "title" "Household Reloaded"\n'
        '2026-04-02 open Assets:Bank CNY\n',
      );

      final secondImport = await facade.importLedger(mainFile.path);
      final current = await facade.loadCurrentLedger();
      final recent = await facade.loadRecentLedgers();

      expect(secondImport.ledgerId, firstImport.ledgerId);
      expect(secondImport.path, firstImport.path);
      expect(current?.id, firstImport.ledgerId);
      expect(
        await File(current!.entryFilePath).readAsString(),
        'option "title" "Household Reloaded"\n'
        '2026-04-02 open Assets:Bank CNY\n',
      );
      expect(recent, hasLength(1));
      expect(recent.single.id, firstImport.ledgerId);
    },
  );

  test(
    'loadRecentLedgers includes the stored entry file path from ledger metadata',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tally_bean_ledger_io_test',
      );
      addTearDown(() => sandbox.delete(recursive: true));

      final sourceRoot = Directory('${sandbox.path}/source/household');
      final nested = Directory('${sourceRoot.path}/journal');
      await nested.create(recursive: true);

      final entryFile = File('${nested.path}/main.beancount');
      await entryFile.writeAsString('2026-04-01 open Assets:Cash CNY\n');

      final supportRoot = Directory('${sandbox.path}/app-support');
      final facade = LocalLedgerIoFacade(appSupportPath: supportRoot.path);

      final imported = await facade.importLedger(entryFile.path);
      final recent = await facade.loadRecentLedgers();

      expect(recent, hasLength(1));
      expect(recent.single.id, imported.ledgerId);
      expect(recent.single.entryFilePath, imported.entryFilePath);
    },
  );

  test(
    'loadLedgerFiles recursively loads only .bean/.beancount files with deterministic relative paths',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tally_bean_ledger_io_test',
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
      final facade = LocalLedgerIoFacade(appSupportPath: supportRoot.path);

      await facade.importLedger(mainFile.path);
      final current = await facade.loadCurrentLedger();
      final files = await facade.loadLedgerFiles(current!.path);

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
    'syncLedgerName remains compatible with legacy metadata filename',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tally_bean_ledger_io_test',
      );
      addTearDown(() => sandbox.delete(recursive: true));

      final sourceRoot = Directory('${sandbox.path}/source/household');
      await sourceRoot.create(recursive: true);

      final mainFile = File('${sourceRoot.path}/main.beancount');
      await mainFile.writeAsString('2026-04-01 open Assets:Cash CNY\n');

      final supportRoot = Directory('${sandbox.path}/app-support');
      final facade = LocalLedgerIoFacade(appSupportPath: supportRoot.path);

      await facade.importLedger(mainFile.path);
      final current = await facade.loadCurrentLedger();
      expect(current, isNotNull);

      final jsonMetadataFile = File('${current!.path}/.tally_bean_ledger.json');
      final legacyMetadataFile = File('${current.path}/.tally_bean_ledger');

      await legacyMetadataFile.writeAsString(
        await jsonMetadataFile.readAsString(),
      );
      await jsonMetadataFile.delete();

      await facade.syncLedgerName(current.id, 'Renamed Ledger');
      final renamed = await facade.loadCurrentLedger();

      expect(renamed?.name, 'Renamed Ledger');
      expect(legacyMetadataFile.existsSync(), isTrue);
    },
  );

  test(
    'loadCurrentLedger remains compatible with legacy workspace state and metadata files',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tally_bean_ledger_io_test',
      );
      addTearDown(() => sandbox.delete(recursive: true));

      final supportRoot = Directory('${sandbox.path}/app-support');
      final legacyLedgerRoot = Directory(
        '${supportRoot.path}/workspaces/household-legacy',
      );
      await legacyLedgerRoot.create(recursive: true);

      final legacyEntryFile = File('${legacyLedgerRoot.path}/main.beancount');
      await legacyEntryFile.writeAsString('2026-04-01 open Assets:Cash CNY\n');
      final legacyMetadataFile = File(
        '${legacyLedgerRoot.path}/.tally_bean_workspace.json',
      );
      await legacyMetadataFile.writeAsString(
        jsonEncode(<String, Object?>{
          'workspaceId': 'household-legacy',
          'name': 'Legacy Household',
          'entryFileRelativePath': 'main.beancount',
          'lastImportedAt': DateTime(2026, 4, 1, 8).toIso8601String(),
        }),
      );
      final legacyStateFile = File('${supportRoot.path}/workspace_state.json');
      await legacyStateFile.parent.create(recursive: true);
      await legacyStateFile.writeAsString(
        jsonEncode(<String, Object?>{
          'currentWorkspaceId': 'household-legacy',
          'recent': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'household-legacy',
              'name': 'Legacy Household',
              'path': legacyLedgerRoot.path,
              'lastOpenedAt': DateTime(2026, 4, 18, 9, 30).toIso8601String(),
            },
          ],
        }),
      );

      final facade = LocalLedgerIoFacade(appSupportPath: supportRoot.path);
      final current = await facade.loadCurrentLedger();
      final recent = await facade.loadRecentLedgers();

      expect(current, isNotNull);
      expect(current?.id, 'household-legacy');
      expect(current?.name, 'Legacy Household');
      expect(current?.path, legacyLedgerRoot.path);
      expect(current?.entryFilePath, legacyEntryFile.path);
      expect(recent, hasLength(1));
      expect(recent.single.id, 'household-legacy');
      expect(recent.single.path, legacyLedgerRoot.path);
    },
  );

  test(
    'deleteLedger removes ledger files and updates current/recent state',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tally_bean_ledger_io_test',
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
      final facade = LocalLedgerIoFacade(appSupportPath: supportRoot.path);

      final summaryA = await facade.importLedger(mainA.path);
      final summaryB = await facade.importLedger(mainB.path);
      expect((await facade.loadCurrentLedger())?.id, summaryB.ledgerId);

      await facade.deleteLedger(summaryB.ledgerId);
      expect(Directory(summaryB.path).existsSync(), isFalse);
      expect((await facade.loadCurrentLedger())?.id, summaryA.ledgerId);
      expect(
        (await facade.loadRecentLedgers()).map((item) => item.id),
        <String>[summaryA.ledgerId],
      );

      await facade.deleteLedger(summaryA.ledgerId);
      expect(Directory(summaryA.path).existsSync(), isFalse);
      expect(await facade.loadCurrentLedger(), isNull);
      expect(await facade.loadRecentLedgers(), isEmpty);
    },
  );

  test(
    'createDefaultLedger regenerates the default ledger even when it already exists',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tally_bean_ledger_io_test',
      );
      addTearDown(() => sandbox.delete(recursive: true));

      final supportRoot = Directory('${sandbox.path}/app-support');
      final facade = LocalLedgerIoFacade(appSupportPath: supportRoot.path);

      final first = await facade.createDefaultLedger();
      final entryFile = File(first.entryFilePath);
      expect(entryFile.existsSync(), isTrue);

      await entryFile.writeAsString('option "title" "custom"\n');
      final extraLedgerFile = File('${first.path}/archives/2026.bean');
      await extraLedgerFile.parent.create(recursive: true);
      await extraLedgerFile.writeAsString('2026-04-01 open Assets:Cash CNY\n');

      final second = await facade.createDefaultLedger();
      final secondEntry = File(second.entryFilePath);

      expect(second.ledgerId, first.ledgerId);
      expect(second.path, first.path);
      expect(
        await secondEntry.readAsString(),
        contains('option "title" "默认账本"'),
      );
      expect(
        await secondEntry.readAsString(),
        contains('open Assets:Cash CNY'),
      );
      expect(extraLedgerFile.existsSync(), isFalse);
      expect(second.fileCount, 1);
    },
  );

  test(
    'createDefaultLedger writes a template with all five account types',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tally_bean_ledger_io_test',
      );
      addTearDown(() => sandbox.delete(recursive: true));

      final supportRoot = Directory('${sandbox.path}/app-support');
      final facade = LocalLedgerIoFacade(appSupportPath: supportRoot.path);

      final summary = await facade.createDefaultLedger();
      final content = await File(summary.entryFilePath).readAsString();

      expect(content, contains('open Assets:'));
      expect(content, contains('open Liabilities:'));
      expect(content, contains('open Equity:'));
      expect(content, contains('open Income:'));
      expect(content, contains('open Expenses:'));
    },
  );

  test(
    'writeFileContent overwrites ledger file content for save and rollback flows',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'tally_bean_ledger_io_test',
      );
      addTearDown(() => sandbox.delete(recursive: true));

      final sourceRoot = Directory('${sandbox.path}/source/household');
      await sourceRoot.create(recursive: true);

      final mainFile = File('${sourceRoot.path}/main.beancount');
      await mainFile.writeAsString('option "title" "Household"\n');

      final supportRoot = Directory('${sandbox.path}/app-support');
      final facade = LocalLedgerIoFacade(appSupportPath: supportRoot.path);

      await facade.importLedger(mainFile.path);
      final current = await facade.loadCurrentLedger();
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

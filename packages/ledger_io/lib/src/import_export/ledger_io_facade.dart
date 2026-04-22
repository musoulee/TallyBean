import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'ledger_io_file_record.dart';
import '../recent_ledgers/recent_ledger_record.dart';

abstract interface class LedgerIoFacade {
  Future<ImportedLedgerSummary> importLedger(String sourcePath);
  Future<ImportedLedgerSummary> createDefaultLedger();
  Future<void> syncLedgerName(String ledgerId, String newName);
  Future<void> deleteLedger(String ledgerId);
  Future<void> exportLedger(String ledgerId, String destinationPath);
  Future<CurrentLedgerRecord?> loadCurrentLedger();
  Future<void> setCurrentLedger(String ledgerId);
  Future<List<RecentLedgerRecord>> loadRecentLedgers();
  Future<String> loadFileContent(String filePath);
  Future<void> writeFileContent(String filePath, String content);
  Future<List<LedgerIoFileRecord>> loadLedgerFiles(String ledgerRootPath);
}

class MemoryLedgerIoFacade implements LedgerIoFacade {
  const MemoryLedgerIoFacade();

  @override
  Future<void> exportLedger(String ledgerId, String destinationPath) async {}

  @override
  Future<ImportedLedgerSummary> createDefaultLedger() async {
    return ImportedLedgerSummary(
      ledgerId: 'default',
      name: '默认账本',
      path: '/memory/default',
      entryFilePath: '/memory/default/main.bean',
      fileCount: 1,
      lastImportedAt: DateTime.now(),
    );
  }

  @override
  Future<void> syncLedgerName(String ledgerId, String newName) async {}

  @override
  Future<void> deleteLedger(String ledgerId) async {}

  @override
  Future<ImportedLedgerSummary> importLedger(String sourcePath) async {
    return ImportedLedgerSummary(
      ledgerId: 'household',
      name: 'Household Ledger',
      path: '/storage/emulated/0/Documents/beancount',
      entryFilePath: '/storage/emulated/0/Documents/beancount/main.beancount',
      fileCount: 12,
      lastImportedAt: DateTime(2026, 4, 12, 9, 42),
    );
  }

  @override
  Future<CurrentLedgerRecord?> loadCurrentLedger() async {
    return CurrentLedgerRecord(
      id: 'household',
      name: 'Household Ledger',
      path: '/storage/emulated/0/Documents/beancount',
      entryFilePath: '/storage/emulated/0/Documents/beancount/main.beancount',
      lastImportedAt: DateTime(2026, 4, 12, 9, 42),
    );
  }

  @override
  Future<List<RecentLedgerRecord>> loadRecentLedgers() async {
    return <RecentLedgerRecord>[
      RecentLedgerRecord(
        id: 'household',
        name: 'Household Ledger',
        path: '/storage/emulated/0/Documents/beancount',
        lastOpenedAt: DateTime(2026, 4, 12, 9, 42),
      ),
    ];
  }

  @override
  Future<void> setCurrentLedger(String ledgerId) async {}

  @override
  Future<String> loadFileContent(String filePath) async {
    return '; 示例账本 - TallyBean 演示模式\n'
        '\n'
        'option "title" "演示账本"\n'
        'option "operating_currency" "CNY"\n'
        '\n'
        '2024-01-01 open Income:Salary CNY\n'
        '2024-01-01 open Expenses:Food CNY\n'
        '2024-01-01 open Assets:Bank:CCB CNY\n';
  }

  @override
  Future<void> writeFileContent(String filePath, String content) async {}

  @override
  Future<List<LedgerIoFileRecord>> loadLedgerFiles(
    String ledgerRootPath,
  ) async {
    return const <LedgerIoFileRecord>[
      LedgerIoFileRecord(
        filePath: '/memory/default/main.bean',
        relativePath: 'main.bean',
        content:
            'option "title" "演示账本"\n'
            'option "operating_currency" "CNY"\n'
            '\n'
            '2024-01-01 open Assets:Bank:CCB CNY\n',
        sizeBytes: 101,
      ),
      LedgerIoFileRecord(
        filePath: '/memory/default/transactions/2024.bean',
        relativePath: 'transactions/2024.bean',
        content: '2024-04-01 * "Market"\n  Expenses:Food  86 CNY\n',
        sizeBytes: 47,
      ),
    ];
  }
}

class LocalLedgerIoFacade implements LedgerIoFacade {
  LocalLedgerIoFacade({this.appSupportPath});

  final String? appSupportPath;

  static const _stateFileName = 'ledger_state.json';
  static const _legacyStateFileName = 'workspace_state.json';
  static const _ledgerMetadataFileName = '.tally_bean_ledger.json';
  static const _legacyLedgerMetadataFileName = '.tally_bean_ledger';
  static const _legacyWorkspaceMetadataFileName = '.tally_bean_workspace.json';
  static const _legacyWorkspaceMetadataFallbackFileName =
      '.tally_bean_workspace';
  static const _defaultLedgerId = 'default-ledger';
  static const _defaultLedgerName = '默认账本';
  static const _defaultEntryRelativePath = 'main.bean';
  static const _defaultEntryTemplate = '''option "title" "默认账本"
option "operating_currency" "CNY"

2000-01-01 open Expenses:Daily
2000-01-01 open Income:Salary
''';

  @override
  Future<void> exportLedger(String ledgerId, String destinationPath) async {
    final recent = await loadRecentLedgers();
    final record = recent.where((item) => item.id == ledgerId).firstOrNull;
    if (record == null) {
      throw FileSystemException('Ledger not found', ledgerId);
    }

    final sourceDirectory = Directory(record.path);
    final destinationDirectory = Directory(
      path.join(destinationPath, path.basename(record.path)),
    );

    if (destinationDirectory.existsSync()) {
      await destinationDirectory.delete(recursive: true);
    }

    await _copyDirectory(sourceDirectory, destinationDirectory);
  }

  @override
  Future<ImportedLedgerSummary> createDefaultLedger() async {
    final supportDirectory = await _ensureSupportDirectory();
    final ledgersDirectory = Directory(
      path.join(supportDirectory.path, 'ledgers'),
    );
    await ledgersDirectory.create(recursive: true);

    final destinationRoot = Directory(
      path.join(ledgersDirectory.path, _defaultLedgerId),
    );
    final openedAt = DateTime.now();
    final existingMetadata = await _readLedgerMetadata(destinationRoot.path);
    final ledgerId =
        existingMetadata?['ledgerId'] as String? ?? _defaultLedgerId;
    final ledgerName =
        existingMetadata?['name'] as String? ?? _defaultLedgerName;
    final entryFileRelativePath =
        existingMetadata?['entryFileRelativePath'] as String? ??
        _defaultEntryRelativePath;
    final importedAt = DateTime.parse(
      existingMetadata?['lastImportedAt'] as String? ??
          openedAt.toIso8601String(),
    );

    await destinationRoot.create(recursive: true);

    final entryFilePath = path.join(
      destinationRoot.path,
      entryFileRelativePath,
    );
    final entryFile = File(entryFilePath);
    if (!entryFile.existsSync()) {
      await entryFile.parent.create(recursive: true);
      await entryFile.writeAsString(_defaultEntryTemplate);
    }

    await _writeLedgerMetadata(
      rootPath: destinationRoot.path,
      metadata: <String, Object?>{
        'ledgerId': ledgerId,
        'name': ledgerName,
        'entryFileRelativePath': entryFileRelativePath,
        'lastImportedAt': importedAt.toIso8601String(),
      },
    );

    final state = await _loadLedgerState();
    final updatedRecent = <RecentLedgerRecord>[
      RecentLedgerRecord(
        id: ledgerId,
        name: ledgerName,
        path: destinationRoot.path,
        lastOpenedAt: openedAt,
      ),
      ...state.recent.where((record) => record.id != ledgerId),
    ];

    await _saveLedgerState(
      _LedgerState(currentLedgerId: ledgerId, recent: updatedRecent),
    );

    return ImportedLedgerSummary(
      ledgerId: ledgerId,
      name: ledgerName,
      path: destinationRoot.path,
      entryFilePath: entryFilePath,
      fileCount: await _countLedgerFiles(destinationRoot.path),
      lastImportedAt: importedAt,
    );
  }

  @override
  Future<ImportedLedgerSummary> importLedger(String sourcePath) async {
    final sourceFile = File(sourcePath);
    if (!sourceFile.existsSync()) {
      throw FileSystemException('Source beancount file not found', sourcePath);
    }

    final sourceRoot = sourceFile.parent;
    final absoluteSourceRoot = path.normalize(path.absolute(sourceRoot.path));
    final supportDirectory = await _ensureSupportDirectory();
    final ledgersDirectory = Directory(
      path.join(supportDirectory.path, 'ledgers'),
    );
    await ledgersDirectory.create(recursive: true);

    final ledgerId = _ledgerIdForPath(absoluteSourceRoot);
    final state = await _loadLedgerState();
    final existingRecord = state.recent.firstWhereOrNull(
      (record) => record.id == ledgerId,
    );
    final ledgerName =
        existingRecord?.name ?? _displayNameForDirectory(sourceRoot.path);
    final importedAt = DateTime.now();
    final destinationRoot = Directory(
      path.join(ledgersDirectory.path, ledgerId),
    );

    if (destinationRoot.existsSync()) {
      await destinationRoot.delete(recursive: true);
    }

    final copiedFiles = await _copyDirectory(sourceRoot, destinationRoot);
    final relativeEntryPath = path.relative(
      sourceFile.path,
      from: sourceRoot.path,
    );
    final entryFilePath = path.join(destinationRoot.path, relativeEntryPath);

    await _writeLedgerMetadata(
      rootPath: destinationRoot.path,
      metadata: <String, Object?>{
        'ledgerId': ledgerId,
        'name': ledgerName,
        'entryFileRelativePath': relativeEntryPath,
        'lastImportedAt': importedAt.toIso8601String(),
      },
    );

    final updatedRecent = <RecentLedgerRecord>[
      RecentLedgerRecord(
        id: ledgerId,
        name: ledgerName,
        path: destinationRoot.path,
        lastOpenedAt: importedAt,
      ),
      ...state.recent.where((record) => record.id != ledgerId),
    ];

    await _saveLedgerState(
      _LedgerState(currentLedgerId: ledgerId, recent: updatedRecent),
    );

    return ImportedLedgerSummary(
      ledgerId: ledgerId,
      name: ledgerName,
      path: destinationRoot.path,
      entryFilePath: entryFilePath,
      fileCount: copiedFiles,
      lastImportedAt: importedAt,
    );
  }

  @override
  Future<CurrentLedgerRecord?> loadCurrentLedger() async {
    final state = await _loadLedgerState();
    final currentId = state.currentLedgerId;
    if (currentId == null) {
      return null;
    }

    final current = state.recent
        .where((record) => record.id == currentId)
        .firstOrNull;
    if (current == null) {
      return null;
    }

    final metadata = await _readLedgerMetadata(current.path);
    if (metadata == null) {
      return null;
    }

    return CurrentLedgerRecord(
      id: current.id,
      name: metadata['name'] as String? ?? current.name,
      path: current.path,
      entryFilePath: path.join(
        current.path,
        metadata['entryFileRelativePath'] as String? ?? 'main.beancount',
      ),
      lastImportedAt: DateTime.parse(
        metadata['lastImportedAt'] as String? ??
            current.lastOpenedAt.toIso8601String(),
      ),
    );
  }

  @override
  Future<List<RecentLedgerRecord>> loadRecentLedgers() async {
    final state = await _loadLedgerState();
    final sorted = [...state.recent]
      ..sort((left, right) => right.lastOpenedAt.compareTo(left.lastOpenedAt));
    final resolved = <RecentLedgerRecord>[];
    for (final record in sorted) {
      final metadata = await _readLedgerMetadata(record.path);
      final entryRelativePath = metadata?['entryFileRelativePath'] as String?;
      resolved.add(
        RecentLedgerRecord(
          id: record.id,
          name: record.name,
          path: record.path,
          lastOpenedAt: record.lastOpenedAt,
          entryFilePath: entryRelativePath == null
              ? null
              : path.join(record.path, entryRelativePath),
        ),
      );
    }
    return resolved;
  }

  @override
  Future<void> setCurrentLedger(String ledgerId) async {
    final state = await _loadLedgerState();
    final now = DateTime.now();
    final updatedRecent = state.recent
        .map(
          (record) => record.id == ledgerId
              ? RecentLedgerRecord(
                  id: record.id,
                  name: record.name,
                  path: record.path,
                  lastOpenedAt: now,
                )
              : record,
        )
        .toList();

    if (updatedRecent.every((record) => record.id != ledgerId)) {
      throw FileSystemException('Ledger not found', ledgerId);
    }

    await _saveLedgerState(
      _LedgerState(currentLedgerId: ledgerId, recent: updatedRecent),
    );
  }

  @override
  Future<void> syncLedgerName(String ledgerId, String newName) async {
    final state = await _loadLedgerState();
    final recentRecord = state.recent.firstWhereOrNull((r) => r.id == ledgerId);

    if (recentRecord == null) {
      throw FileSystemException('Ledger not found in recent list', ledgerId);
    }

    final metadataFile = await _resolveMetadataFile(recentRecord.path);
    if (metadataFile != null) {
      final metadata =
          jsonDecode(await metadataFile.readAsString()) as Map<String, dynamic>;
      metadata['name'] = newName;
      await metadataFile.writeAsString(jsonEncode(metadata));
    }

    // Update state file
    final updatedRecent = state.recent
        .map(
          (record) => record.id == ledgerId
              ? RecentLedgerRecord(
                  id: record.id,
                  name: newName,
                  path: record.path,
                  lastOpenedAt: record.lastOpenedAt,
                )
              : record,
        )
        .toList();

    await _saveLedgerState(
      _LedgerState(
        currentLedgerId: state.currentLedgerId,
        recent: updatedRecent,
      ),
    );
  }

  @override
  Future<void> deleteLedger(String ledgerId) async {
    final state = await _loadLedgerState();
    final recentRecord = state.recent.firstWhereOrNull(
      (record) => record.id == ledgerId,
    );
    if (recentRecord == null) {
      throw FileSystemException('Ledger not found in recent list', ledgerId);
    }

    final ledgerDirectory = Directory(recentRecord.path);
    if (ledgerDirectory.existsSync()) {
      await ledgerDirectory.delete(recursive: true);
    }

    final updatedRecent = state.recent
        .where((record) => record.id != ledgerId)
        .toList(growable: false);
    final nextCurrentLedgerId = state.currentLedgerId == ledgerId
        ? updatedRecent.firstOrNull?.id
        : state.currentLedgerId;
    await _saveLedgerState(
      _LedgerState(currentLedgerId: nextCurrentLedgerId, recent: updatedRecent),
    );
  }

  @override
  Future<String> loadFileContent(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw FileSystemException('File not found', filePath);
    }
    return file.readAsString();
  }

  @override
  Future<void> writeFileContent(String filePath, String content) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw FileSystemException('File not found', filePath);
    }
    await file.writeAsString(content);
  }

  @override
  Future<List<LedgerIoFileRecord>> loadLedgerFiles(
    String ledgerRootPath,
  ) async {
    final rootDirectory = Directory(ledgerRootPath);
    if (!rootDirectory.existsSync()) {
      throw FileSystemException('Ledger root not found', ledgerRootPath);
    }

    final files = <LedgerIoFileRecord>[];
    await for (final entity in rootDirectory.list(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      final lower = entity.path.toLowerCase();
      if (!lower.endsWith('.beancount') && !lower.endsWith('.bean')) {
        continue;
      }

      final relative = path.relative(entity.path, from: ledgerRootPath);
      final content = await entity.readAsString();
      files.add(
        LedgerIoFileRecord(
          filePath: entity.path,
          relativePath: relative,
          content: content,
          sizeBytes: await entity.length(),
        ),
      );
    }

    files.sort(
      (left, right) => left.relativePath.compareTo(right.relativePath),
    );
    return files;
  }

  Future<Directory> _ensureSupportDirectory() async {
    if (appSupportPath != null) {
      final directory = Directory(appSupportPath!);
      await directory.create(recursive: true);
      return directory;
    }

    Directory directory;
    if (Platform.isAndroid) {
      try {
        directory = await getApplicationSupportDirectory();
      } on MissingPluginException {
        directory = Directory(
          path.join(Directory.systemTemp.path, 'tally_bean'),
        );
      }
    } else {
      directory = Directory(path.join(Directory.systemTemp.path, 'tally_bean'));
    }
    await directory.create(recursive: true);
    return directory;
  }

  Future<_LedgerState> _loadLedgerState() async {
    final supportDirectory = await _ensureSupportDirectory();
    final stateFile = _resolveStateFile(supportDirectory.path);
    if (!stateFile.existsSync()) {
      return const _LedgerState(currentLedgerId: null, recent: []);
    }

    final data =
        jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>;
    final recent = (data['recent'] as List<dynamic>? ?? const <dynamic>[])
        .map(
          (item) => RecentLedgerRecord(
            id: item['id'] as String,
            name: item['name'] as String,
            path: item['path'] as String,
            lastOpenedAt: DateTime.parse(item['lastOpenedAt'] as String),
          ),
        )
        .toList();

    return _LedgerState(
      currentLedgerId:
          data['currentLedgerId'] as String? ??
          data['currentWorkspaceId'] as String?,
      recent: recent,
    );
  }

  Future<void> _saveLedgerState(_LedgerState state) async {
    final supportDirectory = await _ensureSupportDirectory();
    final stateFile = File(path.join(supportDirectory.path, _stateFileName));
    await stateFile.writeAsString(
      jsonEncode(<String, Object?>{
        'currentLedgerId': state.currentLedgerId,
        'recent': state.recent
            .map(
              (record) => <String, Object?>{
                'id': record.id,
                'name': record.name,
                'path': record.path,
                'lastOpenedAt': record.lastOpenedAt.toIso8601String(),
              },
            )
            .toList(),
      }),
    );
  }

  Future<Map<String, Object?>?> _readLedgerMetadata(String rootPath) async {
    final metadataFile = await _resolveMetadataFile(rootPath);
    if (metadataFile == null) {
      return null;
    }

    return (jsonDecode(await metadataFile.readAsString())
            as Map<String, dynamic>)
        .cast<String, Object?>();
  }

  Future<void> _writeLedgerMetadata({
    required String rootPath,
    required Map<String, Object?> metadata,
  }) async {
    final metadataFile = File(path.join(rootPath, _ledgerMetadataFileName));
    await metadataFile.writeAsString(jsonEncode(metadata));
  }

  Future<File?> _resolveMetadataFile(String rootPath) async {
    final jsonFile = File(path.join(rootPath, _ledgerMetadataFileName));
    if (jsonFile.existsSync()) {
      return jsonFile;
    }

    final legacyFile = File(path.join(rootPath, _legacyLedgerMetadataFileName));
    if (legacyFile.existsSync()) {
      return legacyFile;
    }

    final legacyWorkspaceJson = File(
      path.join(rootPath, _legacyWorkspaceMetadataFileName),
    );
    if (legacyWorkspaceJson.existsSync()) {
      return legacyWorkspaceJson;
    }

    final legacyWorkspaceFile = File(
      path.join(rootPath, _legacyWorkspaceMetadataFallbackFileName),
    );
    if (legacyWorkspaceFile.existsSync()) {
      return legacyWorkspaceFile;
    }

    return null;
  }

  File _resolveStateFile(String supportDirectoryPath) {
    final ledgerStateFile = File(
      path.join(supportDirectoryPath, _stateFileName),
    );
    if (ledgerStateFile.existsSync()) {
      return ledgerStateFile;
    }
    return File(path.join(supportDirectoryPath, _legacyStateFileName));
  }

  Future<int> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    var copiedFiles = 0;

    await for (final entity in source.list(recursive: false)) {
      if (entity is File) {
        await entity.copy(
          path.join(destination.path, path.basename(entity.path)),
        );
        copiedFiles += 1;
        continue;
      }

      if (entity is Directory) {
        copiedFiles += await _copyDirectory(
          entity,
          Directory(path.join(destination.path, path.basename(entity.path))),
        );
      }
    }

    return copiedFiles;
  }

  String _displayNameForDirectory(String directoryPath) {
    final base = path.basename(directoryPath).replaceAll(RegExp(r'[_-]+'), ' ');
    if (base.isEmpty) {
      return 'Imported Ledger';
    }

    return base
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String _sanitizeLedgerId(String raw) {
    final sanitized = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return sanitized.isEmpty ? 'ledger' : sanitized;
  }

  String _ledgerIdForPath(String sourceRootPath) {
    final base = _sanitizeLedgerId(path.basename(sourceRootPath));
    final suffix = _stableHashHex(sourceRootPath);
    return '$base-$suffix';
  }

  String _stableHashHex(String input) {
    var hash = 0x811c9dc5;
    for (final unit in utf8.encode(input)) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  Future<int> _countLedgerFiles(String ledgerRootPath) async {
    final rootDirectory = Directory(ledgerRootPath);
    if (!rootDirectory.existsSync()) {
      return 0;
    }

    var count = 0;
    await for (final entity in rootDirectory.list(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      final lower = entity.path.toLowerCase();
      if (lower.endsWith('.beancount') || lower.endsWith('.bean')) {
        count += 1;
      }
    }
    return count;
  }
}

class _LedgerState {
  const _LedgerState({required this.currentLedgerId, required this.recent});

  final String? currentLedgerId;
  final List<RecentLedgerRecord> recent;
}

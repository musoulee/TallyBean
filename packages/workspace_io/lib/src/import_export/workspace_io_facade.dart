import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'workspace_io_file_record.dart';
import '../recent_workspaces/recent_workspace_record.dart';

abstract interface class WorkspaceIoFacade {
  Future<ImportedWorkspaceSummary> importWorkspace(String sourcePath);
  Future<ImportedWorkspaceSummary> createDefaultWorkspace();
  Future<void> renameWorkspace(String workspaceId, String newName);
  Future<void> deleteWorkspace(String workspaceId);
  Future<void> exportWorkspace(String workspaceId, String destinationPath);
  Future<CurrentWorkspaceRecord?> loadCurrentWorkspace();
  Future<void> setCurrentWorkspace(String workspaceId);
  Future<List<RecentWorkspaceRecord>> loadRecentWorkspaces();
  Future<String> loadFileContent(String filePath);
  Future<void> writeFileContent(String filePath, String content);
  Future<List<WorkspaceIoFileRecord>> loadWorkspaceFiles(
    String workspaceRootPath,
  );
}

class MemoryWorkspaceIoFacade implements WorkspaceIoFacade {
  const MemoryWorkspaceIoFacade();

  @override
  Future<void> exportWorkspace(
    String workspaceId,
    String destinationPath,
  ) async {}

  @override
  Future<ImportedWorkspaceSummary> createDefaultWorkspace() async {
    return ImportedWorkspaceSummary(
      workspaceId: 'default',
      name: '默认账本',
      path: '/memory/default',
      entryFilePath: '/memory/default/main.bean',
      fileCount: 1,
      lastImportedAt: DateTime.now(),
    );
  }

  @override
  Future<void> renameWorkspace(String workspaceId, String newName) async {}

  @override
  Future<void> deleteWorkspace(String workspaceId) async {}

  @override
  Future<ImportedWorkspaceSummary> importWorkspace(String sourcePath) async {
    return ImportedWorkspaceSummary(
      workspaceId: 'household',
      name: 'Household Ledger',
      path: '/storage/emulated/0/Documents/beancount',
      entryFilePath: '/storage/emulated/0/Documents/beancount/main.beancount',
      fileCount: 12,
      lastImportedAt: DateTime(2026, 4, 12, 9, 42),
    );
  }

  @override
  Future<CurrentWorkspaceRecord?> loadCurrentWorkspace() async {
    return CurrentWorkspaceRecord(
      id: 'household',
      name: 'Household Ledger',
      path: '/storage/emulated/0/Documents/beancount',
      entryFilePath: '/storage/emulated/0/Documents/beancount/main.beancount',
      lastImportedAt: DateTime(2026, 4, 12, 9, 42),
    );
  }

  @override
  Future<List<RecentWorkspaceRecord>> loadRecentWorkspaces() async {
    return <RecentWorkspaceRecord>[
      RecentWorkspaceRecord(
        id: 'household',
        name: 'Household Ledger',
        path: '/storage/emulated/0/Documents/beancount',
        lastOpenedAt: DateTime(2026, 4, 12, 9, 42),
      ),
    ];
  }

  @override
  Future<void> setCurrentWorkspace(String workspaceId) async {}

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
  Future<List<WorkspaceIoFileRecord>> loadWorkspaceFiles(
    String workspaceRootPath,
  ) async {
    return const <WorkspaceIoFileRecord>[
      WorkspaceIoFileRecord(
        filePath: '/memory/default/main.bean',
        relativePath: 'main.bean',
        content:
            'option "title" "演示账本"\n'
            'option "operating_currency" "CNY"\n'
            '\n'
            '2024-01-01 open Assets:Bank:CCB CNY\n',
        sizeBytes: 101,
      ),
      WorkspaceIoFileRecord(
        filePath: '/memory/default/transactions/2024.bean',
        relativePath: 'transactions/2024.bean',
        content: '2024-04-01 * "Market"\n  Expenses:Food  86 CNY\n',
        sizeBytes: 47,
      ),
    ];
  }
}

class LocalWorkspaceIoFacade implements WorkspaceIoFacade {
  LocalWorkspaceIoFacade({this.appSupportPath});

  final String? appSupportPath;

  static const _stateFileName = 'workspace_state.json';
  static const _workspaceMetadataFileName = '.tally_bean_workspace.json';
  static const _legacyWorkspaceMetadataFileName = '.tally_bean_workspace';
  static const _defaultWorkspaceId = 'default-ledger';
  static const _defaultWorkspaceName = '默认账本';
  static const _defaultEntryRelativePath = 'main.bean';
  static const _defaultEntryTemplate = '''option "title" "默认账本"
option "operating_currency" "CNY"

2000-01-01 open Expenses:Daily
2000-01-01 open Income:Salary
''';

  @override
  Future<void> exportWorkspace(
    String workspaceId,
    String destinationPath,
  ) async {
    final recent = await loadRecentWorkspaces();
    final record = recent.where((item) => item.id == workspaceId).firstOrNull;
    if (record == null) {
      throw FileSystemException('Workspace not found', workspaceId);
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
  Future<ImportedWorkspaceSummary> createDefaultWorkspace() async {
    final supportDirectory = await _ensureSupportDirectory();
    final workspacesDirectory = Directory(
      path.join(supportDirectory.path, 'workspaces'),
    );
    await workspacesDirectory.create(recursive: true);

    final destinationRoot = Directory(
      path.join(workspacesDirectory.path, _defaultWorkspaceId),
    );
    final openedAt = DateTime.now();
    final existingMetadata = await _readWorkspaceMetadata(destinationRoot.path);
    final workspaceId =
        existingMetadata?['workspaceId'] as String? ?? _defaultWorkspaceId;
    final workspaceName =
        existingMetadata?['name'] as String? ?? _defaultWorkspaceName;
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

    await _writeWorkspaceMetadata(
      rootPath: destinationRoot.path,
      metadata: <String, Object?>{
        'workspaceId': workspaceId,
        'name': workspaceName,
        'entryFileRelativePath': entryFileRelativePath,
        'lastImportedAt': importedAt.toIso8601String(),
      },
    );

    final state = await _loadWorkspaceState();
    final updatedRecent = <RecentWorkspaceRecord>[
      RecentWorkspaceRecord(
        id: workspaceId,
        name: workspaceName,
        path: destinationRoot.path,
        lastOpenedAt: openedAt,
      ),
      ...state.recent.where((record) => record.id != workspaceId),
    ];

    await _saveWorkspaceState(
      _WorkspaceState(currentWorkspaceId: workspaceId, recent: updatedRecent),
    );

    return ImportedWorkspaceSummary(
      workspaceId: workspaceId,
      name: workspaceName,
      path: destinationRoot.path,
      entryFilePath: entryFilePath,
      fileCount: await _countLedgerFiles(destinationRoot.path),
      lastImportedAt: importedAt,
    );
  }

  @override
  Future<ImportedWorkspaceSummary> importWorkspace(String sourcePath) async {
    final sourceFile = File(sourcePath);
    if (!sourceFile.existsSync()) {
      throw FileSystemException('Source beancount file not found', sourcePath);
    }

    final sourceRoot = sourceFile.parent;
    final absoluteSourceRoot = path.normalize(path.absolute(sourceRoot.path));
    final supportDirectory = await _ensureSupportDirectory();
    final workspacesDirectory = Directory(
      path.join(supportDirectory.path, 'workspaces'),
    );
    await workspacesDirectory.create(recursive: true);

    final workspaceId = _workspaceIdForPath(absoluteSourceRoot);
    final state = await _loadWorkspaceState();
    if (state.recent.any((record) => record.id == workspaceId)) {
      throw FileSystemException('该账本已经导入', absoluteSourceRoot);
    }
    final workspaceName = _displayNameForDirectory(sourceRoot.path);
    final importedAt = DateTime.now();
    final destinationRoot = Directory(
      path.join(workspacesDirectory.path, workspaceId),
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

    await _writeWorkspaceMetadata(
      rootPath: destinationRoot.path,
      metadata: <String, Object?>{
        'workspaceId': workspaceId,
        'name': workspaceName,
        'entryFileRelativePath': relativeEntryPath,
        'lastImportedAt': importedAt.toIso8601String(),
      },
    );

    final updatedRecent = <RecentWorkspaceRecord>[
      RecentWorkspaceRecord(
        id: workspaceId,
        name: workspaceName,
        path: destinationRoot.path,
        lastOpenedAt: importedAt,
      ),
      ...state.recent.where((record) => record.id != workspaceId),
    ];

    await _saveWorkspaceState(
      _WorkspaceState(currentWorkspaceId: workspaceId, recent: updatedRecent),
    );

    return ImportedWorkspaceSummary(
      workspaceId: workspaceId,
      name: workspaceName,
      path: destinationRoot.path,
      entryFilePath: entryFilePath,
      fileCount: copiedFiles,
      lastImportedAt: importedAt,
    );
  }

  @override
  Future<CurrentWorkspaceRecord?> loadCurrentWorkspace() async {
    final state = await _loadWorkspaceState();
    final currentId = state.currentWorkspaceId;
    if (currentId == null) {
      return null;
    }

    final current = state.recent
        .where((record) => record.id == currentId)
        .firstOrNull;
    if (current == null) {
      return null;
    }

    final metadata = await _readWorkspaceMetadata(current.path);
    if (metadata == null) {
      return null;
    }

    return CurrentWorkspaceRecord(
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
  Future<List<RecentWorkspaceRecord>> loadRecentWorkspaces() async {
    final state = await _loadWorkspaceState();
    final sorted = [...state.recent]
      ..sort((left, right) => right.lastOpenedAt.compareTo(left.lastOpenedAt));
    return sorted;
  }

  @override
  Future<void> setCurrentWorkspace(String workspaceId) async {
    final state = await _loadWorkspaceState();
    final now = DateTime.now();
    final updatedRecent = state.recent
        .map(
          (record) => record.id == workspaceId
              ? RecentWorkspaceRecord(
                  id: record.id,
                  name: record.name,
                  path: record.path,
                  lastOpenedAt: now,
                )
              : record,
        )
        .toList();

    if (updatedRecent.every((record) => record.id != workspaceId)) {
      throw FileSystemException('Workspace not found', workspaceId);
    }

    await _saveWorkspaceState(
      _WorkspaceState(currentWorkspaceId: workspaceId, recent: updatedRecent),
    );
  }

  @override
  Future<void> renameWorkspace(String workspaceId, String newName) async {
    final state = await _loadWorkspaceState();
    final recentRecord = state.recent.firstWhereOrNull(
      (r) => r.id == workspaceId,
    );

    if (recentRecord == null) {
      throw FileSystemException(
        'Workspace not found in recent list',
        workspaceId,
      );
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
          (record) => record.id == workspaceId
              ? RecentWorkspaceRecord(
                  id: record.id,
                  name: newName,
                  path: record.path,
                  lastOpenedAt: record.lastOpenedAt,
                )
              : record,
        )
        .toList();

    await _saveWorkspaceState(
      _WorkspaceState(
        currentWorkspaceId: state.currentWorkspaceId,
        recent: updatedRecent,
      ),
    );
  }

  @override
  Future<void> deleteWorkspace(String workspaceId) async {
    final state = await _loadWorkspaceState();
    final recentRecord = state.recent.firstWhereOrNull(
      (record) => record.id == workspaceId,
    );
    if (recentRecord == null) {
      throw FileSystemException(
        'Workspace not found in recent list',
        workspaceId,
      );
    }

    final workspaceDirectory = Directory(recentRecord.path);
    if (workspaceDirectory.existsSync()) {
      await workspaceDirectory.delete(recursive: true);
    }

    final updatedRecent = state.recent
        .where((record) => record.id != workspaceId)
        .toList(growable: false);
    final nextCurrentWorkspaceId = state.currentWorkspaceId == workspaceId
        ? updatedRecent.firstOrNull?.id
        : state.currentWorkspaceId;
    await _saveWorkspaceState(
      _WorkspaceState(
        currentWorkspaceId: nextCurrentWorkspaceId,
        recent: updatedRecent,
      ),
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
  Future<List<WorkspaceIoFileRecord>> loadWorkspaceFiles(
    String workspaceRootPath,
  ) async {
    final rootDirectory = Directory(workspaceRootPath);
    if (!rootDirectory.existsSync()) {
      throw FileSystemException('Workspace root not found', workspaceRootPath);
    }

    final files = <WorkspaceIoFileRecord>[];
    await for (final entity in rootDirectory.list(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      final lower = entity.path.toLowerCase();
      if (!lower.endsWith('.beancount') && !lower.endsWith('.bean')) {
        continue;
      }

      final relative = path.relative(entity.path, from: workspaceRootPath);
      final content = await entity.readAsString();
      files.add(
        WorkspaceIoFileRecord(
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

  Future<_WorkspaceState> _loadWorkspaceState() async {
    final supportDirectory = await _ensureSupportDirectory();
    final stateFile = File(path.join(supportDirectory.path, _stateFileName));
    if (!stateFile.existsSync()) {
      return const _WorkspaceState(currentWorkspaceId: null, recent: []);
    }

    final data =
        jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>;
    final recent = (data['recent'] as List<dynamic>? ?? const <dynamic>[])
        .map(
          (item) => RecentWorkspaceRecord(
            id: item['id'] as String,
            name: item['name'] as String,
            path: item['path'] as String,
            lastOpenedAt: DateTime.parse(item['lastOpenedAt'] as String),
          ),
        )
        .toList();

    return _WorkspaceState(
      currentWorkspaceId: data['currentWorkspaceId'] as String?,
      recent: recent,
    );
  }

  Future<void> _saveWorkspaceState(_WorkspaceState state) async {
    final supportDirectory = await _ensureSupportDirectory();
    final stateFile = File(path.join(supportDirectory.path, _stateFileName));
    await stateFile.writeAsString(
      jsonEncode(<String, Object?>{
        'currentWorkspaceId': state.currentWorkspaceId,
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

  Future<Map<String, Object?>?> _readWorkspaceMetadata(String rootPath) async {
    final metadataFile = await _resolveMetadataFile(rootPath);
    if (metadataFile == null) {
      return null;
    }

    return (jsonDecode(await metadataFile.readAsString())
            as Map<String, dynamic>)
        .cast<String, Object?>();
  }

  Future<void> _writeWorkspaceMetadata({
    required String rootPath,
    required Map<String, Object?> metadata,
  }) async {
    final metadataFile = File(path.join(rootPath, _workspaceMetadataFileName));
    await metadataFile.writeAsString(jsonEncode(metadata));
  }

  Future<File?> _resolveMetadataFile(String rootPath) async {
    final jsonFile = File(path.join(rootPath, _workspaceMetadataFileName));
    if (jsonFile.existsSync()) {
      return jsonFile;
    }

    final legacyFile = File(
      path.join(rootPath, _legacyWorkspaceMetadataFileName),
    );
    if (legacyFile.existsSync()) {
      return legacyFile;
    }

    return null;
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

  String _sanitizeWorkspaceId(String raw) {
    final sanitized = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return sanitized.isEmpty ? 'workspace' : sanitized;
  }

  String _workspaceIdForPath(String sourceRootPath) {
    final base = _sanitizeWorkspaceId(path.basename(sourceRootPath));
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

  Future<int> _countLedgerFiles(String workspaceRootPath) async {
    final rootDirectory = Directory(workspaceRootPath);
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

class _WorkspaceState {
  const _WorkspaceState({
    required this.currentWorkspaceId,
    required this.recent,
  });

  final String? currentWorkspaceId;
  final List<RecentWorkspaceRecord> recent;
}

import 'dart:io' as io;

import 'api.dart' as frb_api;
import 'frb_generated.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart';

const _libraryStem = 'beancount_bridge_native';

abstract interface class RustLedgerRuntime {
  Future<frb_api.RustLedgerSnapshot> parseWorkspace({
    required String rootPath,
    required String entryFilePath,
  });

  Future<int> openWorkspace({
    required String rootPath,
    required String entryFilePath,
  });

  Future<void> closeWorkspace({required int handle});

  Future<frb_api.RustRefreshResult> refreshWorkspace({required int handle});

  Future<frb_api.RustWorkspaceSummary> getWorkspaceSummary({
    required int handle,
  });

  Future<List<frb_api.RustLedgerDiagnostic>> listDiagnostics({
    required int handle,
    required frb_api.RustDiagnosticQuery query,
  });

  Future<frb_api.RustJournalPage> getJournalPage({
    required int handle,
    required frb_api.RustJournalQuery query,
  });

  Future<frb_api.RustAccountTree> getAccountTree({
    required int handle,
    required frb_api.RustAccountTreeQuery query,
  });

  Future<frb_api.RustReportSnapshot> getReportSnapshot({
    required int handle,
    required frb_api.RustReportQuery query,
  });

  Future<List<frb_api.RustDocumentSummary>> listDocuments({
    required int handle,
  });

  Future<frb_api.RustDocument> getDocument({
    required int handle,
    required String documentId,
  });
}

class DefaultRustLedgerRuntime implements RustLedgerRuntime {
  const DefaultRustLedgerRuntime();

  static Future<void>? _initializeFuture;

  @override
  Future<frb_api.RustLedgerSnapshot> parseWorkspace({
    required String rootPath,
    required String entryFilePath,
  }) async {
    await _ensureInitialized();
    return frb_api.parseWorkspace(
      rootPath: rootPath,
      entryFilePath: entryFilePath,
    );
  }

  @override
  Future<void> closeWorkspace({required int handle}) async {
    await _ensureInitialized();
    await frb_api.closeWorkspace(handle: handle);
  }

  @override
  Future<frb_api.RustAccountTree> getAccountTree({
    required int handle,
    required frb_api.RustAccountTreeQuery query,
  }) async {
    await _ensureInitialized();
    return frb_api.getAccountTree(handle: handle, query: query);
  }

  @override
  Future<frb_api.RustDocument> getDocument({
    required int handle,
    required String documentId,
  }) async {
    await _ensureInitialized();
    return frb_api.getDocument(handle: handle, documentId: documentId);
  }

  @override
  Future<frb_api.RustJournalPage> getJournalPage({
    required int handle,
    required frb_api.RustJournalQuery query,
  }) async {
    await _ensureInitialized();
    return frb_api.getJournalPage(handle: handle, query: query);
  }

  @override
  Future<List<frb_api.RustLedgerDiagnostic>> listDiagnostics({
    required int handle,
    required frb_api.RustDiagnosticQuery query,
  }) async {
    await _ensureInitialized();
    return frb_api.listDiagnostics(handle: handle, query: query);
  }

  @override
  Future<List<frb_api.RustDocumentSummary>> listDocuments({
    required int handle,
  }) async {
    await _ensureInitialized();
    return frb_api.listDocuments(handle: handle);
  }

  @override
  Future<int> openWorkspace({
    required String rootPath,
    required String entryFilePath,
  }) async {
    await _ensureInitialized();
    return frb_api.openWorkspace(
      rootPath: rootPath,
      entryFilePath: entryFilePath,
    );
  }

  @override
  Future<frb_api.RustRefreshResult> refreshWorkspace({
    required int handle,
  }) async {
    await _ensureInitialized();
    return frb_api.refreshWorkspace(handle: handle);
  }

  @override
  Future<frb_api.RustReportSnapshot> getReportSnapshot({
    required int handle,
    required frb_api.RustReportQuery query,
  }) async {
    await _ensureInitialized();
    return frb_api.getReportSnapshot(handle: handle, query: query);
  }

  @override
  Future<frb_api.RustWorkspaceSummary> getWorkspaceSummary({
    required int handle,
  }) async {
    await _ensureInitialized();
    return frb_api.getWorkspaceSummary(handle: handle);
  }

  Future<void> _ensureInitialized() {
    return _initializeFuture ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      await RustLib.init();
      return;
    } catch (_) {
      if (!_isFlutterTestEnvironment()) {
        rethrow;
      }
      final fallbackLibrary = _openFallbackLibrary();
      if (fallbackLibrary == null) {
        rethrow;
      }
      await RustLib.init(externalLibrary: fallbackLibrary);
    }
  }

  bool _isFlutterTestEnvironment() {
    return io.Platform.environment.containsKey('FLUTTER_TEST');
  }

  ExternalLibrary? _openFallbackLibrary() {
    for (final candidate in _fallbackLibraryPaths()) {
      try {
        return ExternalLibrary.open(candidate);
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Iterable<String> _fallbackLibraryPaths() sync* {
    if (io.Platform.isAndroid || io.Platform.isLinux) {
      yield 'rust/target/debug/lib$_libraryStem.so';
      yield 'rust/target/release/lib$_libraryStem.so';
      yield '.dart_tool/lib/lib$_libraryStem.so';
      yield 'lib$_libraryStem.so';
      return;
    }

    if (io.Platform.isWindows) {
      yield 'rust/target/debug/$_libraryStem.dll';
      yield 'rust/target/release/$_libraryStem.dll';
      yield '.dart_tool/lib/$_libraryStem.dll';
      yield '$_libraryStem.dll';
      return;
    }

    yield 'rust/target/debug/lib$_libraryStem.dylib';
    yield 'rust/target/release/lib$_libraryStem.dylib';
    yield '.dart_tool/lib/lib$_libraryStem.dylib';
    yield '$_libraryStem.framework/$_libraryStem';
    yield 'lib$_libraryStem.dylib';
  }
}

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
      yield '.dart_tool/lib/lib$_libraryStem.so';
      yield 'rust/target/debug/lib$_libraryStem.so';
      yield 'rust/target/release/lib$_libraryStem.so';
      yield 'lib$_libraryStem.so';
      return;
    }

    if (io.Platform.isWindows) {
      yield '.dart_tool/lib/$_libraryStem.dll';
      yield 'rust/target/debug/$_libraryStem.dll';
      yield 'rust/target/release/$_libraryStem.dll';
      yield '$_libraryStem.dll';
      return;
    }

    yield '.dart_tool/lib/lib$_libraryStem.dylib';
    yield 'rust/target/debug/lib$_libraryStem.dylib';
    yield 'rust/target/release/lib$_libraryStem.dylib';
    yield '$_libraryStem.framework/$_libraryStem';
    yield 'lib$_libraryStem.dylib';
  }
}

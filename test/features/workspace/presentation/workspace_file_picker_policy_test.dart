import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tally_bean/features/workspace/presentation/pages/workspace_file_picker_policy.dart';

void main() {
  group('workspace import picker policy', () {
    test(
      'uses FileType.any on Android to avoid unsupported custom extension',
      () {
        expect(workspaceImportPickerType(TargetPlatform.android), FileType.any);
        expect(
          workspaceImportAllowedExtensions(TargetPlatform.android),
          isNull,
        );
      },
    );

    test('uses custom .beancount filter on non-Android platforms', () {
      expect(workspaceImportPickerType(TargetPlatform.iOS), FileType.custom);
      expect(
        workspaceImportAllowedExtensions(TargetPlatform.iOS),
        const <String>['beancount'],
      );
    });

    test('validates selected entry file extension', () {
      expect(isBeancountEntryFilePath('/tmp/main.beancount'), isTrue);
      expect(isBeancountEntryFilePath('/tmp/MAIN.BEANCOUNT'), isTrue);
      expect(isBeancountEntryFilePath('/tmp/main.txt'), isFalse);
      expect(isBeancountEntryFilePath('/tmp/main'), isFalse);
      expect(isBeancountEntryFilePath(null), isFalse);
    });
  });
}

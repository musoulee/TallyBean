import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tally_bean/features/ledger/presentation/pages/ledger_file_picker_policy.dart';

void main() {
  group('ledger import picker policy', () {
    test(
      'uses FileType.any on Android to avoid unsupported custom extension',
      () {
        expect(ledgerImportPickerType(TargetPlatform.android), FileType.any);
        expect(ledgerImportAllowedExtensions(TargetPlatform.android), isNull);
      },
    );

    test('uses custom .beancount/.bean filter on non-Android platforms', () {
      expect(ledgerImportPickerType(TargetPlatform.iOS), FileType.custom);
      expect(ledgerImportAllowedExtensions(TargetPlatform.iOS), const <String>[
        'beancount',
        'bean',
      ]);
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

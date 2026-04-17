import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

const List<String> _beancountAllowedExtensions = <String>['beancount'];

FileType workspaceImportPickerType(TargetPlatform platform) {
  if (platform == TargetPlatform.android) {
    return FileType.any;
  }
  return FileType.custom;
}

List<String>? workspaceImportAllowedExtensions(TargetPlatform platform) {
  if (platform == TargetPlatform.android) {
    return null;
  }
  return _beancountAllowedExtensions;
}

bool isBeancountEntryFilePath(String? path) {
  if (path == null) {
    return false;
  }
  return path.toLowerCase().endsWith('.beancount');
}

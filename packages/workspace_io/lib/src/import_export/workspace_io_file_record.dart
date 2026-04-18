class WorkspaceIoFileRecord {
  const WorkspaceIoFileRecord({
    required this.filePath,
    required this.relativePath,
    required this.content,
    required this.sizeBytes,
  });

  final String filePath;
  final String relativePath;
  final String content;
  final int sizeBytes;
}

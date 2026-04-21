class LedgerTextFile {
  const LedgerTextFile({
    required this.fileName,
    required this.relativePath,
    required this.content,
    required this.sizeBytes,
  });

  final String fileName;
  final String relativePath;
  final String content;
  final int sizeBytes;
}

class BridgeParseResultDto {
  const BridgeParseResultDto({required this.workspaceId});

  final String workspaceId;
}

class BridgeValidationIssueDto {
  const BridgeValidationIssueDto({
    required this.message,
    required this.location,
    required this.blocking,
  });

  final String message;
  final String location;
  final bool blocking;
}

class BridgeReportResultDto {
  const BridgeReportResultDto({required this.key, required this.lines});

  final String key;
  final List<String> lines;
}

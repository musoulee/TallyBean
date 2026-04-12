import '../dtos/bridge_dtos.dart';

abstract interface class BeancountBridgeFacade {
  Future<BridgeParseResultDto> parseWorkspace(String rootPath);
  Future<List<BridgeValidationIssueDto>> validateWorkspace(String workspaceId);
  Future<List<BridgeReportResultDto>> buildReports(String workspaceId);
}

class StubBeancountBridgeFacade implements BeancountBridgeFacade {
  const StubBeancountBridgeFacade();

  @override
  Future<List<BridgeReportResultDto>> buildReports(String workspaceId) async {
    return const <BridgeReportResultDto>[];
  }

  @override
  Future<BridgeParseResultDto> parseWorkspace(String rootPath) async {
    return const BridgeParseResultDto(workspaceId: 'household');
  }

  @override
  Future<List<BridgeValidationIssueDto>> validateWorkspace(
    String workspaceId,
  ) async {
    return const <BridgeValidationIssueDto>[];
  }
}

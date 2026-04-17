import 'package:beancount_data/beancount_data.dart';
import 'package:beancount_domain/beancount_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('demo repository exposes fixture-backed workspace data', () async {
    final repository = createDemoBeancountRepository();

    final workspace = await repository.loadCurrentWorkspace();
    final entries = await repository.loadJournalEntries();
    final reports = await repository.loadReportSummaries();

    expect(workspace, isNotNull);
    expect(workspace!.status, WorkspaceStatus.ready);
    expect(entries, isNotEmpty);
    expect(reports, isNotEmpty);
  });
}

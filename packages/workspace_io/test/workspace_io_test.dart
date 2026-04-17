import 'package:flutter_test/flutter_test.dart';
import 'package:workspace_io/workspace_io.dart';

void main() {
  test('memory workspace io returns recent workspaces', () async {
    const facade = MemoryWorkspaceIoFacade();

    final recent = await facade.loadRecentWorkspaces();

    expect(recent.single.name, 'Household Ledger');
  });
}

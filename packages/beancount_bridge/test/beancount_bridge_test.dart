import 'package:beancount_bridge/beancount_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stub bridge facade returns skeleton bridge results', () async {
    const facade = StubBeancountBridgeFacade();

    final parseResult = await facade.parseWorkspace(
      '/ledger',
      '/ledger/main.beancount',
    );
    final issues = await facade.validateWorkspace('household');

    expect(parseResult.workspaceId, 'household');
    expect(issues, isEmpty);
  });
}

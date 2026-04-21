import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tally_bean/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('android startup smoke test reaches the main app shell', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TallyBeanApp());

    // Give router/providers time to settle on device runtime.
    for (var index = 0; index < 30; index++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('首页').evaluate().isNotEmpty) {
        break;
      }
    }

    expect(find.text('首页'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });
}

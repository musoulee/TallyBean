import 'package:flutter_test/flutter_test.dart';

import 'package:tally_bean/main.dart';

void main() {
  testWidgets(
    'default app startup lands on workspace flow instead of overview',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      for (var index = 0; index < 20; index++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('工作区').evaluate().isNotEmpty) {
          break;
        }
      }

      expect(find.text('工作区'), findsOneWidget);
      expect(find.text('净资产'), findsNothing);
    },
  );
}

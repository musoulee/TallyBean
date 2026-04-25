import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tally_design_system/tally_design_system.dart';

void main() {
  testWidgets('renders shared metric and section cards', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTallyTheme(),
        home: const Scaffold(
          body: Column(
            children: [
              TallyMetricCard(
                label: '总资产',
                value: '¥ 142,200',
                accent: Color(0xFF4E6A40),
              ),
              TallySectionCard(
                title: '高级工具',
                child: TallySettingsItem(
                  icon: Icons.code_outlined,
                  title: '纯文本编辑',
                  subtitle: '直接查看或编辑 beancount 文本',
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('总资产'), findsOneWidget);
    expect(find.text('高级工具'), findsOneWidget);
    expect(find.text('纯文本编辑'), findsOneWidget);
  });

  testWidgets('section card keeps titleless trailing actions at the end', (
    WidgetTester tester,
  ) async {
    const trailingKey = Key('section-card-trailing');

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTallyTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: TallySectionCard(
              trailing: IconButton(
                key: trailingKey,
                onPressed: () {},
                icon: const Icon(Icons.add_circle_outline),
              ),
              child: const Text('分录'),
            ),
          ),
        ),
      ),
    );

    final cardRect = tester.getRect(find.byType(Card));
    final trailingRect = tester.getRect(find.byKey(trailingKey));

    expect(cardRect.right - trailingRect.right, lessThan(24));
  });
}

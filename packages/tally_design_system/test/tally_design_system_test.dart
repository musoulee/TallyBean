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
}

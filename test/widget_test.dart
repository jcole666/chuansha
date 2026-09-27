import 'package:flutter_test/flutter_test.dart';

import 'package:chuansha/app.dart';

void main() {
  testWidgets('App should render without errors', (WidgetTester tester) async {
    await tester.pumpWidget(const ChuanshaApp());
    await tester.pumpAndSettle();

    // 初始路由是新手引导页（onboarding），验证页面正常渲染
    expect(find.text('欢迎来到穿啥'), findsOneWidget);
    expect(find.text('开始使用，马上管理衣橱'), findsNothing);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/widgets/app_toast.dart';

void main() {
  Future<void> pumpHost(WidgetTester tester, VoidCallback onTap) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showAppToast(context, '测试提示',
                    duration: const Duration(seconds: 2)),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('居中显示、无 SnackBar 底、文本可见', (tester) async {
    await pumpHost(tester, () {});
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const ValueKey('appToast')), findsOneWidget);
    expect(find.text('测试提示'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing, reason: '不再是底部 SnackBar');

    // 屏幕正中（默认测试窗口 800×600）
    final center = tester.getCenter(find.byKey(const ValueKey('appToast')));
    expect(center.dx, closeTo(400, 1), reason: '水平居中');
    expect(center.dy, closeTo(300, 1), reason: '垂直居中');
  });

  testWidgets('duration 后自动淡出移除', (tester) async {
    await pumpHost(tester, () {});
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('appToast')), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('appToast')), findsNothing);
  });

  testWidgets('连续调用只保留最新一条', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            ctx = context;
            return const SizedBox.expand();
          }),
        ),
      ),
    );
    showAppToast(ctx, '第一条');
    await tester.pump();
    showAppToast(ctx, '第二条');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('第一条'), findsNothing);
    expect(find.text('第二条'), findsOneWidget);
    expect(find.byKey(const ValueKey('appToast')), findsOneWidget);
  });
}

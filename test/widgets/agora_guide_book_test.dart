import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/widgets/agora/agora_guide_book.dart';

Future<void> _pumpBook(
  WidgetTester tester, {
  ValueChanged<String>? onImageTap,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: SizedBox(
            width: 390,
            child: AgoraGuideBook(onImageTap: onImageTap),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('首屏显示第 1 步、页码与四枚指示点', (tester) async {
    await _pumpBook(tester);

    expect(find.text('步骤 1 / 4'), findsOneWidget);
    expect(find.text('注册登录并创建通用项目'), findsOneWidget);
    expect(find.text('左右滑动翻页'), findsOneWidget);
    expect(find.byKey(const ValueKey('agoraBookDot_0')), findsOneWidget);
    expect(find.byKey(const ValueKey('agoraBookDot_3')), findsOneWidget);

    final prev = tester.widget<IconButton>(
      find.byKey(const ValueKey('agoraBookPrev')),
    );
    expect(prev.onPressed, isNull);
  });

  testWidgets('左右滑动翻页，页码同步更新', (tester) async {
    await _pumpBook(tester);

    await tester.drag(
      find.byKey(const ValueKey('agoraBookPageView')),
      const Offset(-280, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('步骤 2 / 4'), findsOneWidget);
    expect(find.text('开通体验版套餐包'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('agoraBookPageView')),
      const Offset(280, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('步骤 1 / 4'), findsOneWidget);
  });

  testWidgets('点击指示点跳转到对应步骤', (tester) async {
    await _pumpBook(tester);

    await tester.tap(find.byKey(const ValueKey('agoraBookDot_3')));
    await tester.pumpAndSettle();

    expect(find.text('步骤 4 / 4'), findsOneWidget);
    expect(find.text('获取 APP ID 和证书'), findsOneWidget);
  });

  testWidgets('点击截图回调图片路径', (tester) async {
    String? tapped;
    await _pumpBook(tester, onImageTap: (image) => tapped = image);

    final ctx = tester.element(find.byType(MaterialApp));
    await tester.runAsync(() => precacheImage(
          const AssetImage('assets/images/agora_step1.png'),
          ctx,
        ));
    await tester.pumpAndSettle();

    final image = find.byKey(const ValueKey('agoraBookImage_0'));
    await tester.ensureVisible(image);
    await tester.tap(image);
    await tester.pump();

    expect(tapped, 'assets/images/agora_step1.png');
  });

  testWidgets('窄屏下不溢出', (tester) async {
    await _pumpBook(tester, size: const Size(320, 640));

    expect(tester.takeException(), isNull);
    expect(find.text('步骤 1 / 4'), findsOneWidget);
  });
}

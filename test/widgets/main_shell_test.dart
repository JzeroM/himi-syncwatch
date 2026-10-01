import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/core/router.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';

import '../helpers/test_fakes.dart';

Future<void> pumpApp(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  late GoRouter router;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => FakeSettingsNotifier(const AppSettings())),
        embyAuthServiceProvider.overrideWith((ref) => FakeEmbyAuthService()),
        embyServiceProvider.overrideWith((ref) => FakeEmbyService()),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          router = ref.watch(appRouterProvider);
          return MaterialApp.router(routerConfig: router);
        },
      ),
    ),
  );
  // 手动推进帧：首页含循环 shimmer 动画，pumpAndSettle 会超时
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('桌面宽度显示吊绳与百叶窗抽屉，可展开收回', (tester) async {
    await pumpApp(tester, const Size(1280, 720));

    // 桌面：无底部胶囊导航，有吊绳
    expect(find.byKey(const ValueKey('shellNavBarPadding')), findsNothing);
    expect(find.byKey(const ValueKey('blindNavRope')), findsOneWidget);

    // 点吊绳 → 百叶窗展开，四个导航项逐片翻开
    await tester.tap(find.byKey(const ValueKey('blindNavRope')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('blindNavPanel')), findsOneWidget);
    expect(find.text('首页'), findsWidgets);
    expect(find.text('Emby服务器'), findsOneWidget);
    expect(find.text('声网配置'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);

    // 再点吊绳 → 收回，导航项翻出消失
    await tester.tap(find.byKey(const ValueKey('blindNavRope')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('blindNavPanel')), findsNothing);
    expect(find.text('Emby服务器'), findsNothing);
  });

  testWidgets('点导航项切换分支并自动收回', (tester) async {
    await pumpApp(tester, const Size(1280, 720));

    await tester.tap(find.byKey(const ValueKey('blindNavRope')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 收回且已切到设置分支
    expect(find.byKey(const ValueKey('blindNavPanel')), findsNothing);
    expect(find.byKey(const ValueKey('settingsPage')), findsOneWidget);
  });

  testWidgets('手机宽度保持底部胶囊导航且无吊绳', (tester) async {
    await pumpApp(tester, const Size(390, 844));

    expect(find.byKey(const ValueKey('shellNavBarPadding')), findsOneWidget);
    expect(find.byKey(const ValueKey('blindNavRope')), findsNothing);
    expect(find.byKey(const ValueKey('blindNavPanel')), findsNothing);
  });
}

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
        settingsProvider.overrideWith(
            (ref) => FakeSettingsNotifier(const AppSettings())),
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

double contentWidth(WidgetTester tester) {
  final box = tester.renderObject<RenderBox>(
    find.byKey(const ValueKey('shellContentArea')),
  );
  return box.size.width;
}

void main() {
  testWidgets('桌面展开抽屉时主内容右移分栏不遮挡，汉堡收回', (tester) async {
    await pumpApp(tester, const Size(1280, 720));

    // 桌面：无底部胶囊导航，有汉堡按钮；抽屉收起时内容占满
    expect(find.byKey(const ValueKey('shellNavBarPadding')), findsNothing);
    expect(find.byKey(const ValueKey('drawerToggle')), findsOneWidget);
    expect(find.text('Emby服务器'), findsNothing);
    expect(contentWidth(tester), 1280);

    // 点汉堡 → 抽屉展开，主内容区右移 240（1280-240=1040，零遮挡）
    await tester.tap(find.byKey(const ValueKey('drawerToggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('首页'), findsWidgets);
    expect(find.text('Emby服务器'), findsOneWidget);
    expect(find.text('声网配置'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(contentWidth(tester), 1040);

    // 再点汉堡 → 收回，内容回填占满
    await tester.tap(find.byKey(const ValueKey('drawerToggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Emby服务器'), findsNothing);
    expect(contentWidth(tester), 1280);
  });

  testWidgets('点导航项切分支且抽屉保持展开，手动点汉堡才收回', (tester) async {
    await pumpApp(tester, const Size(1280, 720));

    await tester.tap(find.byKey(const ValueKey('drawerToggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 已切到设置分支，抽屉仍展开（手动收回）
    expect(find.byKey(const ValueKey('settingsPage')), findsOneWidget);
    expect(find.text('Emby服务器'), findsOneWidget);
    expect(contentWidth(tester), 1040);

    // 手动点汉堡收回
    await tester.tap(find.byKey(const ValueKey('drawerToggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Emby服务器'), findsNothing);
    expect(find.byKey(const ValueKey('settingsPage')), findsOneWidget);
  });

  testWidgets('手机宽度保持底部胶囊导航且无汉堡无抽屉', (tester) async {
    await pumpApp(tester, const Size(390, 844));

    expect(find.byKey(const ValueKey('shellNavBarPadding')), findsOneWidget);
    expect(find.byKey(const ValueKey('drawerToggle')), findsNothing);
    expect(find.byKey(const ValueKey('shellContentArea')), findsNothing);
  });
}

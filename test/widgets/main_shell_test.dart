import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/core/router.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/agora/agora_config_screen.dart';
import 'package:himi_syncwatch/screens/home/home_screen.dart';
import 'package:himi_syncwatch/screens/shell/main_shell.dart';
import 'package:himi_syncwatch/screens/shell/shell_side_drawer.dart';
import 'package:himi_syncwatch/screens/shell/tv_top_nav_bar.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;

import '../helpers/test_fakes.dart';

/// 捕获 SystemChannels.platform 调用（断言 SystemNavigator.pop 是否触发）。
List<MethodCall> _mockPlatform(WidgetTester tester) {
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      calls.add(call);
      return null;
    },
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  return calls;
}

bool _exited(List<MethodCall> calls) =>
    calls.any((c) => c.method == 'SystemNavigator.pop');

Future<void> pumpApp(
  WidgetTester tester,
  Size size, {
  AppSettings settings = const AppSettings(),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  late GoRouter router;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => FakeSettingsNotifier(settings)),
        embyAuthServiceProvider.overrideWith((ref) => FakeEmbyAuthService()),
        embyServiceProvider.overrideWith((ref) => FakeEmbyService()),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          router = ref.watch(appRouterProvider);
          // 与生产（core/app.dart）一致：提供 GlassBackgroundSource 所需的采样键
          return lg.LiquidGlassScope(
            child: MaterialApp.router(routerConfig: router),
          );
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

    // 桌面：无底部胶囊导航，有左缘窄把手；抽屉收起时内容占满
    expect(find.byKey(const ValueKey('shellNavBarPadding')), findsNothing);
    expect(find.byKey(const ValueKey('drawerToggle')), findsOneWidget);
    expect(find.text('Emby服务器'), findsNothing);
    expect(contentWidth(tester), 1280);

    // 把手：左缘垂直居中，只露 18×64
    final handle = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('drawerToggle')),
    );
    expect(handle.size.width, 18);
    expect(handle.size.height, 64);
    expect(handle.localToGlobal(Offset.zero).dx, 0);
    expect(handle.localToGlobal(Offset.zero).dy, closeTo(720 / 2 - 32, 1));

    // 底层渐变全宽（抽屉区与内容区同一张背景）
    final bg = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('shellBackground')),
    );
    expect(bg.size.width, 1280);

    // 点把手 → 抽屉展开，主内容区右移 240（1280-240=1040，零遮挡）
    await tester.tap(find.byKey(const ValueKey('drawerToggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('首页'), findsWidgets);
    expect(find.text('Emby服务器'), findsOneWidget);
    expect(find.text('声网配置'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(contentWidth(tester), 1040);

    // 展开后渐变仍全宽连续
    expect(bg.size.width, 1280);

    // 再点把手 → 收回，内容回填占满
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
    // 胶囊底距上移（v1.1.84）：测试环境无安全区 → 20（原 4）
    final padding = tester
        .widget<Padding>(find.byKey(const ValueKey('shellNavBarPadding')));
    expect((padding.padding as EdgeInsets).bottom, 20, reason: '胶囊继续上移，不贴屏底');
  });

  group('navBottomGap（胶囊底距上移 v1.1.84）', () {
    test('无安全区 / 手势条（<40）：统一 20', () {
      expect(MainShell.navBottomGap(0), 20, reason: '原 4，两轮上移');
      expect(MainShell.navBottomGap(34), 20, reason: '原 6，两轮上移');
    });

    test('三键虚拟按键（≥40）：紧贴其上沿 +12', () {
      expect(MainShell.navBottomGap(40), 52, reason: '原 +2，上移 10');
      expect(MainShell.navBottomGap(80), 92);
    });
  });

  testWidgets('TV 模式隐藏声网分支：停在声网页时自动回首页', (tester) async {
    // 非 TV 进入声网分支（currentIndex==2），再打开 TV 模式
    await pumpApp(tester, const Size(390, 844));
    await tester.tap(find.text('声网配置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AgoraConfigScreen), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MainShell)),
    );
    container.read(settingsProvider.notifier).update(tvMode: true);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 顶栏接管 + 声网页不可达，兜底回首页
    expect(find.byType(TvTopNavBar), findsOneWidget);
    expect(find.byType(AgoraConfigScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('TV 模式窄宽度（<1000）用顶部横排导航，无底部胶囊无桌面把手', (tester) async {
    // 模拟高 DPI 盒子：逻辑宽度 960 < 1000，未特判会落入底部胶囊
    await pumpApp(
      tester,
      const Size(960, 540),
      settings: const AppSettings(tvMode: true),
    );
    await tester.pump();

    expect(find.byType(TvTopNavBar), findsOneWidget);
    expect(find.byKey(const ValueKey('shellNavBarPadding')), findsNothing);
    expect(find.byKey(const ValueKey('drawerToggle')), findsNothing);
    expect(
      find.descendant(
          of: find.byType(TvTopNavBar), matching: find.text('HIMI')),
      findsOneWidget,
    );
    // 首页并入标题：顶栏不再有「首页」导航项；TV 取消房间模式，
    // 顶栏也不再渲染房间入口
    expect(
      find.descendant(of: find.byType(TvTopNavBar), matching: find.text('首页')),
      findsNothing,
    );
    expect(
      find.descendant(
          of: find.byType(TvTopNavBar),
          matching: find.byIcon(Icons.meeting_room_outlined)),
      findsNothing,
    );

    // 点顶部导航切分支（纯图标导航项按图标定位）
    await tester.tap(find.byIcon(kShellNavIcons[3]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('settingsPage')), findsOneWidget);
  });

  testWidgets('TV 模式宽宽度（≥1000）同样用顶部导航，覆盖桌面抽屉', (tester) async {
    await pumpApp(
      tester,
      const Size(1280, 720),
      settings: const AppSettings(tvMode: true),
    );
    await tester.pump();

    expect(find.byType(TvTopNavBar), findsOneWidget);
    expect(find.byKey(const ValueKey('drawerToggle')), findsNothing);
    expect(find.byKey(const ValueKey('shellNavBarPadding')), findsNothing);
    expect(find.byKey(const ValueKey('shellContentArea')), findsNothing);
  });

  testWidgets('TV：设置标签按返回 → 回首页，不退出', (tester) async {
    final calls = _mockPlatform(tester);
    await pumpApp(
      tester,
      const Size(720, 480),
      settings: const AppSettings(tvMode: true),
    );
    await tester.pump();

    await tester.tap(find.byIcon(kShellNavIcons[3]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.byKey(const ValueKey('settingsPage')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('settingsPage')), findsNothing);
    expect(_exited(calls), isFalse, reason: '回首页不退出');
    expect(find.text('再按一次返回退出应用'), findsNothing, reason: '非首页静默回首页，不弹提示');
  });

  testWidgets('TV：首页首按返回仅提示，窗口内再按才退出到桌面', (tester) async {
    final calls = _mockPlatform(tester);
    await pumpApp(
      tester,
      const Size(720, 480),
      settings: const AppSettings(tvMode: true),
    );
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('再按一次返回退出应用'), findsOneWidget);
    expect(_exited(calls), isFalse, reason: '首按不退出');

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(_exited(calls), isTrue, reason: '窗口内第二按退出到桌面');
  });

  testWidgets('非 TV：返回不拦截（平台默认退出，无提示）', (tester) async {
    final calls = _mockPlatform(tester);
    await pumpApp(tester, const Size(390, 844));
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(_exited(calls), isTrue, reason: '保持平台默认行为');
    expect(find.text('再按一次返回退出应用'), findsNothing);
  });
}

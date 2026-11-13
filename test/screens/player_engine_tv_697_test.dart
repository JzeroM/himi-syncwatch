import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/cache_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/engine_config_screen.dart';
import 'package:himi_syncwatch/screens/settings/engine_detail_screen.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart';
import 'package:himi_syncwatch/services/player/player_engine.dart';

import '../helpers/cache_fakes.dart';
import '../helpers/test_fakes.dart';

/// 697：三个真机问题回归。
///
/// ## 1. 鸿蒙竖屏状态栏遮挡顶栏
///
/// 此前只有 `_switchToLandscape()` 调 `immersiveSticky`，竖屏进入播放器
/// 时系统栏仍是 `edgeToEdge` → 状态栏浮在画面上压住顶栏控件。
///
/// ## 2. 安卓 TV 切换引擎提示「当前平台不支持」
///
/// `isSupported(target)` 漏传 `tvMode`，默认 `false` → Android 只认
/// `[mpv]` → TV 上点 MDK/Erika 全被拦。
///
/// ## 3. TV 引擎设置焦点切不到别的引擎
///
/// 分段胶囊用 `Focus(canRequestFocus: false)`，节点永远拿不到焦点，
/// `onKeyEvent` 的左右键处理是死代码。改为纵向板块 + 独立子页。
void main() {
  String read(String p) => File(p).readAsStringSync();

  String codeOnly(String s) => s
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*');
      })
      .join('\n');

  group('1. 播放器沉浸模式（鸿蒙竖屏状态栏）', () {
    late String player;

    setUpAll(() => player = read('lib/screens/player/player_screen.dart'));

    test('1.1 提供统一的 _enterImmersive 入口', () {
      expect(codeOnly(player), contains('void _enterImmersive()'));
      expect(codeOnly(player),
          contains('SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky)'));
    });

    test('1.2 initState 进播放器即进入沉浸模式', () {
      final initState = player.substring(
        player.indexOf('void initState()'),
        player.indexOf('void initState()') + 1200,
      );
      expect(initState, contains('_enterImmersive()'));
      // 首帧后再补一次（部分平台首个 frame 前设置会被重置）
      expect(initState, contains('addPostFrameCallback'));
    });

    test('1.3 切横屏走沉浸模式', () {
      final fn = player.substring(
        player.indexOf('void _switchToLandscape'),
        player.indexOf('void _switchToLandscape') + 700,
      );
      expect(fn, contains('_enterImmersive()'));
    });

    test('1.4 切回竖屏**不再**退回 edgeToEdge（bug 根因）', () {
      final fn = player.substring(
        player.indexOf('void _toggleOrientation'),
        player.indexOf('void _toggleOrientation') + 700,
      );
      // 697 前这里是 setEnabledSystemUIMode(SystemUiMode.edgeToEdge)
      expect(fn, isNot(contains('SystemUiMode.edgeToEdge')));
      expect(fn, contains('_enterImmersive()'));
    });

    test('1.5 退出播放器仍恢复系统栏（不能把沉浸泄漏到别的页面）', () {
      // dispose 里的 edgeToEdge 必须保留——否则返回详情页后状态栏仍隐藏
      final disposeIdx = player.indexOf('SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)');
      expect(disposeIdx, greaterThan(0),
          reason: '退出播放器必须恢复 edgeToEdge');
    });
  });

  group('2. TV 切换引擎（isSupported 漏传 tvMode）', () {
    late String player;

    setUpAll(() => player = read('lib/screens/player/player_screen.dart'));

    test('2.1 _switchPlayerKernel 传入真实 tvMode', () {
      final fn = player.substring(
        player.indexOf('Future<void> _switchPlayerKernel'),
        player.indexOf('Future<void> _switchPlayerKernel') + 900,
      );
      expect(fn, contains('ref.read(settingsProvider).tvMode'));
      expect(fn, contains('isSupported(target, tvMode: tvMode)'));
      // 不允许再出现不带 tvMode 的调用
      expect(fn, isNot(contains('isSupported(target))')));
    });

    test('2.2 安卓 TV 支持三引擎，安卓手机只 MPV', () {
      // 直接验证工厂契约（isSupported 的默认值陷阱来源）
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final tv = PlayerEngineFactory.supportedEngines(tvMode: true);
        expect(tv, containsAll(<PlayerEngine>[
          PlayerEngine.mdk,
          PlayerEngine.erika,
          PlayerEngine.mpv,
        ]));

        final phone = PlayerEngineFactory.supportedEngines(tvMode: false);
        expect(phone, [PlayerEngine.mpv]);

        // 漏传 tvMode 时会把 MDK 判成不支持——这正是原 bug
        expect(PlayerEngineFactory.isSupported(PlayerEngine.mdk), isFalse,
            reason: '默认 tvMode=false 只认 MPV（原 bug 现场）');
        expect(
            PlayerEngineFactory.isSupported(PlayerEngine.mdk, tvMode: true),
            isTrue,
            reason: '传对 tvMode 后 TV 应支持 MDK');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('3. TV 引擎板块 + 独立子页', () {
    /// 平台覆盖必须在**测试体内**复位：框架在测试体结束时就校验
    /// 「foundation debug 变量未被修改」，`addTearDown` / `tearDown`
    /// 的回调都晚于该断言。
    Future<ProviderContainer> pumpTv(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(overrides: [
        settingsProvider.overrideWith(
            (ref) => FakeSettingsNotifier(const AppSettings(tvMode: true))),
        appCacheServiceProvider
            .overrideWithValue(FakeAppCacheService(cacheSnapshot())),
      ]);
      addTearDown(container.dispose);

      // 路径必须与生产一致（`_openEngineDetail` 里写的是完整路径）
      final router = GoRouter(
        initialLocation: '/settings/player/engine-config',
        routes: [
          GoRoute(
            path: '/settings/player/engine-config',
            builder: (c, s) => const EngineConfigScreen(),
            routes: [
              GoRoute(
                path: ':engineId',
                builder: (c, s) => EngineDetailScreen(
                  engine: PlayerEngine.fromId(s.pathParameters['engineId']),
                ),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();
      return container;
    }

    test('3.1 分段胶囊已移除（canRequestFocus: false 的死代码根因）', () {
      final screen =
          codeOnly(read('lib/screens/settings/engine_config_screen.dart'));
      expect(screen, isNot(contains('_EngineSegmentedSelector')));
      expect(screen, isNot(contains('canRequestFocus: false')));
    });

    testWidgets('3.2 TV 展示三个纵向引擎板块', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
      await pumpTv(tester);

      expect(find.byKey(const ValueKey('engineBoardList')), findsOneWidget);
      for (final e in [
        PlayerEngine.mdk,
        PlayerEngine.erika,
        PlayerEngine.mpv,
      ]) {
        expect(find.byKey(ValueKey('engineBoard_${e.id}')), findsOneWidget,
            reason: '${e.label} 板块应存在');
      }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('3.3 板块纵向排列（上下键可遍历）', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
      await pumpTv(tester);

      final ys = [
        for (final e in [PlayerEngine.mdk, PlayerEngine.erika, PlayerEngine.mpv])
          tester.getTopLeft(find.byKey(ValueKey('engineBoard_${e.id}'))).dy,
      ];
      expect(ys[0], lessThan(ys[1]));
      expect(ys[1], lessThan(ys[2]));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('3.4 点板块进独立子页（不再内嵌切换）', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
      await pumpTv(tester);

      await tester.tap(find.byKey(const ValueKey('engineBoard_mdk')));
      await tester.pumpAndSettle();

      // 子页 key 带引擎 id
      expect(find.byKey(const ValueKey('engineDetailPage_mdk')), findsOneWidget);
      // 板块列表已不在当前页
      expect(find.byKey(const ValueKey('engineBoardList')), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('3.5 子页展示该引擎专属设置', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
      await pumpTv(tester);

      await tester.tap(find.byKey(const ValueKey('engineBoard_mdk')));
      await tester.pumpAndSettle();

      // MDK 专属项（音频后端是 MDK 独有）
      await tester.scrollUntilVisible(
        find.text('音频后端'),
        250,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('settingsSubPageList')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('音频后端'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('3.6 返回后回到板块列表', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
      await pumpTv(tester);

      await tester.tap(find.byKey(const ValueKey('engineBoard_erika')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('engineDetailPage_erika')), findsOneWidget);

      // 模拟系统返回
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('engineBoardList')), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('3.7 路由表含引擎子页', () {
      final router = read('lib/core/router.dart');
      expect(router, contains("path: ':engineId'"));
      expect(router, contains('EngineDetailScreen'));
      expect(router, contains('PlayerEngine.fromId'));
    });

    test('3.9 返回后焦点回到进入时那个板块', () {
      final screen =
          codeOnly(read('lib/screens/settings/engine_config_screen.dart'));
      // 必须持有板块 FocusNode 并在返回后 requestFocus
      expect(screen, contains('_boardFocusNodes'));
      expect(screen, contains('node.requestFocus()'));
      // 焦点恢复要等一帧（push 返回时退出动画未结束，立即请求会被丢弃）
      expect(screen, contains('addPostFrameCallback'));
      // FocusNode 必须释放
      expect(screen, contains('node.dispose()'));
    });

    test('3.8 非 TV 平台仍用 TabBar（未改动）', () {
      final screen = codeOnly(read('lib/screens/settings/engine_config_screen.dart'));
      expect(screen, contains('TabBarView('));
      expect(screen, contains('EngineTabBody(engine: e)'));
    });
  });
}

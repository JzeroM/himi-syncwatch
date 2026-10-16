import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_counts.dart';
import 'package:himi_syncwatch/models/server_route.dart';
import 'package:himi_syncwatch/models/tv_device.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/providers/tv_sync_provider.dart';
import 'package:himi_syncwatch/screens/settings/qr_config_screen.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_visibility.dart';
import 'package:himi_syncwatch/screens/servers/server_manager_screen.dart';
import 'package:himi_syncwatch/services/emby_service.dart';
import 'package:himi_syncwatch/services/tv_sync/paired_tv_store.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/server_card.dart';
import 'package:himi_syncwatch/widgets/tv/tv_directional_scroll.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

import '../helpers/test_fakes.dart';

/// 固定返回预置配对 TV 的 store（不触碰 secure storage）。
class _StaticPairedTvStore extends PairedTvStore {
  _StaticPairedTvStore(this._tv);

  final PairedTv? _tv;

  @override
  Future<PairedTv?> load() async => _tv;

  @override
  Future<void> save(PairedTv tv) async {}

  @override
  Future<void> clear() async {}
}

EmbyServerConfig _server({
  required String id,
  required String name,
  required String serverId,
  bool authenticated = true,
}) {
  return EmbyServerConfig(
    id: id,
    serverUrl: 'https://$id.example.com',
    serverName: name,
    serverId: serverId,
    username: 'user',
    accessToken: authenticated ? 'token' : null,
    userId: authenticated ? 'uid' : null,
  );
}

/// 挂最小 GoRouter：`/servers` → 服务器页，`/` → 首页替身
/// （点击卡片 context.go('/') 跳首页断言用）。
Future<ProviderContainer> _pumpScreen(
  WidgetTester tester, {
  List<EmbyServerConfig> servers = const [],
  FakeEmbyAuthService? auth,
  AppSettings settings = const AppSettings(),
  EmbyService Function(EmbyServerConfig)? serviceFactory,
  PairedTv? pairedTv,
  bool remote = false,
}) async {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier(settings)),
      embyAuthServiceProvider
          .overrideWith((ref) => auth ?? FakeEmbyAuthService()),
      embyServerListProvider
          .overrideWith((ref) => EmbyServerListNotifier()..setList(servers)),
      pairedTvProvider.overrideWith(
        (ref) => PairedTvNotifier(
          store: _StaticPairedTvStore(pairedTv),
        ),
      ),
      if (serviceFactory != null)
        embyServiceFactoryProvider.overrideWithValue(serviceFactory),
    ],
  );
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: '/servers',
    routes: [
      GoRoute(
        path: '/servers',
        builder: (_, __) => const ServerManagerScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: Center(child: Text('首页替身'))),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: remote
          ? TvRemoteShortcuts(child: MaterialApp.router(routerConfig: router))
          : MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _settleSnackbars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

/// 模拟 TV 遥控器长按 OK 键（按下 → 等 600ms → 松开）。
Future<void> _pressLongOk(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
  await tester.pump(const Duration(milliseconds: 600));
  await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('空列表显示引导提示', (tester) async {
    await _pumpScreen(tester);

    expect(find.text('Emby 服务器'), findsOneWidget);
    expect(find.text('暂无服务器\n点击右上角 + 添加'), findsOneWidget);
  });

  testWidgets('展示服务器列表并标记当前服务器', (tester) async {
    await _pumpScreen(
      tester,
      servers: [
        _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
        _server(id: 'srv_b', name: '备用服务器', serverId: 's2'),
      ],
    );

    expect(find.text('家庭NAS'), findsOneWidget);
    expect(find.text('备用服务器'), findsOneWidget);
    expect(find.byType(ServerListCard), findsNWidgets(2));
  });

  testWidgets('点击未激活卡片切换服务器并跳首页（v1.1.236）', (tester) async {
    final auth = FakeEmbyAuthService();
    final container = await _pumpScreen(
      tester,
      auth: auth,
      servers: [
        _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
        _server(id: 'srv_b', name: '备用服务器', serverId: 's2'),
      ],
    );

    await tester.tap(find.text('备用服务器'));
    await tester.pumpAndSettle();

    expect(container.read(embyConfigProvider)?.id, 'srv_b');
    expect(auth.selectedServerId, 'srv_b');
    expect(find.text('首页替身'), findsOneWidget,
        reason: '点击卡片应跳回首页 tab');
    await _settleSnackbars(tester);
  });

  testWidgets('点击激活卡片直接跳首页且不切换（v1.1.236）', (tester) async {
    final auth = FakeEmbyAuthService();
    final container = await _pumpScreen(
      tester,
      auth: auth,
      servers: [
        _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
        _server(id: 'srv_b', name: '备用服务器', serverId: 's2'),
      ],
    );
    container.read(embyConfigProvider.notifier).setConfig(
          container.read(embyServerListProvider).first,
        );
    await tester.pump();

    await tester.tap(find.text('家庭NAS'));
    await tester.pumpAndSettle();

    expect(container.read(embyConfigProvider)?.id, 'srv_a',
        reason: '激活卡点击不切换服务器');
    expect(auth.selectedServerId, isNull, reason: '未发生切换，不写选中 id');
    expect(find.text('首页替身'), findsOneWidget);
    await _settleSnackbars(tester);
  });

  testWidgets('进页自动拉取延迟与计数并渲染（v1.1.236）', (tester) async {
    final fake = FakeEmbyService(
      itemCounts: const MediaCounts(movies: 123, series: 45, episodes: 678),
      pingLatencyMs: 30,
    );
    await _pumpScreen(
      tester,
      servers: [
        _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
        _server(id: 'srv_b', name: '备用服务器', serverId: 's2'),
      ],
      serviceFactory: (_) => fake,
    );

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('123'), findsNWidgets(2));
    expect(find.text('45'), findsNWidgets(2));
    expect(find.textContaining('ms'), findsNWidgets(2));
  });

  testWidgets('视图切换：列表 ⇄ 网格并落盘偏好（v1.1.236）', (tester) async {
    final container = await _pumpScreen(
      tester,
      servers: [
        _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
        _server(id: 'srv_b', name: '备用服务器', serverId: 's2'),
      ],
    );

    expect(find.byType(ServerListCard), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('serverViewToggle')));
    await tester.pumpAndSettle();

    expect(find.byType(ServerGridCard), findsNWidgets(2));
    expect(find.byType(ServerListCard), findsNothing);
    expect(container.read(settingsProvider).serverViewMode, 'grid');

    await tester.tap(find.byKey(const ValueKey('serverViewToggle')));
    await tester.pumpAndSettle();

    expect(find.byType(ServerListCard), findsNWidgets(2));
    expect(container.read(settingsProvider).serverViewMode, 'list');
  });

  testWidgets('网格视图渲染延迟与计数（v1.1.236）', (tester) async {
    final fake = FakeEmbyService(
      itemCounts: const MediaCounts(movies: 10, series: 5, episodes: 30),
      pingLatencyMs: 20,
    );
    await _pumpScreen(
      tester,
      settings: const AppSettings(serverViewMode: 'grid'),
      servers: [
        _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
        _server(id: 'srv_b', name: '备用服务器', serverId: 's2'),
      ],
      serviceFactory: (_) => fake,
    );

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.byType(ServerGridCard), findsNWidgets(2));
    expect(find.text('10'), findsNWidgets(2));
    expect(find.text('5'), findsNWidgets(2));
    expect(find.textContaining('ms'), findsNWidgets(2));
  });

  testWidgets('列表拖拽把手重排并持久化顺序（v1.1.237）', (tester) async {
    final auth = FakeEmbyAuthService();
    final container = await _pumpScreen(
      tester,
      auth: auth,
      servers: [
        _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
        _server(id: 'srv_b', name: '备用服务器', serverId: 's2'),
      ],
    );

    // 单条连续手势：按下第二张卡的拖拽把手 → 拖到第一张卡把手上
    final handle = find.descendant(
      of: find.byKey(const ValueKey('serverTile_srv_b')),
      matching: find.byIcon(Icons.drag_handle),
    );
    final firstHandle = find.descendant(
      of: find.byKey(const ValueKey('serverTile_srv_a')),
      matching: find.byIcon(Icons.drag_handle),
    );
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(tester.getCenter(firstHandle));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();

    final ids =
        container.read(embyServerListProvider).map((s) => s.id).toList();
    expect(ids, ['srv_b', 'srv_a'],
        reason: '拖拽把手应可重排列表顺序');
    expect(auth.lastSavedServerOrder, ['srv_b', 'srv_a']);
  });

  testWidgets('网格长按拖拽重排并持久化顺序（v1.1.237）', (tester) async {
    final auth = FakeEmbyAuthService();
    final container = await _pumpScreen(
      tester,
      auth: auth,
      settings: const AppSettings(serverViewMode: 'grid'),
      servers: [
        _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
        _server(id: 'srv_b', name: '备用服务器', serverId: 's2'),
      ],
    );

    // 单条连续手势：长按第二张网格卡 → 拖到第一张卡上
    final fromCard = find.byKey(const ValueKey('serverGridTile_srv_b'));
    final toCard = find.byKey(const ValueKey('serverGridTile_srv_a'));
    final gesture = await tester.startGesture(tester.getCenter(fromCard));
    await tester.pump(const Duration(milliseconds: 600)); // 超过长按阈值
    await gesture.moveTo(tester.getCenter(toCard));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final ids =
        container.read(embyServerListProvider).map((s) => s.id).toList();
    expect(ids, ['srv_b', 'srv_a'],
        reason: '网格长按拖拽应可重排顺序');
    expect(auth.lastSavedServerOrder, ['srv_b', 'srv_a']);
  });

  testWidgets('面板展开含占位项且无上移（v1.1.237）', (tester) async {
    await _pumpScreen(
      tester,
      servers: [
        _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
        _server(id: 'srv_b', name: '备用服务器', serverId: 's2'),
      ],
    );

    await tester.tap(find.byKey(const ValueKey('serverMore_srv_b')));
    await tester.pumpAndSettle();

    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('切换线路'), findsOneWidget);
    expect(find.text('更换图标'), findsOneWidget);
    expect(find.text('资源统计'), findsOneWidget);
    expect(find.text('资源设置'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    expect(find.text('上移'), findsNothing, reason: '上移项已移除');
  });

  testWidgets('非激活服务器面板也有编辑项（v1.1.237）', (tester) async {
    final container = await _pumpScreen(
      tester,
      servers: [
        _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
        _server(id: 'srv_b', name: '备用服务器', serverId: 's2'),
      ],
    );
    container.read(embyConfigProvider.notifier).setConfig(
          container.read(embyServerListProvider).first,
        );
    await tester.pump();

    // srv_b 非激活，其面板仍应有编辑
    await tester.tap(find.byKey(const ValueKey('serverMore_srv_b')));
    await tester.pumpAndSettle();

    expect(find.text('编辑'), findsOneWidget,
        reason: '非激活服务器面板也应有编辑项');
  });

  testWidgets('点击「切换线路」打开线路管理弹层（v1.1.242）', (tester) async {
    await _pumpScreen(
      tester,
      servers: [
        _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
        _server(id: 'srv_b', name: '备用服务器', serverId: 's2'),
      ],
    );

    await tester.tap(find.byKey(const ValueKey('serverMore_srv_b')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('切换线路'));
    await tester.pumpAndSettle();

    // 弹层内容：主线路 tile + 添加线路按钮
    expect(find.byKey(const Key('routeTile_main')), findsOneWidget);
    expect(find.byKey(const Key('addRouteButton')), findsOneWidget);
    expect(find.text('功能开发中'), findsNothing);
  });

  testWidgets('点击面板外空白关闭面板（v1.1.237）', (tester) async {
    await _pumpScreen(
      tester,
      servers: [
        _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
        _server(id: 'srv_b', name: '备用服务器', serverId: 's2'),
      ],
    );

    await tester.tap(find.byKey(const ValueKey('serverMore_srv_b')));
    await tester.pumpAndSettle();
    expect(find.text('删除'), findsOneWidget);

    // 点击屏幕左上角空白处（barrier 区域）
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.text('删除'), findsNothing, reason: '点击外部应关闭面板');
  });

  testWidgets('网格卡用户名与头像同行、名称在下一行（v1.1.237）', (tester) async {
    await _pumpScreen(
      tester,
      settings: const AppSettings(serverViewMode: 'grid'),
      servers: [
        _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
        _server(id: 'srv_b', name: '备用服务器', serverId: 's2'),
      ],
    );
    await tester.pumpAndSettle();

    final avatarFinder = find.descendant(
      of: find.byKey(const ValueKey('serverGridTile_srv_a')),
      matching: find.byType(ServerAvatar),
    );
    final usernameFinder = find.descendant(
      of: find.byKey(const ValueKey('serverGridTile_srv_a')),
      matching: find.text('user'),
    );
    final labelFinder = find.descendant(
      of: find.byKey(const ValueKey('serverGridTile_srv_a')),
      matching: find.text('家庭NAS'),
    );

    final avatarCenter = tester.getCenter(avatarFinder);
    final usernameCenter = tester.getCenter(usernameFinder);
    final labelCenter = tester.getCenter(labelFinder);

    expect((avatarCenter.dy - usernameCenter.dy).abs(), lessThan(8),
        reason: '用户名应与头像在同一行（y 坐标接近）');
    expect(labelCenter.dy, greaterThan(usernameCenter.dy),
        reason: '服务器名称应在用户名下方');
  });

  testWidgets('刷新按钮重测延迟与计数（v1.1.236）', (tester) async {
    var factoryCalls = 0;
    final fake = FakeEmbyService(
      itemCounts: const MediaCounts(movies: 1, series: 2, episodes: 3),
      pingLatencyMs: 10,
    );
    await _pumpScreen(
      tester,
      servers: [
        _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
      ],
      serviceFactory: (_) {
        factoryCalls++;
        return fake;
      },
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    final callsAfterLoad = factoryCalls;
    expect(callsAfterLoad, greaterThan(0));

    await tester.tap(find.byKey(const ValueKey('serverStatsRefresh')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(factoryCalls, greaterThan(callsAfterLoad),
        reason: '刷新应重新走服务工厂测延迟/拉计数');
  });

  testWidgets('扫码图标进入手机配置页（仅 TV 模式显示）', (tester) async {
    await _pumpScreen(tester, settings: const AppSettings(tvMode: true));

    await tester.tap(find.byTooltip('手机扫码配置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(QrConfigScreen), findsOneWidget);

    Navigator.of(tester.element(find.byType(QrConfigScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(QrConfigScreen), findsNothing);
  });

  testWidgets('非 TV 模式隐藏扫码入口（手动输入服务器）', (tester) async {
    await _pumpScreen(tester);

    expect(find.byTooltip('手机扫码配置'), findsNothing);
    // 手动添加入口不受影响
    expect(find.byTooltip('添加服务器'), findsOneWidget);
  });

  testWidgets('TV 模式隐藏「+」添加入口（输入走扫码，v1.1.177）', (tester) async {
    await _pumpScreen(tester, settings: const AppSettings(tvMode: true));

    expect(find.byTooltip('添加服务器'), findsNothing);
    expect(find.byTooltip('手机扫码配置'), findsOneWidget,
        reason: 'TV 添加服务器统一走扫码');
  });

  testWidgets('点击 + 展开添加服务器表单', (tester) async {
    await _pumpScreen(tester);

    await tester.tap(find.byTooltip('添加服务器'));
    await tester.pumpAndSettle();

    expect(find.text('连接并登录'), findsOneWidget);
    expect(find.text('服务器地址'), findsOneWidget);
  });

  testWidgets('TV 长按 OK 进入布局模式，方向键移动，OK 保存退出（v1.1.237）',
      (tester) async {
    final auth = FakeEmbyAuthService();
    final container = await _pumpScreen(
      tester,
      auth: auth,
      settings: const AppSettings(tvMode: true),
      servers: [
        _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
        _server(id: 'srv_b', name: '备用服务器', serverId: 's2'),
      ],
    );

    // 第一张卡 autofocus 已聚焦，长按 OK 进入布局模式
    await _pressLongOk(tester);
    expect(find.text('移动中'), findsOneWidget, reason: '应进入布局模式');

    // 方向键下移（列表 ±1）
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final ids =
        container.read(embyServerListProvider).map((s) => s.id).toList();
    expect(ids, ['srv_b', 'srv_a'], reason: '方向键下移应交换顺序');

    // 短按 OK 保存退出
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('移动中'), findsNothing, reason: 'OK 键应退出布局模式');
    expect(auth.lastSavedServerOrder, ['srv_b', 'srv_a']);
    await _settleSnackbars(tester);
  });

  testWidgets('TV 布局模式返回键取消并还原顺序（v1.1.237）', (tester) async {
    final auth = FakeEmbyAuthService();
    final container = await _pumpScreen(
      tester,
      auth: auth,
      settings: const AppSettings(tvMode: true),
      servers: [
        _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
        _server(id: 'srv_b', name: '备用服务器', serverId: 's2'),
      ],
    );

    await _pressLongOk(tester);
    expect(find.text('移动中'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      container.read(embyServerListProvider).map((s) => s.id).toList(),
      ['srv_b', 'srv_a'],
      reason: '方向键下移已生效',
    );

    // 返回键取消
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await _settleSnackbars(tester);

    expect(find.text('移动中'), findsNothing, reason: '返回键应退出布局模式');
    expect(
      container.read(embyServerListProvider).map((s) => s.id).toList(),
      ['srv_a', 'srv_b'],
      reason: '取消应还原进入前的顺序',
    );
    expect(auth.lastSavedServerOrder, ['srv_a', 'srv_b'],
        reason: '取消应把原始顺序写回存储');
  });

  group('编辑服务器复用添加表单（v1.1.243）', () {
    testWidgets('点编辑 → 内联表单标题「编辑服务器」且字段预填', (tester) async {
      await _pumpScreen(
        tester,
        servers: [
          _server(id: 'srv_b', name: '备用服务器', serverId: 's2'),
        ],
      );

      await tester.tap(find.byKey(const ValueKey('serverMore_srv_b')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('serverForm_srv_b')), findsOneWidget);
      expect(find.text('编辑服务器'), findsOneWidget);
      expect(find.text('连接并登录'), findsNothing);
      expect(find.text('保存'), findsOneWidget);

      // 字段预填：名称 / 地址 / 用户名
      final texts =
          tester.widgetList<TextField>(find.byType(TextField)).toList();
      final prefilled = texts.map((t) => t.controller?.text).toList();
      expect(prefilled, contains('备用服务器'));
      expect(prefilled, contains('srv_b.example.com'));
      expect(prefilled, contains('user'));
    });

    testWidgets('编辑保存保留备用线路（原 saveSession 丢线路 bug 回归）',
        (tester) async {
      final auth = FakeEmbyAuthService();
      final container = await _pumpScreen(
        tester,
        auth: auth,
        servers: [
          _server(
            id: 'srv_b',
            name: '备用服务器',
            serverId: 's2',
          ).copyWith(
            routes: const [
              ServerRoute(id: 'r1', name: 'Route 1', url: 'http://r1:8096'),
            ],
            activeRouteUrl: 'http://r1:8096',
          ),
        ],
      );

      await tester.tap(find.byKey(const ValueKey('serverMore_srv_b')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('保存'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // 表单收起 + 成功提示（toast 2s 后自动消失，先断言再 settle）
      expect(find.byKey(const ValueKey('serverForm_srv_b')), findsNothing);
      expect(find.byKey(const ValueKey('appToast')), findsOneWidget);
      expect(find.text('服务器已更新'), findsOneWidget);
      await _settleSnackbars(tester);

      final updated = container.read(embyServerListProvider).single;
      expect(updated.routes.map((r) => r.id).toList(), ['r1'],
        reason: '编辑后列表内的备用线路应保留');
      expect(updated.activeRouteUrl, 'http://r1:8096');
      expect(updated.serverName, '备用服务器');

      expect(auth.lastSavedSessionRoutes, isNotNull);
      expect(auth.lastSavedSessionRoutes!.map((r) => r['id']).toList(), ['r1'],
        reason: 'saveSession 必须带上 routes（原实现清空线路的 bug）');
      expect(auth.lastSavedActiveRouteUrl, 'http://r1:8096');
    });

    testWidgets('编辑不改地址时 serverUrl 保持（host:port 重建一致）',
        (tester) async {
      final container = await _pumpScreen(
        tester,
        servers: [
          _server(id: 'srv_b', name: '备用服务器', serverId: 's2'),
        ],
      );

      await tester.tap(find.byKey(const ValueKey('serverMore_srv_b')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('保存'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      await _settleSnackbars(tester);

      final updated = container.read(embyServerListProvider).single;
      expect(updated.serverUrl, 'https://srv_b.example.com:8096',
        reason: 'parseServerUrl 往返后端口默认 8096');
    });

    testWidgets('编辑表单展开时底部导航隐藏，收起恢复（v1.1.243）',
        (tester) async {
      final container = await _pumpScreen(
        tester,
        servers: [
          _server(id: 'srv_b', name: '备用服务器', serverId: 's2'),
        ],
      );

      expect(container.read(shellNavVisibilityProvider), true);

      await tester.tap(find.byKey(const ValueKey('serverMore_srv_b')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      expect(container.read(shellNavVisibilityProvider), false,
        reason: '编辑表单展开 → 导航隐藏');

      // 保存收起 → 导航恢复
      await tester.ensureVisible(find.text('保存'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      await _settleSnackbars(tester);
      expect(container.read(shellNavVisibilityProvider), true,
        reason: '表单收起 → 导航恢复');
    });

    testWidgets('TV 模式点编辑 → 打开扫码配置页（v1.1.243）', (tester) async {
      await _pumpScreen(
        tester,
        settings: const AppSettings(tvMode: true),
        servers: [
          _server(id: 'srv_b', name: '备用服务器', serverId: 's2'),
        ],
      );

      await tester.tap(find.byKey(const ValueKey('serverMore_srv_b')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(QrConfigScreen), findsOneWidget,
        reason: 'TV 无输入法：编辑走扫码配置');

      Navigator.of(tester.element(find.byType(QrConfigScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(QrConfigScreen), findsNothing);
    });

    testWidgets('切走分支（epoch bump）→ 编辑/添加表单收起、导航恢复（v1.1.243）',
        (tester) async {
      final container = await _pumpScreen(
        tester,
        servers: [
          _server(id: 'srv_b', name: '备用服务器', serverId: 's2'),
        ],
      );

      // 展开编辑表单
      await tester.tap(find.byKey(const ValueKey('serverMore_srv_b')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('serverForm_srv_b')), findsOneWidget);
      expect(container.read(shellNavVisibilityProvider), false);

      // 模拟 MainShell 切 tab：bump Emby 分支代数
      container.read(shellBranchEpochProvider.notifier).bump(2);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('serverForm_srv_b')), findsNothing,
        reason: '切走应丢弃未保存的编辑表单');
      expect(container.read(shellNavVisibilityProvider), true,
        reason: '表单收起后导航恢复');

      // 添加表单同样收起
      await tester.tap(find.byTooltip('添加服务器'));
      await tester.pumpAndSettle();
      expect(find.text('连接并登录'), findsOneWidget);
      container.read(shellBranchEpochProvider.notifier).bump(2);
      await tester.pumpAndSettle();
      expect(find.text('连接并登录'), findsNothing);
      expect(container.read(shellNavVisibilityProvider), true);
    });
  });

  group('v1.1.246 网格卡瘦身与激活卡去色', () {
    testWidgets('网格卡 childAspectRatio 1.25（v1.1.246 卡片缩矮）', (tester) async {
      await _pumpScreen(
        tester,
        settings: const AppSettings(serverViewMode: 'grid'),
        servers: [
          _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
        ],
      );

      final grid = tester.widget<GridView>(find.byType(GridView));
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.childAspectRatio, 1.25,
        reason: '网格卡宽高比应为 1.25（原 0.92 卡太高、中间空白多）');
    });

    testWidgets('激活列表卡 tint 为中性 panelTintOf（v1.1.246 不带颜色）',
        (tester) async {
      final container = await _pumpScreen(
        tester,
        servers: [
          _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
          _server(id: 'srv_b', name: '备用服务器', serverId: 's2'),
        ],
      );
      container.read(embyConfigProvider.notifier).setConfig(
            container.read(embyServerListProvider).first,
          );
      await tester.pump();

      final glass = tester.widget<GlassContainer>(
        find.descendant(
          of: find.byType(ServerListCard).first,
          matching: find.byType(GlassContainer),
        ),
      );
      expect(glass.tint, GlassConfig.panelTintOf(),
        reason: '激活卡玻璃应完全中性，不再用彩色 tint');
    });

    testWidgets('激活网格卡 tint 为中性 panelTintOf（v1.1.246 不带颜色）',
        (tester) async {
      final container = await _pumpScreen(
        tester,
        settings: const AppSettings(serverViewMode: 'grid'),
        servers: [
          _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
        ],
      );
      container.read(embyConfigProvider.notifier).setConfig(
            container.read(embyServerListProvider).first,
          );
      await tester.pump();

      final glass = tester.widget<GlassContainer>(
        find.descendant(
          of: find.byType(ServerGridCard),
          matching: find.byType(GlassContainer),
        ),
      );
      expect(glass.tint, GlassConfig.panelTintOf(),
        reason: '激活网格卡玻璃应完全中性');
    });
  });

  group('v1.1.246 TV 点击不跳首页', () {
    testWidgets('TV 点击未激活卡切换服务器但留在 /servers', (tester) async {
      final auth = FakeEmbyAuthService();
      final container = await _pumpScreen(
        tester,
        auth: auth,
        settings: const AppSettings(tvMode: true),
        servers: [
          _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
          _server(id: 'srv_b', name: '备用服务器', serverId: 's2'),
        ],
      );

      // 第一张卡 autofocus 已聚焦，短按 OK = 点击
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      // srv_a 是当前激活卡（列表首项默认无激活，点击首卡切换到 srv_a）
      // 实际上初始 embyConfigProvider 为空，点第一张卡应切换到 srv_a
      expect(container.read(embyConfigProvider)?.id, 'srv_a');
      expect(auth.selectedServerId, 'srv_a');
      expect(find.text('Emby 服务器'), findsOneWidget,
        reason: 'TV 模式点击卡片不应跳首页，留在服务器管理页');
      expect(find.text('首页替身'), findsNothing);
      await _settleSnackbars(tester);
    });

    testWidgets('TV 点击第二张卡（方向键移动后 OK）也不跳首页', (tester) async {
      final container = await _pumpScreen(
        tester,
        settings: const AppSettings(tvMode: true),
        servers: [
          _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
          _server(id: 'srv_b', name: '备用服务器', serverId: 's2'),
        ],
      );

      // 焦点移到第二张卡
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      // 短按 OK 点击第二张卡
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(container.read(embyConfigProvider)?.id, 'srv_b');
      expect(find.text('Emby 服务器'), findsOneWidget,
        reason: 'TV 点击第二张卡也不应跳首页');
      await _settleSnackbars(tester);
    });
  });

  group('v1.1.246 TV 焦点修复', () {
    testWidgets('TV 仅第一张卡 autofocus（多卡抢焦修复）', (tester) async {
      await _pumpScreen(
        tester,
        settings: const AppSettings(tvMode: true),
        servers: [
          _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
          _server(id: 'srv_b', name: '备用服务器', serverId: 's2'),
          _server(id: 'srv_c', name: '第三服务器', serverId: 's3'),
        ],
      );

      // 短按 OK 应触发第一张卡的 _openServer（焦点在首卡）
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ServerManagerScreen)),
        listen: false,
      );
      expect(container.read(embyConfigProvider)?.id, 'srv_a',
        reason: '焦点应在第一张卡，短按 OK 打开首卡');
      await _settleSnackbars(tester);
    });

    testWidgets('TV ⋮ 菜单打开后焦点留在 ⋮（面板高亮由按钮驱动）',
        (tester) async {
      await _pumpScreen(
        tester,
        settings: const AppSettings(tvMode: true),
        servers: [
          _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
        ],
      );

      // 第一张卡已聚焦，tap ⋮ 按钮打开面板
      await tester.tap(find.byKey(const ValueKey('serverMore_srv_a')));
      await tester.pumpAndSettle();

      // 面板打开：首项「编辑」存在
      expect(find.text('编辑'), findsOneWidget, reason: '面板应已打开');

      // v1.2.1：焦点不进入面板（移出卡片会重建卡片→面板被关），
      // 而是留在卡片/⋮；面板项不再承载焦点节点（ExcludeFocus）。
      final focus = FocusManager.instance.primaryFocus;
      expect(focus, isNotNull, reason: '焦点不应悬空');
      expect(focus?.debugLabel, isNot(startsWith('serverPanelItem')),
          reason: '焦点不应下移进面板项');
      expect(find.text('删除'), findsOneWidget, reason: '面板应保持打开');
    });

    testWidgets('TV ⋮ 菜单关闭后焦点回 ⋮ 按钮', (tester) async {
      await _pumpScreen(
        tester,
        settings: const AppSettings(tvMode: true),
        servers: [
          _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
        ],
      );

      await tester.tap(find.byKey(const ValueKey('serverMore_srv_a')));
      await tester.pumpAndSettle();
      expect(find.text('删除'), findsOneWidget, reason: '面板应已打开');

      // 点击面板外 barrier 关闭
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.text('删除'), findsNothing, reason: '面板应已关闭');

      // 焦点回焦 ⋮ 按钮：再次 tap ⋮ 应能重新打开面板（焦点未悬空）
      await tester.tap(find.byKey(const ValueKey('serverMore_srv_a')));
      await tester.pumpAndSettle();
      expect(find.text('删除'), findsOneWidget,
        reason: '面板关闭后 ⋮ 按钮仍可交互（焦点回焦不悬空）');
    });
  });

  group('v1.1.246 线路管理弹层 TV 焦点', () {
    testWidgets('TV 线路 tile 包裹 TvFocusable（焦点环 + OK 切换）', (tester) async {
      await _pumpScreen(
        tester,
        settings: const AppSettings(tvMode: true),
        servers: [
          _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
        ],
      );

      await tester.tap(find.byKey(const ValueKey('serverMore_srv_a')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('切换线路'));
      await tester.pumpAndSettle();

      // 主线路 tile 内应有 TvFocusable（焦点环 + OK 切换）
      final routeTile = find.byKey(const Key('routeTile_main'));
      expect(routeTile, findsOneWidget);
      final tvWrapped = find.descendant(
        of: routeTile,
        matching: find.byType(TvFocusable),
      );
      expect(tvWrapped, findsWidgets,
        reason: 'TV 模式线路 tile 内应有 TvFocusable 焦点环');
    });

    testWidgets('TV 线路弹层测速按钮 autofocus（首项落焦）', (tester) async {
      await _pumpScreen(
        tester,
        settings: const AppSettings(tvMode: true),
        servers: [
          _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
        ],
      );

      await tester.tap(find.byKey(const ValueKey('serverMore_srv_a')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('切换线路'));
      await tester.pumpAndSettle();

      // 测速按钮内应有 TvFocusable 且 autofocus=true
      final measureFinder = find.byKey(const Key('measureAllButton'));
      expect(measureFinder, findsOneWidget);
      final measureTvList = tester
          .widgetList<TvFocusable>(
            find.descendant(of: measureFinder, matching: find.byType(TvFocusable)),
          )
          .toList();
      expect(measureTvList, isNotEmpty,
        reason: '测速按钮应有 TvFocusable');
      expect(measureTvList.first.autofocus, isTrue,
        reason: 'TV 线路弹层打开时测速按钮应 autofocus 落焦');
    });
  });

  group('v1.1.247 拖拽反馈尺寸与 TV 长按焦点修复', () {
    testWidgets('网格拖拽反馈尺寸跟随 aspect 1.25（不再是旧 180×200）',
        (tester) async {
      await _pumpScreen(
        tester,
        settings: const AppSettings(serverViewMode: 'grid'),
        servers: [
          _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
        ],
      );

      // 测试窗口默认 800×600：crossAxisCount = (800/220).floor() = 3
      // cellWidth = (800 - 24 - 20) / 3 = 252；cellHeight = 252 / 1.25 = 201.6
      final draggable = tester.widget<LongPressDraggable<int>>(
        find.byType(LongPressDraggable<int>),
      );
      final material = draggable.feedback as Material;
      final opacity = material.child as Opacity;
      final box = opacity.child as SizedBox;
      expect(box.width, moreOrLessEquals(252),
        reason: '拖拽反馈宽度应为网格单元实际宽度');
      expect(box.height, moreOrLessEquals(201.6),
        reason: '拖拽反馈高度应按 aspect 1.25 计算（修复旧 180×200）');
    });

    testWidgets('TV 长按 OK 进入布局模式后 KeyRepeat 不退出（视图不闪切）',
        (tester) async {
      final container = await _pumpScreen(
        tester,
        settings: const AppSettings(tvMode: true),
        servers: [
          _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
          _server(id: 'srv_b', name: '备用服务器', serverId: 's2'),
        ],
      );

      // 长按 OK：KeyDown 后等 600ms 触发长按 → 进入布局模式
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('移动中'), findsOneWidget, reason: '长按应进入布局模式');

      // 用户仍按住 OK：OS 持续发送 KeyRepeat。修复前 _handleLayoutKey
      // 把 enter 的 KeyRepeat 当作短按退出 → 布局模式立刻退出 → 焦点
      // 回落 scope → 全局 TvScopeEnterIntent 把焦点抢到顶栏 → 视图
      // 切换按钮被反复激活（网格/列表闪切）。
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text('移动中'), findsOneWidget,
        reason: 'KeyRepeat 不应退出布局模式（v1.1.247）');

      // 松开 OK：KeyUp 也不应退出
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('移动中'), findsOneWidget,
        reason: 'KeyUp 不应退出布局模式');

      // 视图模式保持列表（未被顶栏切换按钮改写）
      expect(container.read(settingsProvider).serverViewMode, 'list',
        reason: '长按 OK 期间视图模式不应被切换');
      await _settleSnackbars(tester);
    });

    testWidgets('TV 孤立 KeyUp（无对应 KeyDown）不触发打开服务器', (tester) async {
      final container = await _pumpScreen(
        tester,
        settings: const AppSettings(tvMode: true),
        servers: [
          _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
        ],
      );

      // 只发 KeyUp（模拟焦点中途转移后 OS 补发的孤立抬起）。
      // 修复前 _TvCardFocus 对任意 KeyUp 直接 widget.onTap() →
      // 误切换服务器；修复后仅在见过对应 KeyDown 时才 onTap。
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(container.read(embyConfigProvider), isNull,
        reason: '孤立 KeyUp 不应触发 onTap 打开服务器');
    });

    testWidgets('v1.1.251 布局模式：持续 KeyRepeat 焦点不跳到顶栏（仍在卡片）',
        (tester) async {
      final container = await _pumpScreen(
        tester,
        remote: true, // 挂 TvRemoteShortcuts，复现全局 TvScopeEnterIntent 抢焦点
        settings: const AppSettings(tvMode: true),
        servers: [
          _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
          _server(id: 'srv_b', name: '备用服务器', serverId: 's2'),
        ],
      );

      // 长按 OK 进入布局模式（首卡 autofocus 已获焦）
      final focusBefore = FocusManager.instance.primaryFocus;
      expect(focusBefore, isNotNull);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('移动中'), findsOneWidget, reason: '长按应进入布局模式');

      // 核心不变量：进入布局模式必须复用同一焦点节点，否则旧节点销毁、
      // 焦点瞬时回落到外层 scope → 全局 TvScopeEnterIntent 抢到壳层顶栏。
      expect(identical(FocusManager.instance.primaryFocus, focusBefore), isTrue,
          reason: '进入布局模式不应重建焦点节点（回归 v1.1.251）');

      // 用户仍按住 OK：持续 KeyRepeat，焦点不应被抢到顶栏
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      final focusCtx = FocusManager.instance.primaryFocus?.context;
      expect(focusCtx, isNotNull);
      expect(focusCtx!.findAncestorWidgetOfExactType<AppBar>(), isNull,
          reason: '焦点应留在卡片子树，不应跳到顶栏');
      expect(identical(FocusManager.instance.primaryFocus, focusBefore), isTrue,
          reason: 'KeyRepeat 期间焦点仍在原卡片节点');

      // 方向键应移动卡片（srv_a ↔ srv_b），证明按键落到布局处理器
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final order = container
          .read(embyServerListProvider)
          .map((s) => s.id)
          .take(2)
          .toList();
      expect(order, ['srv_b', 'srv_a'],
          reason: '方向键应移动卡片而非被顶栏吞掉');
      expect(find.text('移动中'), findsOneWidget,
          reason: '移动后仍处于布局模式');
      expect(container.read(settingsProvider).serverViewMode, 'list',
          reason: '视图模式不应被顶栏按钮改写');

      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await _settleSnackbars(tester);
    });
  });

  group('TV 设备同步入口（v1.1.248）', () {
    testWidgets('非 TV 模式顶栏显示 TV 设备按钮，点击打开发现面板', (tester) async {
      await _pumpScreen(
        tester,
        servers: [_server(id: 'srv_a', name: '家庭NAS', serverId: 's1')],
      );

      final btn = find.byKey(const ValueKey('tvDeviceButton'));
      expect(btn, findsOneWidget, reason: '顶栏应有电视机图标入口');

      await tester.tap(btn);
      await tester.pumpAndSettle();

      expect(find.text('TV 设备'), findsOneWidget, reason: '应打开设备面板');
      expect(find.text('未发现 TV 设备，搜索中…'), findsOneWidget);
      expect(find.byKey(const ValueKey('tvDeviceSheetClose')), findsOneWidget);

      // 关面板 → autoDispose 发现监听（停周期 Timer），避免帧末 timer 挂起
      await tester.tap(find.byKey(const ValueKey('tvDeviceSheetClose')));
      await tester.pumpAndSettle();
    });

    testWidgets('TV 模式不显示 TV 设备按钮（TV 是被推送方）', (tester) async {
      await _pumpScreen(
        tester,
        settings: const AppSettings(tvMode: true),
        servers: [_server(id: 'srv_a', name: '家庭NAS', serverId: 's1')],
      );

      expect(find.byKey(const ValueKey('tvDeviceButton')), findsNothing);
    });

    testWidgets('未配对 TV 时卡片不显示同步图标', (tester) async {
      await _pumpScreen(
        tester,
        servers: [
          _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
        ],
      );

      expect(find.byKey(const ValueKey('syncToTvButton')), findsNothing);
    });

    testWidgets('已配对 TV 时列表/网格卡片显示同步图标', (tester) async {
      const tv = PairedTv(
        deviceId: 'tv_1',
        name: '客厅电视',
        ip: '192.168.1.10',
        port: 17894,
        token: 'tok',
      );
      await _pumpScreen(
        tester,
        pairedTv: tv,
        servers: [
          _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
          _server(id: 'srv_b', name: '备用服务器', serverId: 's2'),
        ],
      );
      expect(find.byKey(const ValueKey('syncToTvButton')), findsNWidgets(2));

      // 切到网格视图同样显示
      await tester.tap(find.byIcon(Icons.view_module));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('syncToTvButton')), findsNWidgets(2));
    });

    testWidgets('已配对但 TV 模式下不显示同步图标', (tester) async {
      const tv = PairedTv(
        deviceId: 'tv_1',
        name: '客厅电视',
        ip: '192.168.1.10',
        port: 17894,
        token: 'tok',
      );
      await _pumpScreen(
        tester,
        pairedTv: tv,
        settings: const AppSettings(tvMode: true),
        servers: [_server(id: 'srv_a', name: '家庭NAS', serverId: 's1')],
      );
      expect(find.byKey(const ValueKey('syncToTvButton')), findsNothing);
    });

    testWidgets('设置关闭「同步到 TV」→ 顶栏电视机按钮隐藏', (tester) async {
      await _pumpScreen(
        tester,
        settings: const AppSettings(tvSyncEnabled: false),
        servers: [_server(id: 'srv_a', name: '家庭NAS', serverId: 's1')],
      );
      expect(find.byKey(const ValueKey('tvDeviceButton')), findsNothing);
      expect(find.byIcon(Icons.add), findsWidgets,
        reason: '其他顶栏按钮不受影响');
    });

    testWidgets('设置关闭「同步到 TV」→ 已配对时卡片同步图标也隐藏', (tester) async {
      const tv = PairedTv(
        deviceId: 'tv_1',
        name: '客厅电视',
        ip: '192.168.1.10',
        port: 17894,
        token: 'tok',
      );
      await _pumpScreen(
        tester,
        pairedTv: tv,
        settings: const AppSettings(tvSyncEnabled: false),
        servers: [
          _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
        ],
      );
      expect(find.byKey(const ValueKey('tvDeviceButton')), findsNothing);
      expect(find.byKey(const ValueKey('syncToTvButton')), findsNothing);
    });
  });

  group('网格布局移动焦点保持（焦点不跳顶栏）', () {
    testWidgets('TV 网格布局模式方向键移动后焦点仍在移动卡', (tester) async {
      final container = await _pumpScreen(
        tester,
        settings: const AppSettings(tvMode: true, serverViewMode: 'grid'),
        servers: [
          _server(id: 'srv_a', name: 'A', serverId: 's1'),
          _server(id: 'srv_b', name: 'B', serverId: 's2'),
          _server(id: 'srv_c', name: 'C', serverId: 's3'),
          _server(id: 'srv_d', name: 'D', serverId: 's4'),
        ],
      );

      // 首卡 autofocus 已聚焦，长按 OK 进入布局模式
      await _pressLongOk(tester);
      expect(find.text('移动中'), findsOneWidget, reason: '应进入布局模式');

      // 网格：右移 ±1，srv_a 从 0 → 1
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        container.read(embyServerListProvider).map((s) => s.id).toList(),
        ['srv_b', 'srv_a', 'srv_c', 'srv_d'],
        reason: '方向键右移应交换顺序',
      );

      // 重排后焦点必须仍落在移动中的卡片（而非回落到外层 scope）
      final primary = FocusManager.instance.primaryFocus;
      expect(primary?.context, isNotNull);
      expect(
        primary!.context!.findAncestorWidgetOfExactType<KeyedSubtree>()?.key,
        const ValueKey('serverGridTile_srv_a'),
        reason: '重排后焦点应保持在移动中的卡片上',
      );

      // 焦点未丢 → 再次右移仍能继续重排 srv_a 1 → 2
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        container.read(embyServerListProvider).map((s) => s.id).toList(),
        ['srv_b', 'srv_c', 'srv_a', 'srv_d'],
        reason: '连续移动应持续生效（焦点未逃逸）',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await _settleSnackbars(tester);
    });

    testWidgets('TV 布局模式顶栏 actions 被 ExcludeFocus 屏蔽', (tester) async {
      await _pumpScreen(
        tester,
        settings: const AppSettings(tvMode: true, serverViewMode: 'grid'),
        servers: [
          _server(id: 'srv_a', name: 'A', serverId: 's1'),
          _server(id: 'srv_b', name: 'B', serverId: 's2'),
        ],
      );

      final toggle = find.byKey(const ValueKey('serverViewToggle'));
      expect(
        find.ancestor(of: toggle, matching: find.byType(ExcludeFocus)),
        findsNothing,
        reason: '常规态顶栏按钮可聚焦',
      );

      await _pressLongOk(tester);
      expect(find.text('移动中'), findsOneWidget);

      expect(
        find.ancestor(of: toggle, matching: find.byType(ExcludeFocus)),
        findsWidgets,
        reason: '布局模式顶栏按钮应被 ExcludeFocus 屏蔽焦点',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await _settleSnackbars(tester);
    });
  });

  group('v1.1.256 TV 卡片 ⋮ 方向键可达（C1）', () {
    Key? focusedTileKey() => FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<KeyedSubtree>()
        ?.key;

    testWidgets('TV 列表：右键进入 ⋮、左键回主体、OK 打开面板', (tester) async {
      await _pumpScreen(
        tester,
        remote: true,
        settings: const AppSettings(tvMode: true),
        servers: [
          _server(id: 'srv_a', name: 'A', serverId: 's1'),
          _server(id: 'srv_b', name: 'B', serverId: 's2'),
        ],
      );

      // 首卡主体 autofocus
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'TvCardFocus');
      expect(focusedTileKey(), const ValueKey('serverTile_srv_a'));

      // 右键 → 焦点落到本卡 ⋮（页面显式连线：主体 → ⋮）
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'serverMoreBtn',
          reason: '右键应进入本卡 ⋮');
      expect(focusedTileKey(), const ValueKey('serverTile_srv_a'),
          reason: '⋮ 仍属于同一卡片');

      // OK → 打开操作面板
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('删除'), findsOneWidget, reason: '⋮ 上按 OK 应打开面板');

      // 关闭面板（点面板外 barrier）→ 焦点回 ⋮
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'serverMoreBtn',
          reason: '面板关闭后焦点回 ⋮');

      // 左键 → 回主体
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'TvCardFocus',
          reason: '左键应从 ⋮ 回到本卡主体');
      expect(focusedTileKey(), const ValueKey('serverTile_srv_a'));
      await _settleSnackbars(tester);
    });

    testWidgets('TV 网格：右键进入 ⋮', (tester) async {
      await _pumpScreen(
        tester,
        remote: true,
        settings: const AppSettings(tvMode: true, serverViewMode: 'grid'),
        servers: [
          _server(id: 'srv_a', name: 'A', serverId: 's1'),
          _server(id: 'srv_b', name: 'B', serverId: 's2'),
        ],
      );

      expect(FocusManager.instance.primaryFocus?.debugLabel, 'TvCardFocus');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'serverMoreBtn',
          reason: '网格卡片右键应进入本卡 ⋮');
      expect(focusedTileKey(), const ValueKey('serverGridTile_srv_a'));
      await _settleSnackbars(tester);
    });

    testWidgets('TV 列表：上下键仍正常导航卡片（不被 ⋮ 干扰）', (tester) async {
      await _pumpScreen(
        tester,
        remote: true,
        settings: const AppSettings(tvMode: true),
        servers: [
          _server(id: 'srv_a', name: 'A', serverId: 's1'),
          _server(id: 'srv_b', name: 'B', serverId: 's2'),
        ],
      );

      expect(focusedTileKey(), const ValueKey('serverTile_srv_a'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(focusedTileKey(), const ValueKey('serverTile_srv_b'),
          reason: '下键应落到下一张卡主体（而非 ⋮）');
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'TvCardFocus');
      await _settleSnackbars(tester);
    });
  });

  group('v1.2.1 TV 操作面板方向键导航闭环', () {
    String? focusLabel() => FocusManager.instance.primaryFocus?.debugLabel;

    Future<void> openPanel(WidgetTester tester, {bool remote = true}) async {
      await _pumpScreen(
        tester,
        remote: remote,
        settings: const AppSettings(tvMode: true),
        servers: [
          _server(id: 'srv_a', name: 'A', serverId: 's1'),
          _server(id: 'srv_b', name: 'B', serverId: 's2'),
        ],
      );
      // 首卡聚焦 → 右键进 ⋮ → OK 打开面板
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('删除'), findsOneWidget, reason: '面板应已打开');
    }

    testWidgets('打开面板后焦点仍在 ⋮（不移入面板，卡片不重建）', (tester) async {
      await openPanel(tester);
      expect(focusLabel(), 'serverMoreBtn',
          reason: '焦点应留在 ⋮ 按钮，避免卡片重建导致面板被关');
      // 面板仍在（若焦点移出卡片会被重建关闭）
      expect(find.text('删除'), findsOneWidget);
      await _settleSnackbars(tester);
    });

    testWidgets('方向键移动高亮不逃逸：面板打开期间焦点始终在 ⋮', (tester) async {
      await openPanel(tester);
      for (var i = 0; i < 8; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(focusLabel(), 'serverMoreBtn',
            reason: '↓ 期间焦点不应离开 ⋮（不逃逸）');
        expect(find.text('删除'), findsOneWidget, reason: '面板应保持打开');
      }
      // 越界后仍停在面板内，面板不关
      expect(find.text('删除'), findsOneWidget);
      await _settleSnackbars(tester);
    });

    testWidgets('默认选中首项：打开后直接 OK 触发「编辑」（TV→扫码页）',
        (tester) async {
      await openPanel(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(QrConfigScreen), findsOneWidget,
          reason: '默认选中首项=编辑，OK 应触发编辑动作（TV 走扫码）');
      Navigator.of(tester.element(find.byType(QrConfigScreen))).pop();
      await tester.pumpAndSettle();
      await _settleSnackbars(tester);
    });

    testWidgets('↓ 到第二项 OK 触发「切换线路」', (tester) async {
      await openPanel(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('routeTile_main')), findsOneWidget,
          reason: '下移一次 → 第二项=切换线路 → OK 打开线路弹层');
      expect(find.text('删除'), findsNothing, reason: '触发动作后面板应关闭');
      await _settleSnackbars(tester);
    });

    testWidgets('↓↑ 往返后 OK 命中对应项（↓ ↓ ↑ → 第二项「切换线路」）',
        (tester) async {
      await openPanel(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('routeTile_main')), findsOneWidget,
          reason: '两次↓一次↑应回到第二项=切换线路');
      await _settleSnackbars(tester);
    });

    testWidgets('越界：连续 ↓ 后 OK 命中末项「删除」（弹确认框）', (tester) async {
      await openPanel(tester);
      for (var i = 0; i < 10; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('删除服务器'), findsOneWidget,
          reason: '↓ 越界应停在末项=删除，OK 弹删除确认框');
      await _settleSnackbars(tester);
    });

    testWidgets('首项 ↑ 不越界：仍停在首项，OK 触发「编辑」', (tester) async {
      await openPanel(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(QrConfigScreen), findsOneWidget,
          reason: '首项↑不越界，仍选中编辑');
      Navigator.of(tester.element(find.byType(QrConfigScreen))).pop();
      await tester.pumpAndSettle();
      await _settleSnackbars(tester);
    });

    testWidgets('无全局方向键钩子（remote:false）时面板导航仍可用', (tester) async {
      await openPanel(tester, remote: false);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('routeTile_main')), findsOneWidget,
          reason: '不依赖全局 TvRemoteShortcuts，面板导航由 ⋮ 自身完成');
      await _settleSnackbars(tester);
    });
  });
}

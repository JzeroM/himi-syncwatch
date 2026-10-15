import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_counts.dart';
import 'package:himi_syncwatch/models/server_route.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/qr_config_screen.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_visibility.dart';
import 'package:himi_syncwatch/screens/servers/server_manager_screen.dart';
import 'package:himi_syncwatch/services/emby_service.dart';
import 'package:himi_syncwatch/widgets/server_card.dart';

import '../helpers/test_fakes.dart';

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
}) async {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier(settings)),
      embyAuthServiceProvider
          .overrideWith((ref) => auth ?? FakeEmbyAuthService()),
      embyServerListProvider
          .overrideWith((ref) => EmbyServerListNotifier()..setList(servers)),
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
      child: MaterialApp.router(routerConfig: router),
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
}

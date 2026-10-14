import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_counts.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/qr_config_screen.dart';
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

  testWidgets('「上移」菜单重排并持久化顺序（v1.1.236）', (tester) async {
    final auth = FakeEmbyAuthService();
    final container = await _pumpScreen(
      tester,
      auth: auth,
      servers: [
        _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
        _server(id: 'srv_b', name: '备用服务器', serverId: 's2'),
      ],
    );

    await tester.tap(find.byKey(const ValueKey('serverMore_srv_b')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('上移'));
    await tester.pumpAndSettle();

    final ids =
        container.read(embyServerListProvider).map((s) => s.id).toList();
    expect(ids, ['srv_b', 'srv_a']);
    expect(auth.lastSavedServerOrder, ['srv_b', 'srv_a']);
  });

  testWidgets('网格视图「上移」菜单同样重排（v1.1.236）', (tester) async {
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

    await tester.tap(find.byKey(const ValueKey('serverMore_srv_b')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('上移'));
    await tester.pumpAndSettle();

    final ids =
        container.read(embyServerListProvider).map((s) => s.id).toList();
    expect(ids, ['srv_b', 'srv_a']);
    expect(auth.lastSavedServerOrder, ['srv_b', 'srv_a']);
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

  testWidgets('首张卡不显示「上移」（v1.1.236）', (tester) async {
    await _pumpScreen(
      tester,
      servers: [
        _server(id: 'srv_a', name: '家庭NAS', serverId: 's1'),
        _server(id: 'srv_b', name: '备用服务器', serverId: 's2'),
      ],
    );

    await tester.tap(find.byKey(const ValueKey('serverMore_srv_a')));
    await tester.pumpAndSettle();

    expect(find.text('删除'), findsOneWidget);
    expect(find.text('上移'), findsNothing);
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
}

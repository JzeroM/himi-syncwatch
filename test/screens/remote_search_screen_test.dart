import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/services/global_search_service.dart';
import 'package:himi_syncwatch/providers/remote_search_provider.dart';
import 'package:himi_syncwatch/screens/search/global_search_screen.dart';
import 'package:himi_syncwatch/screens/search/remote_search_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../helpers/test_fakes.dart';

ProviderContainer _container() {
  final server = EmbyServerConfig(
    id: 'a',
    serverUrl: 'https://a.example.com',
    serverName: '服务器a',
    serverId: 'srv-a',
    username: 'user',
    accessToken: 'tok-a',
    userId: 'uid',
  );
  final container = ProviderContainer(
    overrides: [
      remoteSearchBasePortProvider.overrideWithValue(0),
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier()),
      embyServerListProvider.overrideWith(
        (ref) => EmbyServerListNotifier()..setList([server]),
      ),
      globalSearchProvider.overrideWithValue(
        GlobalSearchService(
          serviceFactory: (cfg) => FakeEmbyService(
            searchResults: [
              MediaItem(
                id: 'm1',
                name: '${cfg.serverName}的影片',
                type: 'Movie',
              ),
            ],
          ),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

GoRouter _router() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const RemoteSearchScreen(),
        ),
        GoRoute(
          path: '/detail/:id',
          builder: (_, s) =>
              Scaffold(body: Text('detail:${s.pathParameters['id']}')),
        ),
      ],
    );

/// 真实 IO（端口绑定/网络接口枚举）需在 runAsync 窗口执行（照 qr_config 范式）。
Future<void> _pumpStarted(
    WidgetTester tester, ProviderContainer container, GoRouter router) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump(); // initState → microtask → start()
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  });
}

/// 模拟手机端 POST /api/select 到达 handler 后的一步（HTTP 层已在
/// remote_search_server_test 端到端覆盖；flutter_test 默认 MockHttp 不发真请求）。
Future<void> _phoneSelect(
  WidgetTester tester,
  ProviderContainer container, {
  required String serverId,
  required String itemId,
}) async {
  final notifier = container.read(remoteSearchProvider.notifier);
  final error = await notifier.server.onSelect(serverId, itemId);
  expect(error, isNull, reason: 'select handler 成功');
  expect(container.read(remoteSearchProvider).lastSelectedName, isNotNull,
      reason: 'state 已写入');
  await tester.pump();
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50)); // 进/退场转场
  }
}

void main() {
  testWidgets('启动后显示二维码与地址，角落保留电视本机搜索入口', (tester) async {
    final container = _container();
    final router = _router();
    await _pumpStarted(tester, container, router);

    expect(
        find.byType(RemoteSearchScreen, skipOffstage: false), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);

    final state = container.read(remoteSearchProvider);
    expect(state.running, isTrue);
    expect(state.url, contains('t='));
    expect(find.textContaining('同一 WiFi'), findsOneWidget);
    expect(find.byKey(const ValueKey('localSearchEntry')), findsOneWidget,
        reason: '角落本机搜索备选入口');
    expect(find.text('电视本机搜索'), findsOneWidget);
  });

  testWidgets('角落入口可打开电视本机搜索页', (tester) async {
    final container = _container();
    final router = _router();
    await _pumpStarted(tester, container, router);

    await tester.tap(find.byKey(const ValueKey('localSearchEntry')));
    await tester.pumpAndSettle();

    expect(find.byType(GlobalSearchScreen), findsOneWidget);
  });

  testWidgets('手机选片：电视打开对应详情并显示已选片名', (tester) async {
    final container = _container();
    final router = _router();
    await _pumpStarted(tester, container, router);

    // 预热名字缓存（手机流程会先搜索）
    final notifier = container.read(remoteSearchProvider.notifier);
    await notifier.server.onSearch('影片');
    await tester.pump();

    await _phoneSelect(tester, container, serverId: 'a', itemId: 'm1');

    expect(find.text('detail:m1'), findsOneWidget);
    expect(
      container.read(remoteSearchProvider).lastSelectedName,
      '服务器a的影片',
    );
    // 扫码页仍在栈下，服务持续运行
    expect(
        find.byType(RemoteSearchScreen, skipOffstage: false), findsOneWidget);
    expect(container.read(remoteSearchProvider).running, isTrue);
  });

  testWidgets('连续选片：替换栈顶详情，不堆叠', (tester) async {
    final container = _container();
    final router = _router();
    await _pumpStarted(tester, container, router);

    await _phoneSelect(tester, container, serverId: 'a', itemId: 'm1');
    expect(find.text('detail:m1'), findsOneWidget);

    await _phoneSelect(tester, container, serverId: 'a', itemId: 'm2');
    expect(find.text('detail:m2'), findsOneWidget);
    expect(find.text('detail:m1'), findsNothing, reason: '旧详情已弹出');

    // 详情返回 → 扫码页仍在，服务仍在
    router.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(
        find.byType(RemoteSearchScreen, skipOffstage: false), findsOneWidget);
    expect(container.read(remoteSearchProvider).running, isTrue);
  });
}

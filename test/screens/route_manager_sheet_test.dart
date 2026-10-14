import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/server_route.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/servers/route_manager_sheet.dart';

import '../helpers/test_fakes.dart';

const _route1 = ServerRoute(id: 'r1', name: '备用一', url: 'http://r1:8096');
const _route2 = ServerRoute(id: 'r2', name: '备用二', url: 'http://r2:8096');

EmbyServerConfig _server({
  List<ServerRoute> routes = const [],
  String? activeRouteUrl,
}) =>
    EmbyServerConfig(
      id: 'cfg1',
      serverUrl: 'http://main:8096',
      serverName: 'NAS',
      serverId: 'srv1',
      username: 'u',
      accessToken: 'tok',
      userId: 'uid',
      routes: routes,
      activeRouteUrl: activeRouteUrl,
    );

/// 弹层经 showModalBottomSheet 打开，依赖同一 container 的
/// embyServerListProvider / serverRouteServiceProvider（默认工厂，
/// 切换线路只走内存 notifier + FakeAuth，不触网）。
Future<ProviderContainer> _pumpSheet(
  WidgetTester tester, {
  required EmbyServerConfig server,
}) async {
  final container = ProviderContainer(
    overrides: [
      embyAuthServiceProvider.overrideWithValue(FakeEmbyAuthService()),
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier()),
      embyServerListProvider.overrideWith(
        (ref) => EmbyServerListNotifier()..setList([server]),
      ),
      embyConfigProvider.overrideWith(
        (ref) => EmbyConfigNotifier()..setConfig(server),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => Center(
              child: ElevatedButton(
                key: const Key('openSheet'),
                onPressed: () => showRouteManagerSheet(context, ref, server),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('openSheet')));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('打开线路管理弹层：主线路 tile + 添加按钮 + 故障转移开关', (tester) async {
    await _pumpSheet(tester, server: _server());

    expect(find.byKey(const Key('routeTile_main')), findsOneWidget);
    expect(find.text('主线路'), findsOneWidget);
    expect(find.byKey(const Key('addRouteButton')), findsOneWidget);
    expect(find.byKey(const Key('autoFailoverSwitch')), findsOneWidget);
  });

  testWidgets('备用线路全部显示', (tester) async {
    await _pumpSheet(
      tester,
      server: _server(routes: const [_route1, _route2]),
    );

    expect(find.byKey(const Key('routeTile_r1')), findsOneWidget);
    expect(find.byKey(const Key('routeTile_r2')), findsOneWidget);
    expect(find.text('备用一'), findsOneWidget);
    expect(find.text('备用二'), findsOneWidget);
  });

  testWidgets('自动故障转移开关默认开', (tester) async {
    await _pumpSheet(tester, server: _server());
    final sw =
        tester.widget<Switch>(find.byKey(const Key('autoFailoverSwitch')));
    expect(sw.value, true);
  });

  testWidgets('点击备用线路 tile → activeRouteUrl 更新为该线路', (tester) async {
    final server = _server(routes: const [_route1]);
    final container = await _pumpSheet(tester, server: server);

    await tester.tap(find.byKey(const Key('routeTile_r1')));
    await tester.pumpAndSettle();

    final updated = container.read(embyServerListProvider).single;
    expect(updated.activeRouteUrl, _route1.url);
  });

  testWidgets('点击主线路 tile → 回主线路（activeRouteUrl 清空）', (tester) async {
    final server = _server(
      routes: const [_route1],
      activeRouteUrl: _route1.url,
    );
    final container = await _pumpSheet(tester, server: server);

    await tester.tap(find.byKey(const Key('routeTile_main')));
    await tester.pumpAndSettle();

    final updated = container.read(embyServerListProvider).single;
    expect(updated.activeRouteUrl, isNull);
  });
}

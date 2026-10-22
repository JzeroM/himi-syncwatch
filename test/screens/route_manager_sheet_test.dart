import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/server_route.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/qr_config_screen.dart';
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
  AppSettings settings = const AppSettings(),
}) async {
  final container = ProviderContainer(
    overrides: [
      embyAuthServiceProvider.overrideWithValue(FakeEmbyAuthService()),
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier(settings)),
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

  testWidgets('TV 点添加线路 → 打开扫码配置页（mode=route，v1.1.243）', (tester) async {
    final container = await _pumpSheet(
      tester,
      server: _server(),
      settings: const AppSettings(tvMode: true),
    );

    // TV 弹层不可拖拽关闭但添加按钮可点（遥控器 OK）
    await tester.tap(find.byKey(const Key('addRouteButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(QrConfigScreen), findsOneWidget,
        reason: 'TV 无输入法：添加线路走手机扫码');
    final qr = tester.widget<QrConfigScreen>(find.byType(QrConfigScreen));
    expect(qr.mode, 'route');
    expect(qr.serverId, 'cfg1', reason: 'serverId 透传给 routeHandler 落库目标');

    Navigator.of(tester.element(find.byType(QrConfigScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('routeTile_main')), findsOneWidget,
        reason: '返回线路弹层');
    // 未做任何添加：列表不变
    expect(container.read(embyServerListProvider).single.routes, isEmpty);
  });

  testWidgets('粘贴完整 IPv6 URL → 自动拆分并落库', (tester) async {
    const ipv6Url = 'http://[2408:85a3::8a2e:370:7334]:8097/emby';
    final container = await _pumpSheet(tester, server: _server());

    await tester.tap(find.byKey(const Key('addRouteButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('routeHostField')),
      ipv6Url,
    );
    await tester.pumpAndSettle();

    String textOf(String key) =>
        tester.widget<TextField>(find.byKey(Key(key))).controller!.text;
    expect(textOf('routeHostField'), '2408:85a3::8a2e:370:7334');
    expect(textOf('routePortField'), '8097');
    expect(textOf('routePathField'), 'emby');
    expect(
      tester.widget<Switch>(find.byKey(const Key('routeHttpsSwitch'))).value,
      isFalse,
    );

    await tester.ensureVisible(find.byKey(const Key('saveRouteButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saveRouteButton')));
    await tester.pumpAndSettle();

    final updated = container.read(embyServerListProvider).single;
    expect(updated.routes.single.url, ipv6Url);
  });

  testWidgets('保存按钮底边避开虚拟导航键区（viewPadding.bottom=48）', (tester) async {
    const navInset = 48.0;
    final container = ProviderContainer(
      overrides: [
        embyAuthServiceProvider.overrideWithValue(FakeEmbyAuthService()),
        settingsProvider
            .overrideWith((ref) => FakeSettingsNotifier(const AppSettings())),
      ],
    );
    addTearDown(container.dispose);
    final server = _server();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MediaQuery(
          data: const MediaQueryData(
            viewPadding: EdgeInsets.only(bottom: navInset),
          ).copyWith(size: const Size(800, 600)),
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const Key('openSheet'),
                  onPressed: () => showModalBottomSheet<void>(
                    context: tester.element(find.byKey(const Key('openSheet'))),
                    backgroundColor: Colors.transparent,
                    isScrollControlled: true,
                    builder: (_) => AddRouteSheet(server: server),
                  ),
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

    // 表单内容高于视口：滚到底让保存按钮落到滚动视口底部，
    // 再断言其底边不侵入虚拟导航键区。
    final scrollable =
        tester.state<ScrollableState>(find.byType(Scrollable).first);
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pumpAndSettle();

    final screen = tester.getSize(find.byType(MaterialApp));
    final buttonRect = tester.getRect(find.byKey(const Key('saveRouteButton')));
    expect(
      buttonRect.bottom,
      lessThanOrEqualTo(screen.height - navInset + 0.5),
      reason: '保存按钮底边必须在虚拟导航键区（底部48px）之上',
    );
  });
}

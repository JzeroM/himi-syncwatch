import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/shell/shell_side_drawer.dart';
import 'package:himi_syncwatch/screens/shell/tv_top_nav_bar.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';

import '../helpers/test_fakes.dart';

EmbyServerConfig _server(String id, String name) => EmbyServerConfig(
      id: id,
      serverUrl: 'https://$id',
      serverName: name,
      serverId: 'srv-$id',
      username: 'user',
      accessToken: 'token',
      userId: 'uid',
    );

Widget _host({
  int index = 0,
  ValueChanged<int>? onSelect,
  List<EmbyServerConfig> servers = const [],
  EmbyServerConfig? current,
}) {
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith(
          (ref) => FakeSettingsNotifier(const AppSettings(tvMode: true))),
      embyAuthServiceProvider.overrideWith((ref) => FakeEmbyAuthService()),
      if (servers.isNotEmpty)
        embyServerListProvider
            .overrideWith((ref) => EmbyServerListNotifier()..setList(servers)),
      if (current != null)
        embyConfigProvider
            .overrideWith((ref) => EmbyConfigNotifier()..setConfig(current)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: TvTopNavBar(
          currentIndex: index,
          onSelect: onSelect ?? (_) {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('渲染服务器标题与三个横排导航项（首页并入标题）', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump();

    // 无配置兜底标题；首页项并入标题，顶栏无「首页」字样
    expect(find.text('HIMI'), findsOneWidget);
    expect(find.text('同步观影'), findsNothing);
    expect(find.text('首页'), findsNothing);
    for (var i = 1; i < kShellNavLabels.length; i++) {
      expect(find.text(kShellNavLabels[i]), findsOneWidget);
    }
    // 搜索/房间常驻顶栏
    expect(find.byIcon(Icons.meeting_room_outlined), findsOneWidget);
    // 无已认证服务器时不显示搜索入口
    expect(find.byIcon(Icons.search), findsNothing);
  });

  testWidgets('点击导航项回调 onSelect', (tester) async {
    int? selected;
    await tester.pumpWidget(_host(onSelect: (i) => selected = i));
    await tester.pump();

    await tester.tap(find.text('设置'));
    await tester.pump();
    expect(selected, 3);

    await tester.tap(find.text('声网配置'));
    await tester.pump();
    expect(selected, 2);
  });

  testWidgets('选中项使用实心图标与高亮色，非选中为线框图标', (tester) async {
    await tester.pumpWidget(_host(index: 2));
    await tester.pump();

    // currentIndex=2：声网配置选中（实心 key 图标），设置回退线框
    // （避开 dns_outlined——标题胶囊同用该图标）
    expect(find.byIcon(kShellNavSelectedIcons[2]), findsOneWidget);
    expect(find.byIcon(kShellNavIcons[3]), findsOneWidget);
    expect(find.byIcon(kShellNavSelectedIcons[3]), findsNothing);
    // 首页已并入标题，不渲染首页导航图标
    expect(find.byIcon(kShellNavSelectedIcons[0]), findsNothing);
    expect(find.byIcon(kShellNavIcons[0]), findsNothing);
  });

  testWidgets('标题名称点击回首页（onSelect(0)）', (tester) async {
    int? selected;
    final servers = [_server('a', '家庭NAS')];
    await tester.pumpWidget(
      _host(
        index: 3,
        onSelect: (i) => selected = i,
        servers: servers,
        current: servers.first,
      ),
    );
    await tester.pump();

    expect(find.text('家庭NAS'), findsOneWidget);
    await tester.tap(find.text('家庭NAS'));
    await tester.pump();
    expect(selected, 0);
  });

  testWidgets('▾ 打开服务器下拉并可切换服务器', (tester) async {
    final servers = [_server('a', '家庭NAS'), _server('b', '备用服务器')];
    await tester.pumpWidget(
      _host(servers: servers, current: servers.first),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.arrow_drop_down));
    await tester.pumpAndSettle();
    expect(find.text('备用服务器'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    await tester.tap(find.text('备用服务器'));
    await tester.pumpAndSettle();

    // 下拉关闭，标题切到新服务器
    expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
    expect(find.text('备用服务器'), findsOneWidget);
    expect(find.text('家庭NAS'), findsNothing);
  });

  testWidgets('已认证服务器时显示搜索入口，点击打开聚合搜索', (tester) async {
    final servers = [_server('a', '家庭NAS')];
    await tester.pumpWidget(
      _host(servers: servers, current: servers.first),
    );
    await tester.pump();

    expect(find.byIcon(Icons.search), findsOneWidget);
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    expect(find.text('输入关键词搜索全部服务器'), findsOneWidget);
  });

  testWidgets('点击房间按钮弹出房间卡片', (tester) async {
    final servers = [_server('a', '家庭NAS')];
    await tester.pumpWidget(
      _host(servers: servers, current: servers.first),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.meeting_room_outlined));
    await tester.pumpAndSettle();
    expect(find.text('创建房间'), findsOneWidget);
    expect(find.text('加入房间'), findsOneWidget);
  });

  testWidgets('顶栏为通栏玻璃条，标题胶囊被玻璃包裹', (tester) async {
    final servers = [_server('a', '家庭NAS')];
    await tester.pumpWidget(
      _host(servers: servers, current: servers.first),
    );
    await tester.pump();

    final titleCapsule = find.descendant(
      of: find.byType(TvTopNavBar),
      matching: find.byType(GlassContainer),
    );
    expect(titleCapsule, findsOneWidget);
    expect(
      tester.widget<GlassContainer>(titleCapsule).showShadow,
      isFalse,
    );
  });
}

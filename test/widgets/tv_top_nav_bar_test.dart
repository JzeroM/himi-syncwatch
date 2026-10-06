import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/remote_search_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/shell/shell_side_drawer.dart';
import 'package:himi_syncwatch/screens/search/remote_search_screen.dart';
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

/// 顶栏导航项图标 finder：标题胶囊同用 `dns_outlined`（size 18），
/// 按导航项的 20 号图标尺寸限定，避免撞图标歧义。
Finder _navIcon(IconData icon) => find.byWidgetPredicate(
      (w) => w is Icon && w.icon == icon && w.size == 20,
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
      remoteSearchBasePortProvider.overrideWithValue(0),
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
  testWidgets('渲染服务器标题与纯图标导航项，声网配置隐藏（首页并入标题）', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(_host());
      await tester.pump();

      // 无配置兜底标题；首页项并入标题，顶栏无「首页」字样
      expect(find.text('HIMI'), findsOneWidget);
      expect(find.text('同步观影'), findsNothing);
      expect(find.text('首页'), findsNothing);
      // 导航项去文字：仅图标，文字经 Semantics 保留无障碍标签
      // （dns_outlined 与标题胶囊同图标，故用 findsWidgets）
      for (var i = 1; i < kShellNavLabels.length; i++) {
        if (i == TvTopNavBar.hiddenAgoraIndex) continue;
        expect(find.text(kShellNavLabels[i]), findsNothing);
        expect(find.byIcon(kShellNavIcons[i]), findsWidgets);
        expect(find.bySemanticsLabel(kShellNavLabels[i]), findsOneWidget);
      }
      // TV 模式隐藏声网配置入口：图标与语义标签均不渲染
      expect(
        find.byIcon(kShellNavIcons[TvTopNavBar.hiddenAgoraIndex]),
        findsNothing,
      );
      expect(
        find.bySemanticsLabel(kShellNavLabels[TvTopNavBar.hiddenAgoraIndex]),
        findsNothing,
      );
      // 搜索常驻顶栏；TV 模式取消房间模式，无房间入口
      expect(find.byIcon(Icons.meeting_room_outlined), findsNothing);
      // 无已认证服务器时不显示搜索入口
      expect(find.byIcon(Icons.search), findsNothing);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('点击导航项回调 onSelect，隐藏项不可点', (tester) async {
    int? selected;
    await tester.pumpWidget(_host(onSelect: (i) => selected = i));
    await tester.pump();

    await tester.tap(_navIcon(kShellNavIcons[4]));
    await tester.pump();
    expect(selected, 4);

    await tester.tap(_navIcon(kShellNavIcons[1]));
    await tester.pump();
    expect(selected, 1);

    // 声网配置图标未渲染，无法被点到
    expect(
        _navIcon(kShellNavIcons[TvTopNavBar.hiddenAgoraIndex]), findsNothing);
  });

  testWidgets('选中项使用实心图标与高亮色，非选中为线框图标', (tester) async {
    await tester.pumpWidget(_host(index: 4));
    await tester.pump();

    // currentIndex=4：设置选中（实心图标），收藏回退线框
    expect(_navIcon(kShellNavSelectedIcons[4]), findsOneWidget);
    expect(_navIcon(kShellNavIcons[1]), findsOneWidget);
    expect(_navIcon(kShellNavSelectedIcons[1]), findsNothing);
    // 首页已并入标题，不渲染首页导航图标
    expect(_navIcon(kShellNavSelectedIcons[0]), findsNothing);
    expect(_navIcon(kShellNavIcons[0]), findsNothing);
  });

  testWidgets('标题名称点击回首页（onSelect(0)）', (tester) async {
    int? selected;
    final servers = [_server('a', '家庭NAS')];
    await tester.pumpWidget(
      _host(
        index: 4,
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

  testWidgets('已认证服务器时显示搜索入口，点击打开远程扫码搜索', (tester) async {
    final servers = [_server('a', '家庭NAS')];
    await tester.pumpWidget(
      _host(servers: servers, current: servers.first),
    );
    await tester.pump();

    expect(find.byIcon(Icons.search), findsOneWidget);
    await tester.tap(find.byIcon(Icons.search));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350)); // push 转场
    await tester.pump();
    expect(find.byType(RemoteSearchScreen), findsOneWidget);
    expect(find.text('手机扫码搜索'), findsOneWidget);
  });

  testWidgets('TV 取消房间模式：顶栏不渲染房间入口', (tester) async {
    final servers = [_server('a', '家庭NAS')];
    await tester.pumpWidget(
      _host(servers: servers, current: servers.first),
    );
    await tester.pump();

    expect(find.byIcon(Icons.meeting_room_outlined), findsNothing);
    expect(find.text('创建房间'), findsNothing);
    expect(find.text('加入房间'), findsNothing);
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

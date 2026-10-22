import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:himi_syncwatch/widgets/server_title_dropdown.dart';
import 'package:himi_syncwatch/widgets/tv/tv_remote_shell.dart';

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
  AppSettings settings = const AppSettings(tvMode: true),
}) {
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier(settings)),
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
  testWidgets('渲染服务器标题与纯图标导航项，声网配置隐藏（首页不占顶栏）', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(_host());
      await tester.pump();

      // 无配置兜底标题；首页入口不在顶栏（回首页走返回键）
      expect(find.text('HIMI'), findsOneWidget);
      expect(find.text('同步观影'), findsNothing);
      expect(find.text('首页'), findsNothing);
      expect(find.bySemanticsLabel('首页'), findsNothing);
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
    // 首页不占图标位（回首页走返回键），不渲染首页导航图标
    expect(_navIcon(kShellNavSelectedIcons[0]), findsNothing);
    expect(_navIcon(kShellNavIcons[0]), findsNothing);
  });

  testWidgets('标题胶囊为单个焦点：点名称或 ▾ 均打开服务器下拉（v1.2.31 单焦点）', (tester) async {
    int? selected;
    final servers = [_server('a', '家庭NAS'), _server('b', '备用服务器')];
    await tester.pumpWidget(
      _host(
        index: 4,
        onSelect: (i) => selected = i,
        servers: servers,
        current: servers.first,
      ),
    );
    await tester.pump();

    // 整颗胶囊只有一个可聚焦节点（回归：不再拆成「首页 / 下拉」两个）
    expect(
      find.descendant(
        of: find.byType(ServerTitleDropdown),
        matching: find.byType(Focus),
      ),
      findsOneWidget,
    );

    // 点名称即打开下拉，且不再触发回首页
    await tester.tap(find.text('家庭NAS'));
    await tester.pumpAndSettle();
    expect(find.text('备用服务器'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('serverRow_a')),
        matching: find.byIcon(Icons.check_circle),
      ),
      findsOneWidget,
    );
    expect(selected, isNull);

    // 点外部关闭后点 ▾：同样打开下拉
    await tester.tapAt(const Offset(20, 500));
    await tester.pumpAndSettle();
    expect(find.text('备用服务器'), findsNothing);
    await tester.tap(find.byIcon(Icons.arrow_drop_down));
    await tester.pumpAndSettle();
    expect(find.text('备用服务器'), findsOneWidget);
  });

  testWidgets('无服务器时标题胶囊仍可打开并切换首页模式', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump();

    expect(find.text('HIMI'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ServerTitleDropdown),
        matching: find.byType(Focus),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('HIMI'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tmdbSourceRow')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('homeSourceModeRow_server')), findsNothing);
    expect(find.byKey(const ValueKey('homeSourceModeRow_tmdb')), findsNothing);
    expect(find.text('未添加服务器'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ServerTitleDropdown)),
    );
    await tester.tap(find.byKey(const ValueKey('tmdbSourceRow')));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).isTmdbHome, isTrue);
    expect(
      find.descendant(
        of: find.byType(ServerTitleDropdown),
        matching: find.text('TMDB'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(ServerTitleDropdown),
        matching: find.byIcon(Icons.local_movies_outlined),
      ),
      findsOneWidget,
    );
  });

  testWidgets('TMDB 模式胶囊显示胶片图标，选择服务器切回服务器首页', (tester) async {
    final servers = [_server('a', '家庭NAS'), _server('b', '备用服务器')];
    await tester.pumpWidget(
      _host(
        servers: servers,
        current: servers.first,
        settings: const AppSettings(tvMode: true, homeSourceMode: 'tmdb'),
      ),
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(ServerTitleDropdown),
        matching: find.text('TMDB'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(ServerTitleDropdown),
        matching: find.byIcon(Icons.local_movies_outlined),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('TMDB'));
    await tester.pumpAndSettle();

    // TMDB 行在第一位，下面按配置页顺序列出服务器；激活服务器仍打勾。
    expect(find.byKey(const ValueKey('tmdbSourceRow')), findsOneWidget);
    expect(find.byKey(const ValueKey('serverRow_a')), findsOneWidget);
    expect(find.byKey(const ValueKey('serverRow_b')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('serverRow_a')),
        matching: find.byIcon(Icons.check_circle),
      ),
      findsOneWidget,
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ServerTitleDropdown)),
    );
    await tester.tap(find.text('备用服务器'));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).isTmdbHome, isFalse);
    expect(container.read(embyConfigProvider)?.id, 'b');
    expect(
      find.descendant(
        of: find.byType(ServerTitleDropdown),
        matching: find.text('备用服务器'),
      ),
      findsOneWidget,
    );
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
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('serverRow_a')),
        matching: find.byIcon(Icons.check_circle),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('备用服务器'));
    await tester.pumpAndSettle();

    // 下拉关闭，标题切到新服务器
    expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
    expect(find.text('备用服务器'), findsOneWidget);
    expect(find.text('家庭NAS'), findsNothing);
  });

  testWidgets('TV：下拉每行有焦点框，方向键移动 + OK 选中（v1.2.32 回归）', (tester) async {
    final servers = [_server('a', '家庭NAS'), _server('b', '备用服务器')];
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(
            (ref) => FakeSettingsNotifier(const AppSettings(tvMode: true))),
        remoteSearchBasePortProvider.overrideWithValue(0),
        embyAuthServiceProvider.overrideWith((ref) => FakeEmbyAuthService()),
        embyServerListProvider
            .overrideWith((ref) => EmbyServerListNotifier()..setList(servers)),
        embyConfigProvider.overrideWith(
            (ref) => EmbyConfigNotifier()..setConfig(servers.first)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        // TV 方向键遍历由 TvRemoteShell 提供（与真机一致）
        child: TvRemoteShell(
          child: MaterialApp(
            home: Scaffold(
              body: TvTopNavBar(currentIndex: 0, onSelect: (_) {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('家庭NAS'));
    await tester.pumpAndSettle();

    // 下拉打开后有且仅有一个焦点环（当前服务器行 autofocus）
    expect(
      find.byWidgetPredicate(
        (w) => w is AnimatedContainer && w.foregroundDecoration != null,
      ),
      findsOneWidget,
    );

    // 当前服务器行已聚焦，方向键下移一格到备用服务器，OK 选中并关闭下拉
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('备用服务器'), findsWidgets);
    expect(container.read(embyConfigProvider)?.id, 'b');
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

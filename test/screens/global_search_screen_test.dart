import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/search/global_search_screen.dart';
import 'package:himi_syncwatch/services/global_search_service.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';

import '../helpers/test_fakes.dart';

EmbyServerConfig _server(String id, String name) => EmbyServerConfig(
      id: id,
      serverUrl: 'https://$id.example.com',
      serverName: name,
      serverId: 'srv-$id',
      username: 'user',
      accessToken: 'token',
      userId: 'uid',
    );

MediaItem _item(String id, String name) =>
    MediaItem(id: id, name: name, type: 'Movie', posterUrl: '');

/// 按服务器返回不同结果的聚合搜索（甲库甲片 / 乙库乙片）。
GlobalSearchService _searchService({
  List<MediaItem> fromA = const [],
  List<MediaItem> fromB = const [],
}) =>
    GlobalSearchService(
      serviceFactory: (cfg) => FakeEmbyService(
        searchResults: cfg.id == 'a' ? fromA : fromB,
      ),
    );

Future<void> _pump(
  WidgetTester tester, {
  GlobalSearchService? search,
  List<EmbyServerConfig> servers = const [],
  AppSettings settings = const AppSettings(),
}) async {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier(settings)),
      if (servers.isNotEmpty)
        embyServerListProvider.overrideWith(
          (ref) => EmbyServerListNotifier()..setList(servers),
        ),
      globalSearchProvider.overrideWithValue(
        search ?? GlobalSearchService(serviceFactory: (_) => FakeEmbyService()),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: GlobalSearchScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('左右栏结构：左服务器筛选 + 右资源卡片，不再是全屏平铺列表', (tester) async {
    await _pump(
      tester,
      servers: [_server('a', '服务器甲'), _server('b', '服务器乙')],
      search: _searchService(
        fromA: [_item('a1', '甲的影片')],
        fromB: [_item('b1', '乙的影片')],
      ),
    );

    expect(find.text('输入关键词，搜索所有服务器'), findsOneWidget, reason: '空词提示态');

    await tester.enterText(find.byType(TextField), '影片');
    await tester.pump(const Duration(milliseconds: 320)); // 防抖到期
    await tester.pumpAndSettle();

    // 左栏：全部 + 各服务器筛选片
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('服务器甲'), findsWidgets, reason: '筛选片 + 卡片角标');
    expect(find.text('服务器乙'), findsWidgets);

    // 右栏：两台服务器的卡片（卡片角标区分来源），无旧平铺 ListTile
    expect(find.text('甲的影片'), findsOneWidget);
    expect(find.text('乙的影片'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing, reason: '旧平铺列表已移除');
  });

  testWidgets('TV 模式输入框不抢焦且被 ExcludeFocus（打开即卡死回归，v1.1.177）',
      (tester) async {
    await _pump(tester, settings: const AppSettings(tvMode: true));

    final field = find.byKey(const ValueKey('globalSearchField'));
    expect(field, findsOneWidget);
    expect(
      find.ancestor(of: field, matching: find.byType(ExcludeFocus)),
      findsOneWidget,
      reason: 'TV 下输入框必须屏蔽焦点（方向键被文本编辑快捷键吞掉）',
    );

    // autofocus 已条件化：TV 下不写 true
    final tf = tester.widget<TextField>(field);
    expect(tf.autofocus, isFalse);

    // 焦点不在输入框上
    final editable = find.descendant(of: field, matching: find.byType(EditableText));
    final focusNode = tester.widget<EditableText>(editable.first).focusNode;
    expect(focusNode.hasFocus, isFalse);
  });

  testWidgets('左栏筛选：点服务器只看该服务器结果，点全部恢复', (tester) async {
    await _pump(
      tester,
      servers: [_server('a', '服务器甲'), _server('b', '服务器乙')],
      search: _searchService(
        fromA: [_item('a1', '甲的影片')],
        fromB: [_item('b1', '乙的影片')],
      ),
    );
    await tester.enterText(find.byType(TextField), '影片');
    await tester.pump(const Duration(milliseconds: 320)); // 防抖到期
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('serverChip_b')));
    await tester.pumpAndSettle();
    expect(find.text('乙的影片'), findsOneWidget);
    expect(find.text('甲的影片'), findsNothing, reason: '已过滤掉甲');

    await tester.tap(find.byKey(const ValueKey('serverChip_all')));
    await tester.pumpAndSettle();
    expect(find.text('甲的影片'), findsOneWidget, reason: '回落全部');
    expect(find.text('乙的影片'), findsOneWidget);
  });

  testWidgets('底色同主题色：三段渐变 = pageGradient(darkenForPage(主题色))', (tester) async {
    const themeColor = 0xFF3EBC7A;
    await _pump(
      tester,
      settings: const AppSettings(themeColor: themeColor),
      search: _searchService(fromA: [_item('a1', '甲的影片')]),
      servers: [_server('a', '服务器甲')],
    );
    await tester.enterText(find.byType(TextField), '影片');
    await tester.pump(const Duration(milliseconds: 320)); // 防抖到期
    await tester.pumpAndSettle();

    final gradient = (tester
            .widget<Container>(find.byKey(const Key('searchBackground')))
            .decoration! as BoxDecoration)
        .gradient! as LinearGradient;
    expect(gradient.colors.first,
        PosterPalette.darkenForPage(const Color(themeColor)),
        reason: '首色 = 压暗主题色');
    expect(gradient.stops, PosterPalette.pageStops);
  });

  testWidgets('未设主题色：保持应用底色三段（与首页一致）', (tester) async {
    await _pump(tester, search: _searchService());
    await tester.enterText(find.byType(TextField), '无结果词');
    await tester.pump(const Duration(milliseconds: 320)); // 防抖到期
    await tester.pumpAndSettle();

    final gradient = (tester
            .widget<Container>(find.byKey(const Key('searchBackground')))
            .decoration! as BoxDecoration)
        .gradient! as LinearGradient;
    final base =
        Theme.of(tester.element(find.byKey(const Key('searchBackground'))))
            .scaffoldBackgroundColor;
    expect(gradient.colors, [base, base, base], reason: '三段同底色 = 未设主题色的默认观');
  });

  testWidgets('无结果 → 未找到结果', (tester) async {
    await _pump(tester, search: _searchService());
    await tester.enterText(find.byType(TextField), 'zzz没有');
    await tester.pump(const Duration(milliseconds: 320)); // 防抖到期
    await tester.pumpAndSettle();
    expect(find.text('未找到结果'), findsOneWidget);
  });

  testWidgets('清空按钮：清词回落空词提示态', (tester) async {
    await _pump(
      tester,
      servers: [_server('a', '服务器甲')],
      search: _searchService(fromA: [_item('a1', '甲的影片')]),
    );
    await tester.enterText(find.byType(TextField), '影片');
    await tester.pump(const Duration(milliseconds: 320)); // 防抖到期
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('globalSearchClear')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('globalSearchClear')));
    await tester.pumpAndSettle();
    expect(find.text('输入关键词，搜索所有服务器'), findsOneWidget);
    expect(find.text('甲的影片'), findsNothing);
  });

  testWidgets('输入防抖：280ms 内零请求，停顿后按终词只发一次', (tester) async {
    final counting = _CountingSearch(
      serviceFactory: (cfg) => FakeEmbyService(
        searchResults: cfg.id == 'a' ? [_item('a1', '甲的影片')] : const [],
      ),
    );
    await _pump(
      tester,
      servers: [_server('a', '服务器甲')],
      search: counting,
    );

    await tester.enterText(find.byType(TextField), '影');
    await tester.pump(const Duration(milliseconds: 200));
    expect(counting.searchStreamCalls, 0, reason: '防抖窗口内零请求');

    await tester.enterText(find.byType(TextField), '影片甲');
    await tester.pump(const Duration(milliseconds: 150));
    expect(counting.searchStreamCalls, 0, reason: '再次输入重置防抖');

    await tester.enterText(find.byType(TextField), '影片');
    await tester.pump(const Duration(milliseconds: 320));
    expect(counting.searchStreamCalls, 1, reason: '停顿后只发一次（终词）');
    await tester.pumpAndSettle();
    expect(find.text('甲的影片'), findsOneWidget);
  });

  testWidgets('换词期间保留上一批结果 + 顶部进度线，新结果到达后替换', (tester) async {
    final gated = _GatedSearch(
      serviceFactory: (cfg) => FakeEmbyService(
        searchResults: cfg.id == 'a' ? [_item('a1', '甲的影片')] : const [],
      ),
    );
    await _pump(
      tester,
      servers: [_server('a', '服务器甲')],
      search: gated,
    );

    await tester.enterText(find.byType(TextField), '第一词');
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pumpAndSettle();
    expect(find.text('甲的影片'), findsOneWidget, reason: '首批结果就位');

    // 第二词被闸门挂起：旧果保留 + 进度线
    await tester.enterText(find.byType(TextField), '第二词');
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.byKey(const Key('searchProgressLine')), findsOneWidget,
        reason: '换词加载中显示顶部细进度条');
    expect(find.text('甲的影片'), findsOneWidget, reason: '保留上一批结果不闪空');

    // 放行新结果
    gated.open(
      '第二词',
      [
        GlobalSearchResult(
            server: _server('a', '服务器甲'), item: _item('a2', '第二词的影片'))
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('第二词的影片'), findsOneWidget);
    expect(find.text('甲的影片'), findsNothing, reason: '新果替换旧果');
    expect(find.byKey(const Key('searchProgressLine')), findsNothing,
        reason: '完成后移除进度线');
  });

  testWidgets('房间模式：选片进 roomMode 详情，资源数据带回资源面板', (tester) async {
    final harness = await _pumpRoom(
      tester,
      servers: [_server('a', '服务器甲')],
      search: _searchService(fromA: [_item('a1', '甲的影片')]),
    );

    await tester.tap(find.byKey(const ValueKey('openRoomSearch')));
    await tester.pumpAndSettle();
    expect(find.byType(GlobalSearchScreen), findsOneWidget);

    await tester.enterText(find.byType(TextField), '影片');
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('posterCard_a1_a')));
    await tester.pumpAndSettle();

    // 详情带全 roomMode/roomCode/server 参数
    expect(find.text('detail:a1'), findsOneWidget);
    expect(find.textContaining('roomMode=true'), findsOneWidget);
    expect(find.textContaining('roomCode=rc1'), findsOneWidget);
    expect(find.textContaining('server=a'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('returnResource')));
    await tester.pumpAndSettle();

    expect(harness.received, {'resourceId': 'r1'}, reason: '数据带回面板');
    expect(find.byType(GlobalSearchScreen), findsNothing, reason: '搜索页已退场');
    expect(find.text('资源面板'), findsOneWidget);
  });

  testWidgets('房间模式：详情未选资源直接返回，留在搜索页继续挑', (tester) async {
    final harness = await _pumpRoom(
      tester,
      servers: [_server('a', '服务器甲')],
      search: _searchService(fromA: [_item('a1', '甲的影片')]),
    );

    await tester.tap(find.byKey(const ValueKey('openRoomSearch')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '影片');
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('posterCard_a1_a')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('returnNull')));
    await tester.pumpAndSettle();

    expect(find.byType(GlobalSearchScreen), findsOneWidget, reason: '留在搜索页');
    expect(harness.received, isNull, reason: '面板未收到数据');
    expect(find.text('甲的影片'), findsOneWidget, reason: '结果仍在，可继续选');
  });
}

/// 房间模式 harness：面板 push 搜索页，fake 详情按 query 参数渲染。
Future<_RoomHarness> _pumpRoom(
  WidgetTester tester, {
  GlobalSearchService? search,
  List<EmbyServerConfig> servers = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier()),
      if (servers.isNotEmpty)
        embyServerListProvider.overrideWith(
          (ref) => EmbyServerListNotifier()..setList(servers),
        ),
      globalSearchProvider.overrideWithValue(
        search ?? GlobalSearchService(serviceFactory: (_) => FakeEmbyService()),
      ),
    ],
  );
  addTearDown(container.dispose);
  final harness = _RoomHarness();
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => _PanelPage(harness: harness),
      ),
      GoRoute(
        path: '/detail/:id',
        builder: (_, state) => _FakeDetailPage(state: state),
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

class _RoomHarness {
  Object? received;
}

/// 房间资源面板替身：push 房间模式搜索页，接收带回的资源数据。
class _PanelPage extends StatefulWidget {
  const _PanelPage({required this.harness});

  final _RoomHarness harness;

  @override
  State<_PanelPage> createState() => _PanelPageState();
}

class _PanelPageState extends State<_PanelPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('资源面板'),
          ElevatedButton(
            key: const ValueKey('openRoomSearch'),
            onPressed: () async {
              final data = await Navigator.of(context).push<Object?>(
                MaterialPageRoute(
                  builder: (_) => const GlobalSearchScreen(roomCode: 'rc1'),
                ),
              );
              if (data != null) {
                setState(() => widget.harness.received = data);
              }
            },
            child: const Text('打开搜索'),
          ),
          if (widget.harness.received != null)
            Text('received:${widget.harness.received}'),
        ],
      ),
    );
  }
}

/// roomMode 详情替身：展示命中的 query 参数；返回资源数据或 null。
class _FakeDetailPage extends StatelessWidget {
  const _FakeDetailPage({required this.state});

  final GoRouterState state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('detail:${state.pathParameters['id']}'),
          Text('query:${state.uri.query}', key: const ValueKey('detailQuery')),
          ElevatedButton(
            key: const ValueKey('returnResource'),
            onPressed: () => Navigator.of(context).pop({'resourceId': 'r1'}),
            child: const Text('返回资源'),
          ),
          ElevatedButton(
            key: const ValueKey('returnNull'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('直接返回'),
          ),
        ],
      ),
    );
  }
}

/// 只计数的搜索服务：验证防抖调用次数。
class _CountingSearch extends GlobalSearchService {
  _CountingSearch({required super.serviceFactory});

  int searchStreamCalls = 0;

  @override
  Stream<List<GlobalSearchResult>> searchStream(
    String query,
    List<EmbyServerConfig> servers,
  ) {
    searchStreamCalls++;
    return super.searchStream(query, servers);
  }
}

/// 第二词挂闸（不发首快照）的搜索服务：验证换词保旧果/进度线。
class _GatedSearch extends GlobalSearchService {
  _GatedSearch({required super.serviceFactory});

  final Map<String, StreamController<List<GlobalSearchResult>>> _gates = {};

  void open(String query, List<GlobalSearchResult> results) {
    final c = _gates[query];
    if (c == null) return;
    c.add(results);
    c.close();
  }

  @override
  Stream<List<GlobalSearchResult>> searchStream(
    String query,
    List<EmbyServerConfig> servers,
  ) {
    if (query == '第二词') {
      final c = StreamController<List<GlobalSearchResult>>();
      _gates[query] = c;
      return c.stream;
    }
    return super.searchStream(query, servers);
  }
}

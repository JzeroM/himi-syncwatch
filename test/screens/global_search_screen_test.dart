import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('globalSearchClear')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('globalSearchClear')));
    await tester.pumpAndSettle();
    expect(find.text('输入关键词，搜索所有服务器'), findsOneWidget);
    expect(find.text('甲的影片'), findsNothing);
  });
}

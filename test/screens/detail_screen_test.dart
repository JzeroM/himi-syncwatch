import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/palette_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/detail/detail_screen.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

import '../helpers/test_fakes.dart';

const _posterUrl = 'https://emby.test/Items/m1/Images/Primary';

final _item = MediaItem(
  id: 'm1',
  name: '测试影片',
  type: 'Movie',
  posterUrl: _posterUrl,
  overview: '这是一段测试简介。',
);

Future<void> _pumpDetail(
  WidgetTester tester, {
  Color? accent,
  FakeEmbyService? emby,
  bool tv = false,
  bool roomMode = false,
  MediaItem? item,
}) async {
  final targetItem = item ?? _item;
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier(
          tv ? const AppSettings(tvMode: true) : const AppSettings())),
      embyServiceProvider
          .overrideWith((ref) => emby ?? FakeEmbyService(item: targetItem)),
      posterColorProvider(_posterUrl).overrideWith((ref) async => accent),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: DetailScreen(itemId: targetItem.id, roomMode: roomMode),
      ),
    ),
  );
  // 图片占位转圈动画不会 settle，改为固定帧推进：
  // 首帧处理加载微任务，再推进超过 500ms 的渐变过渡动画。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 600));
}

/// 焦点是否位于 [finder] 所指子树内。
bool _focusWithin(Finder finder) {
  final top = finder.evaluate().firstOrNull;
  final node = FocusManager.instance.primaryFocus?.context;
  if (top == null || node is! Element) return false;
  if (identical(node, top)) return true;
  var found = false;
  // ignore: avoid_types_on_closure_parameters
  node.visitAncestorElements((Element a) {
    if (a == top) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

LinearGradient _pageGradient(WidgetTester tester) {
  final container = tester
      .widget<AnimatedContainer>(find.byKey(const Key('detailBackground')));
  final decoration = container.decoration! as BoxDecoration;
  return decoration.gradient! as LinearGradient;
}

void main() {
  testWidgets('取色成功时背景为海报主色垂直渐变', (tester) async {
    const accent = Color(0xFF3366AA);
    await _pumpDetail(tester, accent: accent);

    final gradient = _pageGradient(tester);
    expect(gradient.colors.first, accent);
    expect(gradient.colors.last, ThemeData.dark().scaffoldBackgroundColor);
    expect(gradient.colors.length, 3);
    expect(find.text('测试影片'), findsWidgets);
  });

  testWidgets('取色失败时背景保持页面底色', (tester) async {
    await _pumpDetail(tester, accent: null);

    final gradient = _pageGradient(tester);
    final base = ThemeData.dark().scaffoldBackgroundColor;
    expect(gradient.colors.toSet(), {base});
    expect(find.text('测试影片'), findsWidgets);
  });

  testWidgets('跨服务器详情按 serverId 使用来源服务器的服务', (tester) async {
    final target = EmbyServerConfig(
      id: 'srv-b',
      serverUrl: 'https://b.example.com',
      serverName: '服务器B',
      serverId: 'srv-b',
      username: 'user',
      accessToken: 'token',
      userId: 'uid',
    );
    EmbyServerConfig? used;
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith((ref) => FakeSettingsNotifier()),
        // 当前激活服务器返回 null：若误用当前服务会加载失败
        embyServiceProvider.overrideWith((ref) => FakeEmbyService(item: null)),
        embyServiceFactoryProvider.overrideWithValue((cfg) {
          used = cfg;
          return FakeEmbyService(item: _item);
        }),
        posterColorProvider(_posterUrl).overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);
    container.read(embyServerListProvider.notifier).setList([target]);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: const DetailScreen(itemId: 'm1', serverId: 'srv-b'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));

    expect(used?.id, 'srv-b');
    expect(find.text('测试影片'), findsWidgets);
  });

  testWidgets('相似推荐卡片：无黑底 Card、标题在海报下方、评分与集数角标', (tester) async {
    await _pumpDetail(
      tester,
      emby: FakeEmbyService(
        item: _item,
        similar: [
          MediaItem(
            id: 's1',
            name: '相似影片',
            type: 'Movie',
            posterUrl: '',
            year: '2024',
            communityRating: 7.2,
            indexNumber: 5,
          ),
        ],
      ),
    );

    expect(find.text('相似推荐'), findsOneWidget);
    expect(find.byType(Card), findsNothing);

    final card = find.byKey(const ValueKey('posterCard_s1'));
    expect(card, findsOneWidget);

    final poster = tester.getRect(
      find.descendant(of: card, matching: find.byType(EmbyImage)),
    );
    final title = tester.getRect(
      find.descendant(of: card, matching: find.text('相似影片')),
    );
    expect(title.top, greaterThanOrEqualTo(poster.bottom));
    expect(poster.height, closeTo(poster.width * 1.5, 0.5));

    expect(
      find.descendant(of: card, matching: find.text('7.2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('5')),
      findsOneWidget,
    );
  });

  group('TV 模式操作按钮（取消胶囊、移到简介上方）', () {
    testWidgets('无胶囊底栏，按钮在简介上方且被 TvFocusable 包裹、自动落焦', (tester) async {
      await _pumpDetail(tester, tv: true);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.bottomNavigationBar, isNull, reason: 'TV 不渲染胶囊底栏');

      // 无胶囊托盘：按钮祖先链里不应有 GlassContainer
      expect(
        find.ancestor(
            of: find.text('开始播放'), matching: find.byType(GlassContainer)),
        findsNothing,
      );

      // 在简介标题上方
      final btn = tester.getRect(find.text('开始播放'));
      final desc = tester.getRect(find.text('简介'));
      expect(btn.top, lessThan(desc.top));

      // TvFocusable 包裹（焦点环/OK 键激活）
      expect(
        find.ancestor(
            of: find.text('开始播放'), matching: find.byType(TvFocusable)),
        findsOneWidget,
      );
      expect(
        find.ancestor(of: find.text('建房'), matching: find.byType(TvFocusable)),
        findsOneWidget,
      );

      // 进页 autofocus：焦点直接落在开始播放（解决有时无法聚焦）
      expect(
        _focusWithin(find.ancestor(
            of: find.text('开始播放'), matching: find.byType(TvFocusable))),
        isTrue,
        reason: '进页应自动聚焦开始播放',
      );
    });

    testWidgets('电视剧：无开始播放，autofocus 落建房', (tester) async {
      final series = MediaItem(
        id: 'm1',
        name: '测试剧集',
        type: 'Series',
        posterUrl: _posterUrl,
        overview: '剧集简介。',
      );
      await _pumpDetail(tester, tv: true, item: series);

      expect(find.text('开始播放'), findsNothing);
      expect(find.text('建房'), findsOneWidget);
      expect(
        _focusWithin(find.ancestor(
            of: find.text('建房'), matching: find.byType(TvFocusable))),
        isTrue,
        reason: '电视剧进页应自动聚焦建房',
      );
    });

    testWidgets('roomMode：加入资源移到简介上方且无底栏', (tester) async {
      await _pumpDetail(tester, tv: true, roomMode: true);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.bottomNavigationBar, isNull);
      expect(find.text('开始播放'), findsNothing);
      expect(find.text('加入资源'), findsOneWidget);
      expect(
        find.ancestor(
            of: find.text('加入资源'), matching: find.byType(TvFocusable)),
        findsOneWidget,
      );
      final btn = tester.getRect(find.text('加入资源'));
      final desc = tester.getRect(find.text('简介'));
      expect(btn.top, lessThan(desc.top));
    });

    testWidgets('非 TV 回归：保持胶囊底栏不变', (tester) async {
      await _pumpDetail(tester, tv: false);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.bottomNavigationBar, isNotNull);
      // 按钮仍在底栏的 GlassContainer 胶囊内
      expect(
        find.ancestor(
            of: find.text('开始播放'), matching: find.byType(GlassContainer)),
        findsOneWidget,
      );
      // 内容流中不出现内联按钮行
      expect(
        find.ancestor(
            of: find.text('开始播放'), matching: find.byType(TvFocusable)),
        findsNothing,
      );
    });
  });
}

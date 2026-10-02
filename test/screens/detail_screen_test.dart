import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/palette_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/providers/track_provider.dart';
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

Future<ProviderContainer> _pumpDetail(
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
  return container;
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

    testWidgets('非 TV 回归：胶囊底栏取消，播放按钮进内容流（简介上方）', (tester) async {
      await _pumpDetail(tester, tv: false);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.bottomNavigationBar, isNull,
          reason: '播放/建房已进内容流，非 roomMode 不再渲染胶囊底栏');
      // 按钮不被 GlassContainer 托盘包裹
      expect(
        find.ancestor(
            of: find.text('开始播放'), matching: find.byType(GlassContainer)),
        findsNothing,
      );
      // 非 TV 不包 TvFocusable（触摸直接点按钮）
      expect(
        find.ancestor(
            of: find.text('开始播放'), matching: find.byType(TvFocusable)),
        findsNothing,
      );
      // 按钮位于简介上方
      final btn = tester.getRect(find.text('开始播放'));
      final desc = tester.getRect(find.text('简介'));
      expect(btn.top, lessThan(desc.top));
    });

    testWidgets('非 TV roomMode：胶囊底栏保留「加入资源」', (tester) async {
      await _pumpDetail(tester, tv: false, roomMode: true);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.bottomNavigationBar, isNotNull);
      expect(
        find.ancestor(
            of: find.text('加入资源'), matching: find.byType(GlassContainer)),
        findsOneWidget,
      );
      expect(find.text('开始播放'), findsNothing);
    });
  });

  // ---- 剧集分季（选季下拉 / 该季剧集 / 播出季季卡） ----

  final series = MediaItem(
    id: 'sv1',
    name: '测试剧集',
    type: 'Series',
    posterUrl: _posterUrl,
    overview: '剧集简介。',
  );

  MediaItem ep(String id,
          {int season = 1, int number = 1, DateTime? premiere}) =>
      MediaItem(
        id: id,
        name: '第$number集',
        type: 'Episode',
        parentIndexNumber: season,
        indexNumber: number,
        premiereDate: premiere,
        overview: '剧情简介$id',
      );

  final seasons = [
    MediaItem(
        id: 'sea1', name: '第1季', type: 'Season', indexNumber: 1, childCount: 2),
    MediaItem(
        id: 'sea2', name: '第2季', type: 'Season', indexNumber: 2, childCount: 1),
  ];

  final episodesByParent = {
    'sv1': [
      ep('e1', season: 1, number: 1, premiere: DateTime(2022, 3, 31)),
      ep('e2', season: 1, number: 2),
      ep('e3', season: 2, number: 1),
    ],
  };

  group('剧集分季详情页', () {
    testWidgets('渲染选季器/播出季季卡/该季剧集，默认第1季', (tester) async {
      await _pumpDetail(
        tester,
        item: series,
        emby: FakeEmbyService(
          item: series,
          itemsByParent: episodesByParent,
          seasons: seasons,
        ),
      );

      expect(find.byKey(const Key('seriesSeasonSelector')), findsOneWidget);
      expect(find.text('播出季'), findsOneWidget);
      expect(find.byKey(const Key('seasonCard_sea1')), findsOneWidget);
      expect(find.byKey(const Key('seasonCard_sea2')), findsOneWidget);

      // 第1季两集可见，第2季集不在列表
      expect(find.byKey(const Key('episodeCard_e1')), findsOneWidget);
      expect(find.byKey(const Key('episodeCard_e2')), findsOneWidget);
      expect(find.byKey(const Key('episodeCard_e3')), findsNothing);

      // 剧集卡：日期 meta + 简介
      expect(find.text('2022年3月31日'), findsOneWidget);
      expect(find.text('剧情简介e1'), findsOneWidget);

      // 有集时剧集页显示播放按钮
      expect(find.text('开始播放'), findsOneWidget);
      expect(find.text('第 1 季'), findsWidgets);
    });

    testWidgets('点第2季卡 → 上方剧集列表切换为第2季', (tester) async {
      await _pumpDetail(
        tester,
        item: series,
        emby: FakeEmbyService(
          item: series,
          itemsByParent: episodesByParent,
          seasons: seasons,
        ),
      );

      final card = find.byKey(const Key('seasonCard_sea2'));
      await tester.ensureVisible(card);
      await tester.pump();
      await tester.tap(card);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('episodeCard_e3')), findsOneWidget);
      expect(find.byKey(const Key('episodeCard_e1')), findsNothing);
      expect(find.byKey(const Key('episodeCard_e2')), findsNothing);
      // 选季器跟随切换
      expect(find.text('第 2 季'), findsWidgets);
    });

    testWidgets('Seasons 接口为空时按集分组兜底出合成季', (tester) async {
      await _pumpDetail(
        tester,
        item: series,
        emby: FakeEmbyService(
          item: series,
          itemsByParent: episodesByParent,
          seasons: const [],
        ),
      );

      expect(find.byKey(const Key('seasonCard_season_1')), findsOneWidget);
      expect(find.byKey(const Key('seasonCard_season_2')), findsOneWidget);
      // 合成季集数徽章
      expect(find.text('2集'), findsOneWidget);
      expect(find.text('1集'), findsOneWidget);
      expect(find.byKey(const Key('episodeCard_e1')), findsOneWidget);
    });

    testWidgets('下拉选季切换（非 TV 点 DropdownButton）', (tester) async {
      await _pumpDetail(
        tester,
        item: series,
        emby: FakeEmbyService(
          item: series,
          itemsByParent: episodesByParent,
          seasons: seasons,
        ),
      );

      final selector = find.byKey(const Key('seriesSeasonSelector'));
      await tester.ensureVisible(selector);
      await tester.pump();
      await tester.tap(selector);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text('第 2 季').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byKey(const Key('episodeCard_e3')), findsOneWidget);
      expect(find.byKey(const Key('episodeCard_e1')), findsNothing);
    });

    testWidgets('电影页不渲染分季区块', (tester) async {
      await _pumpDetail(tester);

      expect(find.byKey(const Key('seriesSeasonSelector')), findsNothing);
      expect(find.byKey(const Key('seasonCard_sea1')), findsNothing);
      expect(find.text('播出季'), findsNothing);
    });
  });

  // ---- 字幕/音轨选择器（操作图标行） ----

  group('字幕/音轨选择器', () {
    final trackItem = MediaItem(
      id: 'm1',
      name: '测试影片',
      type: 'Movie',
      posterUrl: _posterUrl,
      overview: '简介。',
      mediaStreams: [
        MediaStream(type: 'Video', codec: 'hevc', width: 1920, height: 1080),
        MediaStream(type: 'Audio', codec: 'aac', language: 'chi', index: 0),
        MediaStream(type: 'Audio', codec: 'ac3', language: 'eng', index: 1),
        MediaStream(type: 'Subtitle', codec: 'srt', language: 'chi', index: 3),
      ],
    );

    testWidgets('有字幕/多音轨时显示两个图标；选中写入预选 provider', (tester) async {
      final container = await _pumpDetail(
        tester,
        item: trackItem,
        emby: FakeEmbyService(item: trackItem),
      );

      expect(find.byKey(const Key('subtitleSelectorButton')), findsOneWidget);
      expect(find.byKey(const Key('audioSelectorButton')), findsOneWidget);

      // 字幕选择器（图片占位转圈动画永动，不能 pumpAndSettle，用固定帧）
      final subtitleBtn = find.byKey(const Key('subtitleSelectorButton'));
      await tester.ensureVisible(subtitleBtn);
      await tester.pump();
      await tester.tap(subtitleBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('字幕'), findsOneWidget);
      expect(find.byKey(const Key('trackOption_auto')), findsOneWidget);
      expect(find.byKey(const Key('trackOption_-1')), findsOneWidget);
      expect(find.byKey(const Key('trackOption_3')), findsOneWidget);

      await tester.tap(find.byKey(const Key('trackOption_-1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        container.read(pendingTrackSelectionProvider)?.subtitleIndex,
        -1,
        reason: '关闭字幕写入 -1',
      );

      // 音轨选择器：写入音轨且保留字幕预选
      final audioBtn = find.byKey(const Key('audioSelectorButton'));
      await tester.ensureVisible(audioBtn);
      await tester.pump();
      await tester.tap(audioBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('音轨'), findsOneWidget);
      await tester.tap(find.byKey(const Key('trackOption_1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final selection = container.read(pendingTrackSelectionProvider);
      expect(selection?.audioIndex, 1);
      expect(selection?.subtitleIndex, -1, reason: '音轨选择不冲掉字幕预选');
    });

    testWidgets('无字幕且单音轨时隐藏两个图标', (tester) async {
      final single = MediaItem(
        id: 'm1',
        name: '测试影片',
        type: 'Movie',
        posterUrl: _posterUrl,
        mediaStreams: [
          MediaStream(type: 'Video', codec: 'hevc'),
          MediaStream(type: 'Audio', codec: 'aac', index: 0),
        ],
      );
      await _pumpDetail(tester,
          item: single, emby: FakeEmbyService(item: single));

      expect(find.byKey(const Key('subtitleSelectorButton')), findsNothing);
      expect(find.byKey(const Key('audioSelectorButton')), findsNothing);
    });

    testWidgets('TV 模式图标被 TvFocusable 包裹', (tester) async {
      await _pumpDetail(tester,
          tv: true, item: trackItem, emby: FakeEmbyService(item: trackItem));

      expect(
        find.ancestor(
            of: find.byKey(const Key('subtitleSelectorButton')),
            matching: find.byType(TvFocusable)),
        findsOneWidget,
      );
    });
  });

  // ---- 顶部徽章 TV-MA / 4K ----

  testWidgets('顶部 meta 显示 TV-MA 与 4K 徽章', (tester) async {
    final item = MediaItem(
      id: 'm1',
      name: '测试影片',
      type: 'Movie',
      posterUrl: _posterUrl,
      officialRating: 'TV-MA',
      mediaStreams: [
        MediaStream(type: 'Video', codec: 'hevc', width: 3840, height: 2160),
      ],
    );
    await _pumpDetail(tester, item: item, emby: FakeEmbyService(item: item));

    expect(find.text('TV-MA'), findsOneWidget);
    expect(find.text('4K'), findsOneWidget);
  });
}

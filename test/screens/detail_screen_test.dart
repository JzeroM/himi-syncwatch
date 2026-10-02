import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/palette_provider.dart';
import 'package:himi_syncwatch/providers/room_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/providers/track_provider.dart';
import 'package:himi_syncwatch/screens/detail/detail_screen.dart';
import 'package:himi_syncwatch/screens/detail/series_sections.dart';
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

      // 页面级胶囊托盘已取消，按钮自身为玻璃质感（GlassContainer 外壳）
      expect(
        find.ancestor(
            of: find.text('开始播放'), matching: find.byType(GlassContainer)),
        findsOneWidget,
        reason: '播放按钮应带玻璃外壳',
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
      // 按钮为玻璃质感（GlassContainer 外壳），且非 TV 不包 TvFocusable
      expect(
        find.ancestor(
            of: find.text('开始播放'), matching: find.byType(GlassContainer)),
        findsOneWidget,
      );
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

  // ---- 版本选择器与字幕/音轨联动 ----

  group('版本选择器', () {
    final src1 = MediaSource(
      id: 'src1',
      name: '1080p版',
      mediaStreams: [
        MediaStream(type: 'Video', codec: 'hevc'),
        MediaStream(type: 'Audio', codec: 'aac', language: 'chi', index: 1),
        MediaStream(type: 'Audio', codec: 'ac3', language: 'eng', index: 2),
        MediaStream(type: 'Subtitle', codec: 'srt', language: 'chi', index: 3),
        MediaStream(type: 'Subtitle', codec: 'srt', language: 'jpn', index: 4),
      ],
    );
    final src2 = MediaSource(
      id: 'src2',
      name: '4K版',
      mediaStreams: [
        MediaStream(type: 'Video', codec: 'hevc'),
        MediaStream(type: 'Audio', codec: 'eac3', language: 'eng', index: 1),
        MediaStream(type: 'Subtitle', codec: 'ass', language: 'jpn', index: 5),
      ],
    );
    final multi = MediaItem(
      id: 'mv1',
      name: '多版本影片',
      type: 'Movie',
      posterUrl: _posterUrl,
      mediaStreams: [...src1.mediaStreams],
      mediaSources: [src1, src2],
    );

    Future<ProviderContainer> pumpMulti(WidgetTester t, {bool tv = false}) =>
        _pumpDetail(t, item: multi, emby: FakeEmbyService(item: multi), tv: tv);

    Future<void> openSheet(WidgetTester t, Key key) async {
      final btn = find.byKey(key);
      await t.ensureVisible(btn);
      await t.pump();
      await t.tap(btn);
      await t.pump();
      await t.pump(const Duration(milliseconds: 350));
    }

    Future<void> closeSheet(WidgetTester t) async {
      t.state<NavigatorState>(find.byType(Navigator)).pop();
      await t.pump();
      await t.pump(const Duration(milliseconds: 350));
    }

    testWidgets('单版本资源隐藏版本图标', (tester) async {
      await _pumpDetail(tester);
      expect(find.byKey(const Key('versionSelectorButton')), findsNothing);
    });

    testWidgets('多版本显示图标且排在字幕前', (tester) async {
      await pumpMulti(tester);
      final versionBtn = find.byKey(const Key('versionSelectorButton'));
      final subtitleBtn = find.byKey(const Key('subtitleSelectorButton'));
      expect(versionBtn, findsOneWidget);
      await tester.ensureVisible(versionBtn);
      await tester.ensureVisible(subtitleBtn);
      expect(
        tester.getRect(versionBtn).left,
        lessThan(tester.getRect(subtitleBtn).left),
        reason: '版本图标在字幕图标前',
      );
    });

    testWidgets('点图标弹版本 sheet，选中后图标高亮', (tester) async {
      await pumpMulti(tester);

      await openSheet(tester, const Key('versionSelectorButton'));
      expect(find.text('选择版本'), findsOneWidget);
      expect(find.byKey(const Key('versionOption_src1')), findsOneWidget);
      expect(find.byKey(const Key('versionOption_src2')), findsOneWidget);

      await tester.tap(find.byKey(const Key('versionOption_src2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byKey(const Key('versionOption_src2')), findsNothing);

      final icon = tester
          .widget<IconButton>(find.byKey(const Key('versionSelectorButton')));
      expect(icon.color, ThemeData.dark().colorScheme.primary,
          reason: '已选版本高亮主色');
    });

    testWidgets('切版本后字幕/音轨流列表跟随新版本', (tester) async {
      await pumpMulti(tester);

      // 未选版本：回退顶层流（= src1 流集）
      await openSheet(tester, const Key('subtitleSelectorButton'));
      expect(find.byKey(const Key('trackOption_3')), findsOneWidget);
      expect(find.byKey(const Key('trackOption_4')), findsOneWidget);
      expect(find.byKey(const Key('trackOption_5')), findsNothing);
      await closeSheet(tester);

      // 切到 src2：字幕仅 jpn(5)，音轨仅 eng(1)
      await openSheet(tester, const Key('versionSelectorButton'));
      await tester.tap(find.byKey(const Key('versionOption_src2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      await openSheet(tester, const Key('subtitleSelectorButton'));
      expect(find.byKey(const Key('trackOption_5')), findsOneWidget);
      expect(find.byKey(const Key('trackOption_3')), findsNothing);
      expect(find.byKey(const Key('trackOption_4')), findsNothing);
      await closeSheet(tester);

      // src2 仅一条音轨 → 音轨图标按规则隐藏
      expect(find.byKey(const Key('audioSelectorButton')), findsNothing);
    });

    testWidgets('切版本预选按语言迁移，无同语言轨则清空', (tester) async {
      final container = await pumpMulti(tester);

      // src1 预选：字幕 jpn(4)、音轨 chi(1)
      await openSheet(tester, const Key('subtitleSelectorButton'));
      await tester.tap(find.byKey(const Key('trackOption_4')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await openSheet(tester, const Key('audioSelectorButton'));
      await tester.tap(find.byKey(const Key('trackOption_1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final before = container.read(pendingTrackSelectionProvider);
      expect(before?.subtitleIndex, 4);
      expect(before?.audioIndex, 1);

      // 切 src2：jpn 字幕存在 → 迁移到 5；chi 音轨不存在 → 清空
      await openSheet(tester, const Key('versionSelectorButton'));
      await tester.tap(find.byKey(const Key('versionOption_src2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final after = container.read(pendingTrackSelectionProvider);
      expect(after?.subtitleIndex, 5, reason: 'jpn 字幕迁移到 src2 的 index');
      expect(after?.audioIndex, isNull, reason: 'src2 无 chi 音轨 → 清空');
    });

    testWidgets('TV 模式版本图标被 TvFocusable 包裹', (tester) async {
      await pumpMulti(tester, tv: true);

      expect(
        find.ancestor(
            of: find.byKey(const Key('versionSelectorButton')),
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

  // ---- 玻璃按钮行 ----

  group('玻璃按钮行', () {
    testWidgets('开始播放/建房各占约半行且带玻璃外壳', (tester) async {
      await _pumpDetail(tester);

      // FilledButton.icon 是私有子类，byType 不命中，用玻璃外壳 rect 断言
      final playGlass = find
          .ancestor(
              of: find.text('开始播放'), matching: find.byType(GlassContainer))
          .last;
      final roomGlass = find
          .ancestor(of: find.text('建房'), matching: find.byType(GlassContainer))
          .last;
      final play = tester.getRect(playGlass);
      final room = tester.getRect(roomGlass);

      // 内容区左右 padding 16，两按钮间距 12：每侧约 (800-32-12)/2
      expect(play.width, greaterThan(340));
      expect(room.width, greaterThan(340));
      expect(play.width, closeTo(room.width, 1), reason: '两按钮等宽');

      // 玻璃外壳（GlassContainer）包裹
      expect(
        find.ancestor(
            of: find.text('开始播放'), matching: find.byType(GlassContainer)),
        findsOneWidget,
      );
      expect(
        find.ancestor(
            of: find.text('建房'), matching: find.byType(GlassContainer)),
        findsOneWidget,
      );
    });

    testWidgets('非 TV roomMode 单一入口：仅底栏加入资源，内容流无重复', (tester) async {
      await _pumpDetail(tester, roomMode: true);

      expect(find.text('加入资源'), findsOneWidget,
          reason: '内容流操作行在非 TV roomMode 下隐藏，入口只在底栏');
      expect(find.text('开始播放'), findsNothing);
    });
  });

  // ---- 播出季卡宽度 ----

  testWidgets('播出季卡加宽（约 104）', (tester) async {
    await _pumpDetail(
      tester,
      item: series,
      emby: FakeEmbyService(
        item: series,
        itemsByParent: episodesByParent,
        seasons: seasons,
      ),
    );

    final card = find.byKey(const Key('seasonCard_sea1'));
    await tester.ensureVisible(card);
    await tester.pump();
    expect(tester.getRect(card).width, closeTo(104, 1));
  });

  // ---- 数字网格选集器 ----

  group('数字网格选集器', () {
    Future<ProviderContainer> pumpSeries(WidgetTester tester) {
      return _pumpDetail(
        tester,
        item: series,
        emby: FakeEmbyService(
          item: series,
          itemsByParent: episodesByParent,
          seasons: seasons,
        ),
      );
    }

    testWidgets('入口打开 sheet：标题/该季数字格/首集高亮', (tester) async {
      await pumpSeries(tester);

      final btn = find.byKey(const Key('episodePickerButton'));
      await tester.ensureVisible(btn);
      await tester.pump();
      await tester.tap(btn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byKey(const Key('episodePickerTitle')), findsOneWidget);
      // 第 1 季两集，第 2 季集不出现
      expect(find.byKey(const Key('episodeNumber_e1')), findsOneWidget);
      expect(find.byKey(const Key('episodeNumber_e2')), findsOneWidget);
      expect(find.byKey(const Key('episodeNumber_e3')), findsNothing);

      // 首集高亮：边框为主色
      final tile =
          tester.widget<Container>(find.byKey(const Key('episodeNumber_e1')));
      final deco = tile.decoration! as BoxDecoration;
      expect(deco.border?.top.color, ThemeData.dark().colorScheme.primary);

      // 未选集的另一集无高亮
      final plain =
          tester.widget<Container>(find.byKey(const Key('episodeNumber_e2')));
      expect((plain.decoration! as BoxDecoration).border?.top.color,
          Colors.transparent);
    });

    testWidgets('点数字仅选中：sheet 关闭，再次打开高亮跟随', (tester) async {
      await pumpSeries(tester);

      Future<void> openPicker() async {
        final btn = find.byKey(const Key('episodePickerButton'));
        await tester.ensureVisible(btn);
        await tester.pump();
        await tester.tap(btn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
      }

      await openPicker();
      await tester.tap(find.byKey(const Key('episodeNumber_e2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byKey(const Key('episodePickerTitle')), findsNothing,
          reason: '选中后 sheet 关闭');
      // 选中触发的定位滚动（350ms 延迟 + 250ms ensureVisible 动画）结束
      await tester.pump(const Duration(milliseconds: 600));

      await openPicker();
      final tile =
          tester.widget<Container>(find.byKey(const Key('episodeNumber_e2')));
      expect((tile.decoration! as BoxDecoration).border?.top.color,
          ThemeData.dark().colorScheme.primary,
          reason: '高亮跟随到点选的第 2 集');
    });

    testWidgets('sheet 内排序切换：网格顺序翻转', (tester) async {
      await pumpSeries(tester);

      final btn = find.byKey(const Key('episodePickerButton'));
      await tester.ensureVisible(btn);
      await tester.pump();
      await tester.tap(btn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // 正序：e1 在左、e2 在右
      final e1a = tester.getRect(find.byKey(const Key('episodeNumber_e1')));
      final e2a = tester.getRect(find.byKey(const Key('episodeNumber_e2')));
      expect(e1a.left, lessThan(e2a.left));

      await tester.tap(find.byKey(const Key('episodeSortToggleInSheet')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final e1b = tester.getRect(find.byKey(const Key('episodeNumber_e1')));
      final e2b = tester.getRect(find.byKey(const Key('episodeNumber_e2')));
      expect(e2b.left, lessThan(e1b.left), reason: '倒序后 e2 在左');
    });

    testWidgets('外部排序入口：剧集横卡行顺序翻转', (tester) async {
      await pumpSeries(tester);

      final row = find.byKey(const Key('episodeCard_e1'));
      final row2 = find.byKey(const Key('episodeCard_e2'));
      expect(tester.getRect(row).left, lessThan(tester.getRect(row2).left),
          reason: '默认正序');

      final toggle = find.byKey(const Key('episodeSortToggle'));
      await tester.ensureVisible(toggle);
      await tester.pump();
      await tester.tap(toggle);
      await tester.pump();

      expect(
          tester.getRect(find.byKey(const Key('episodeCard_e2'))).left,
          lessThan(
              tester.getRect(find.byKey(const Key('episodeCard_e1'))).left),
          reason: '倒序后第 2 集在左');
    });

    testWidgets('TV：入口与数字格被 TvFocusable 包裹', (tester) async {
      await _pumpDetail(
        tester,
        tv: true,
        item: series,
        emby: FakeEmbyService(
          item: series,
          itemsByParent: episodesByParent,
          seasons: seasons,
        ),
      );

      expect(
        find.ancestor(
            of: find.byKey(const Key('episodePickerButton')),
            matching: find.byType(TvFocusable)),
        findsOneWidget,
      );
      expect(
        find.ancestor(
            of: find.byKey(const Key('episodeSortToggle')),
            matching: find.byType(TvFocusable)),
        findsOneWidget,
      );

      final btn = find.byKey(const Key('episodePickerButton'));
      await tester.ensureVisible(btn);
      await tester.pump();
      await tester.tap(btn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(
        find.ancestor(
            of: find.byKey(const Key('episodeNumber_e1')),
            matching: find.byType(TvFocusable)),
        findsOneWidget,
      );
    });
  });

  // ---- 选集定位与横卡高亮 ----

  group('选集定位与横卡高亮', () {
    Future<ProviderContainer> pumpSeries(WidgetTester tester) {
      return _pumpDetail(
        tester,
        item: series,
        emby: FakeEmbyService(
          item: series,
          itemsByParent: episodesByParent,
          seasons: seasons,
        ),
      );
    }

    /// 打开网格 → 点 [episodeKey] → 关 sheet 并等定位动画（350 延迟 + 250 滚动）。
    Future<void> pickViaGrid(WidgetTester tester, String episodeKey) async {
      final btn = find.byKey(const Key('episodePickerButton'));
      await tester.ensureVisible(btn);
      await tester.pump();
      await tester.tap(btn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.byKey(Key('episodeNumber_$episodeKey')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 600));
    }

    BoxDecoration borderOf(WidgetTester tester, Key key) {
      final card = tester.widget<Container>(find.byKey(key));
      return card.decoration! as BoxDecoration;
    }

    testWidgets('网格选中集 → 横卡图片描边，文字区不描边', (tester) async {
      await pumpSeries(tester);

      expect(
          borderOf(tester, const Key('episodeCardImage_e1')).border?.top.color,
          Colors.transparent,
          reason: '未选中时无描边');
      expect(
          tester
              .widget<Container>(find.byKey(const Key('episodeCard_e1')))
              .decoration,
          isNull,
          reason: '整卡（文字/简介区）不描边');

      await pickViaGrid(tester, 'e2');

      expect(
          borderOf(tester, const Key('episodeCardImage_e2')).border?.top.color,
          ThemeData.dark().colorScheme.primary,
          reason: '选中集图片描边高亮');
      expect(
          borderOf(tester, const Key('episodeCardImage_e1')).border?.top.color,
          Colors.transparent);
    });

    testWidgets('点横卡仅选中描边，不进播放器', (tester) async {
      await pumpSeries(tester);

      final card = find.byKey(const Key('episodeCard_e2'));
      await tester.ensureVisible(card);
      await tester.pump();
      await tester.tap(card);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 测试环境无 GoRouter，若走到 context.push 必然抛出；
      // 无异常 = 仅选中、未触发播放跳转
      expect(tester.takeException(), isNull, reason: '点横卡不跳播放器');
      expect(
          borderOf(tester, const Key('episodeCardImage_e2')).border?.top.color,
          ThemeData.dark().colorScheme.primary,
          reason: '点横卡设为选中');
      expect(
          borderOf(tester, const Key('episodeCardImage_e1')).border?.top.color,
          Colors.transparent);
    });

    testWidgets('选季卡：描边仅海报图，第N季文字不随选中高亮', (tester) async {
      await pumpSeries(tester);

      expect(
          borderOf(tester, const Key('seasonCardImage_sea1')).border?.top.color,
          ThemeData.dark().colorScheme.primary,
          reason: '默认选中第 1 季，描边在海报图上');
      expect(
          borderOf(tester, const Key('seasonCardImage_sea2')).border?.top.color,
          Colors.transparent);
      expect(
          tester
              .widget<Container>(find.byKey(const Key('seasonCard_sea1')))
              .decoration,
          isNull,
          reason: '整张季卡不描边');

      final sea2 = find.byKey(const Key('seasonCard_sea2'));
      await tester.ensureVisible(sea2);
      await tester.pump();
      await tester.tap(sea2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
          borderOf(tester, const Key('seasonCardImage_sea2')).border?.top.color,
          ThemeData.dark().colorScheme.primary,
          reason: '切季后海报描边跟随');
      expect(
          borderOf(tester, const Key('seasonCardImage_sea1')).border?.top.color,
          Colors.transparent);

      final label = tester.widget<Text>(
          find.descendant(of: sea2, matching: find.text('第 2 季')));
      expect(label.style?.color, Colors.white70, reason: '文字不随选中变主色');
      expect(label.style?.fontWeight ?? FontWeight.normal, FontWeight.normal,
          reason: '文字不随选中加粗');
      // 切季联动：第 2 季的集替换第 1 季
      expect(find.byKey(const Key('episodeCard_e3')), findsOneWidget);
      expect(find.byKey(const Key('episodeCard_e1')), findsNothing);
    });

    testWidgets('点开始播放：序列化整部并跳播放器', (tester) async {
      // 本用例单独挂最小 GoRouter：push 到假 player 路由，以「路由实际
      // 跳转 + pendingRoomEpisodes 序列化」双重断言播放入口。
      final container = ProviderContainer(overrides: [
        settingsProvider
            .overrideWith((ref) => FakeSettingsNotifier(const AppSettings())),
        embyServiceProvider.overrideWith((ref) => FakeEmbyService(
            item: series, itemsByParent: episodesByParent, seasons: seasons)),
        posterColorProvider(_posterUrl).overrideWith((ref) async => null),
      ]);
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: '/detail',
        routes: [
          GoRoute(
            path: '/detail',
            builder: (c, s) => DetailScreen(itemId: series.id),
          ),
          GoRoute(
            path: '/player/:id',
            builder: (c, s) => const SizedBox(key: Key('fakePlayer')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: ThemeData.dark(),
          routerConfig: router,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));

      final btn = find.text('开始播放');
      await tester.ensureVisible(btn);
      await tester.pump();
      await tester.tap(btn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('fakePlayer')), findsOneWidget,
          reason: '点开始播放跳转播放器');

      final pending = container.read(pendingRoomEpisodesProvider);
      expect(pending, isNotNull, reason: '整部已序列化');
      expect(pending!.length, 3, reason: 'fixture 共 3 集全部入列');
      expect(pending.first['id'], 'e1', reason: '正序首集在前');
    });

    testWidgets('选中视口外远集 → 横卡行滚动定位该集', (tester) async {
      final farEpisodes = [
        for (var i = 1; i <= 7; i++) ep('e$i', season: 1, number: i),
      ];
      await _pumpDetail(
        tester,
        item: series,
        emby: FakeEmbyService(
          item: series,
          itemsByParent: {'sv1': farEpisodes},
          seasons: [seasons.first],
        ),
      );

      expect(find.byKey(const Key('episodeCard_e7')), findsNothing,
          reason: '视口+缓存范围外初始不构建');

      await pickViaGrid(tester, 'e7');

      expect(find.byKey(const Key('episodeCard_e7')), findsOneWidget,
          reason: '水平滚动到第 7 集');
      expect(
          borderOf(tester, const Key('episodeCardImage_e7')).border?.top.color,
          ThemeData.dark().colorScheme.primary);

      // 垂直：分季区块滚入逻辑视口（600 高）
      final logicalHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final sectionRect = tester.getRect(find.byType(SeriesSections));
      expect(sectionRect.top, lessThan(logicalHeight), reason: '横卡行区块在视口内');
      expect(sectionRect.bottom, greaterThan(0));

      // 锚定操作行：高亮图片卡顶可见 + 开始播放/建房完整可见
      final imgRect =
          tester.getRect(find.byKey(const Key('episodeCardImage_e7')));
      expect(imgRect.top, greaterThanOrEqualTo(0), reason: '高亮图片卡顶部进入视口');
      expect(imgRect.top, lessThan(logicalHeight), reason: '高亮图片卡在视口上方边界内');
      for (final label in ['开始播放', '建房']) {
        final r = tester.getRect(find.text(label));
        expect(r.top, greaterThanOrEqualTo(0), reason: '$label 可见');
        expect(r.bottom, lessThanOrEqualTo(logicalHeight),
            reason: '$label 完整可见（锚点不过分靠下）');
      }
    });
  });
}

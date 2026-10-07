import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/agora_config_model.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/agora_provider.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/palette_provider.dart';
import 'package:himi_syncwatch/providers/playback_report_provider.dart';
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

/// 带最小 GoRouter 的详情页：`/detail` → DetailScreen，`/player/:id` 落到
/// 一个把路由参数打印出来的桩页，用于断言播放跳转的 query。
Future<ProviderContainer> _pumpDetailInRouter(
  WidgetTester tester, {
  required MediaItem item,
  FakeEmbyService? emby,
  List<Override> extraOverrides = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      settingsProvider
          .overrideWith((ref) => FakeSettingsNotifier(const AppSettings())),
      embyServiceProvider
          .overrideWith((ref) => emby ?? FakeEmbyService(item: item)),
      posterTrioProvider(_posterUrl).overrideWith((ref) async => null),
      ...extraOverrides,
    ],
  );
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: '/detail',
    routes: [
      GoRoute(
        path: '/detail',
        builder: (ctx, st) => DetailScreen(itemId: item.id),
      ),
      GoRoute(
        path: '/player/:id',
        builder: (ctx, st) => Scaffold(
          body: Text('PLAYER:${st.pathParameters['id']}|${st.uri.query}'),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        theme: ThemeData.dark(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 600));
  return container;
}

/// 焦点是否位于 [finder] 所指子树内。
/// 读取某选项所属 RadioGroup 的 groupValue（v3.47 Radio 重构后
/// groupValue 从 RadioListTile 移到了 RadioGroup 祖先）。
T? _groupValueOf<T>(WidgetTester tester, Key optionKey) {
  return tester
      .widget<RadioGroup<T>>(
        find.ancestor(
          of: find.byKey(optionKey),
          matching: find.byType(RadioGroup<T>),
        ),
      )
      .groupValue;
}

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

/// getItemDetails 依次返回 [sequence] 中条目的 Fake（验证返回播放器后
/// 详情页静默刷新读取到最新进度）。
class _SeqItemFakeService extends FakeEmbyService {
  _SeqItemFakeService({required this.sequence});

  final List<MediaItem?> sequence;
  int calls = 0;

  @override
  Future<MediaItem?> getItemDetails(String id) async {
    final r = calls < sequence.length ? sequence[calls] : sequence.last;
    calls++;
    return r;
  }
}

void main() {
  testWidgets('非 TV：正文铺虚化氛围底图 + 压暗罩，顶部海报保持清晰', (tester) async {
    await _pumpDetail(tester);

    // 正文氛围层（低分模糊图 + 压暗罩）存在
    expect(find.byKey(const Key('detailAmbientImage')), findsOneWidget);
    expect(find.byKey(const Key('detailAmbientScrim')), findsOneWidget);

    // 页面背景不再使用纯色渐变（改为底色打底）
    final container = tester
        .widget<AnimatedContainer>(find.byKey(const Key('detailBackground')));
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.gradient, isNull, reason: '方案 A：正文改用虚化底图，不再叠加纯色渐变');

    // 顶部海报仍是清晰原图（SliverAppBar 内），未被 TV 整页方案替换
    expect(find.byKey(const Key('detailBackdrop')), findsNothing);
    expect(find.byKey(const Key('detailBackdropScrim')), findsNothing);
    expect(
      find.descendant(
        of: find.byType(FlexibleSpaceBar),
        matching: find.byType(EmbyImage),
      ),
      findsOneWidget,
    );
    expect(find.text('测试影片'), findsWidgets);
  });

  // ---- TV 详情页：海报整页背景 + 操作行合排 ----

  group('TV 海报背景与操作行合排', () {
    testWidgets('TV：透明渐变，整页海报背景 + 压暗罩', (tester) async {
      await _pumpDetail(tester, tv: true);

      final container = tester
          .widget<AnimatedContainer>(find.byKey(const Key('detailBackground')));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.gradient, isNull, reason: 'TV 背景由海报 Stack 承担，不再用页面渐变');

      // 整页海报图层 + 上浅下深压暗罩存在
      expect(find.byKey(const Key('detailBackdrop')), findsOneWidget);
      expect(find.byKey(const Key('detailBackdropScrim')), findsOneWidget);

      // SliverAppBar flexibleSpace 不再重复铺海报（与整页背景连成一张图）
      expect(
        find.descendant(
          of: find.byType(FlexibleSpaceBar),
          matching: find.byType(EmbyImage),
        ),
        findsNothing,
      );
    });

    testWidgets('非 TV 回归：氛围底图在、海报仍在 AppBar 内', (tester) async {
      await _pumpDetail(tester);

      expect(find.byKey(const Key('detailAmbientImage')), findsOneWidget);
      expect(find.byKey(const Key('detailAmbientScrim')), findsOneWidget);
      expect(find.byKey(const Key('detailBackdrop')), findsNothing);
      expect(find.byKey(const Key('detailBackdropScrim')), findsNothing);
      expect(
        find.descendant(
          of: find.byType(FlexibleSpaceBar),
          matching: find.byType(EmbyImage),
        ),
        findsOneWidget,
      );
    });

    testWidgets('TV：播放按钮缩小、居行首、与字幕音轨同排', (tester) async {
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
          MediaStream(
              type: 'Subtitle', codec: 'srt', language: 'chi', index: 3),
        ],
      );
      await _pumpDetail(tester,
          tv: true, item: trackItem, emby: FakeEmbyService(item: trackItem));

      final play = find.widgetWithText(FilledButton, '播放');
      final subtitle = find.byKey(const Key('subtitleSelectorButton'));
      final audio = find.byKey(const Key('audioSelectorButton'));
      expect(play, findsOneWidget);
      expect(subtitle, findsOneWidget);
      expect(audio, findsOneWidget);

      final playRect = tester.getRect(play);
      final subRect = tester.getRect(subtitle);

      // 同排：中心线基本对齐（Row 居中对齐）
      expect((playRect.center.dy - subRect.center.dy).abs(), lessThan(8),
          reason: 'TV 播放与字幕/音轨应合为一行');
      // 行首：播放在字幕左边
      expect(playRect.center.dx, lessThan(subRect.center.dx));
      // 缩小：不再 Expanded 占半行（800 宽下半行约 378）
      expect(playRect.width, lessThan(250), reason: 'TV 播放按钮应为紧凑宽度');
      expect(playRect.height, lessThanOrEqualTo(44),
          reason: 'TV 播放按钮应缩小到约 40 高');
    });

    testWidgets('非 TV 回归：播放与选择器仍分两行、播放占半行', (tester) async {
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
          MediaStream(
              type: 'Subtitle', codec: 'srt', language: 'chi', index: 3),
        ],
      );
      await _pumpDetail(tester,
          item: trackItem, emby: FakeEmbyService(item: trackItem));

      final playRect =
          tester.getRect(find.widgetWithText(FilledButton, '开始播放'));
      final subRect =
          tester.getRect(find.byKey(const Key('subtitleSelectorButton')));

      // 分两行：选择器在播放下方
      expect(subRect.top, greaterThan(playRect.bottom));
      expect((playRect.center.dy - subRect.center.dy).abs(), greaterThan(30));
      // 半行宽（800 宽下 Expanded 约 378）
      expect(playRect.width, greaterThan(300));
    });

    testWidgets('TV：播放按钮补水平内边距，文字不贴玻璃胶囊边', (tester) async {
      await _pumpDetail(tester, tv: true);

      final button =
          tester.widget<FilledButton>(find.widgetWithText(FilledButton, '播放'));
      final padding = button.style!.padding!.resolve(<WidgetState>{})!;
      expect(padding.horizontal, greaterThan(0),
          reason: 'TV 紧凑态需水平内边距，否则文字压到胶囊边缘');
    });
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
        posterTrioProvider(_posterUrl).overrideWith((ref) async => null),
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

    // TV 焦点框 1.06 放大溢出内容盒：横行必须 Clip.none，否则裁掉上下边
    final horizontals = tester
        .widgetList<ListView>(find.byType(ListView))
        .where((w) => w.scrollDirection == Axis.horizontal);
    expect(horizontals, isNotEmpty);
    for (final lv in horizontals) {
      expect(lv.clipBehavior, Clip.none);
    }
  });

  group('TV 模式操作按钮（取消胶囊、移到简介上方）', () {
    testWidgets('无胶囊底栏，按钮在简介上方且被 TvFocusable 包裹、自动落焦', (tester) async {
      await _pumpDetail(tester, tv: true);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.bottomNavigationBar, isNull, reason: 'TV 不渲染胶囊底栏');

      // 页面级胶囊托盘已取消，按钮自身为玻璃质感（GlassContainer 外壳）
      expect(
        find.ancestor(
            of: find.text('播放'), matching: find.byType(GlassContainer)),
        findsOneWidget,
        reason: '播放按钮应带玻璃外壳',
      );

      // 简介入口已移至海报（页面顶部），位于开始播放上方
      final desc = tester.getRect(find.text('简介'));
      final btn = tester.getRect(find.text('播放'));
      expect(desc.top, lessThan(btn.top), reason: '简介控件在海报上，操作区在正文（其下方）');

      // TvFocusable 包裹（焦点环/OK 键激活）
      expect(
        find.ancestor(of: find.text('播放'), matching: find.byType(TvFocusable)),
        findsOneWidget,
      );
      // TV 取消房间模式：不渲染建房入口
      expect(find.text('建房'), findsNothing);

      // 进页 autofocus：焦点直接落在开始播放（解决有时无法聚焦）
      expect(
        _focusWithin(find.ancestor(
            of: find.text('播放'), matching: find.byType(TvFocusable))),
        isTrue,
        reason: '进页应自动聚焦开始播放',
      );
    });

    testWidgets('电视剧（无集数据）：TV 取消房间模式后无建房入口', (tester) async {
      final series = MediaItem(
        id: 'm1',
        name: '测试剧集',
        type: 'Series',
        posterUrl: _posterUrl,
        overview: '剧集简介。',
      );
      await _pumpDetail(tester, tv: true, item: series);

      expect(find.text('开始播放'), findsNothing);
      expect(find.text('建房'), findsNothing);
    });

    testWidgets('roomMode：TV 取消房间模式后无「加入资源」入口', (tester) async {
      await _pumpDetail(tester, tv: true, roomMode: true);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.bottomNavigationBar, isNull);
      expect(find.text('开始播放'), findsNothing);
      expect(find.text('加入资源'), findsNothing);
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
      // 简介控件在海报（顶部），位于开始播放上方
      final desc = tester.getRect(find.text('简介'));
      final btn = tester.getRect(find.text('开始播放'));
      expect(desc.top, lessThan(btn.top), reason: '简介入口已移至海报，正文区不再渲染简介块');
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
      expect(find.text('第1季'), findsWidgets);

      // 季行 + 剧集行：TV 焦点框放大溢出内容盒，Clip.none 才不裁边
      final horizontals = tester
          .widgetList<ListView>(find.byType(ListView))
          .where((w) => w.scrollDirection == Axis.horizontal);
      expect(horizontals, isNotEmpty);
      for (final lv in horizontals) {
        expect(lv.clipBehavior, Clip.none);
      }
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
      expect(find.text('第2季'), findsWidgets);
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
      await tester.tap(find.text('第2季').last);
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

      // TV 焦点框放大溢出单元格：网格 Clip.none 才不裁边
      final grids = tester.widgetList<GridView>(find.byType(GridView));
      expect(grids, isNotEmpty);
      for (final g in grids) {
        expect(g.clipBehavior, Clip.none);
      }

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

      final label = tester
          .widget<Text>(find.descendant(of: sea2, matching: find.text('第2季')));
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
        posterTrioProvider(_posterUrl).overrideWith((ref) async => null),
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

  // ---- 每集选择器（方案 A）：版本/字幕/音轨绑选中集 ----

  group('剧集每集选择器（方案 A）', () {
    MediaStream audio(int idx, String lang) =>
        MediaStream(type: 'Audio', codec: 'aac', language: lang, index: idx);
    MediaStream sub(int idx, String lang) =>
        MediaStream(type: 'Subtitle', codec: 'srt', language: lang, index: idx);

    final seriesItem = MediaItem(
      id: 'sv9',
      name: '每集选择剧集',
      type: 'Series',
      posterUrl: _posterUrl,
      overview: '简介。',
    );

    final ep1 = MediaItem(
      id: 'p1',
      name: '第1集',
      type: 'Episode',
      parentIndexNumber: 1,
      indexNumber: 1,
      posterUrl: _posterUrl,
      mediaStreams: [audio(0, 'chi'), audio(1, 'eng'), sub(3, 'chi')],
    );
    final ep2 = MediaItem(
      id: 'p2',
      name: '第2集',
      type: 'Episode',
      parentIndexNumber: 1,
      indexNumber: 2,
      posterUrl: _posterUrl,
      mediaStreams: [audio(0, 'chi'), audio(7, 'jpn'), sub(4, 'chi')],
    );
    final seasons9 = [
      MediaItem(
          id: 'sea9',
          name: '第1季',
          type: 'Season',
          indexNumber: 1,
          childCount: 2),
    ];
    final itemsByParent9 = {
      'sv9': [ep1, ep2],
    };

    FakeEmbyService fake() => FakeEmbyService(
          item: seriesItem,
          itemsByParent: itemsByParent9,
          seasons: seasons9,
        );

    /// 关闭底部弹窗（点遮罩），不改当前选择。
    Future<void> dismissSheet(WidgetTester tester) async {
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }

    /// 点音轨图标 → 选 [optionKey] → 关闭动画。
    Future<void> pickAudio(WidgetTester tester, String optionKey) async {
      final btn = find.byKey(const Key('audioSelectorButton'));
      await tester.ensureVisible(btn);
      await tester.pump();
      await tester.tap(btn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.byKey(Key('trackOption_$optionKey')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }

    /// 打开音轨 sheet 断言用：开 sheet 后返回。
    Future<void> openAudioSheet(WidgetTester tester) async {
      final btn = find.byKey(const Key('audioSelectorButton'));
      await tester.ensureVisible(btn);
      await tester.pump();
      await tester.tap(btn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }

    /// 点横卡选集。
    Future<void> tapCard(WidgetTester tester, String id) async {
      final card = find.byKey(Key('episodeCard_$id'));
      await tester.ensureVisible(card);
      await tester.pump();
      await tester.tap(card);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('预选按集隔离：e1 选轨写 e1 的 map，e2 独立，全局 provider 不动', (tester) async {
      final container =
          await _pumpDetail(tester, item: seriesItem, emby: fake());

      // 默认目标集 = 第1季第1集：字幕/音轨图标显示，单版本无版本图标
      expect(find.byKey(const Key('subtitleSelectorButton')), findsOneWidget);
      expect(find.byKey(const Key('audioSelectorButton')), findsOneWidget);
      expect(find.byKey(const Key('versionSelectorButton')), findsNothing);

      // e1 选 eng 轨（index 1）→ 写入 per-episode map，不动全局 provider
      await pickAudio(tester, '1');
      expect(container.read(pendingTrackSelectionProvider), isNull,
          reason: '剧集预选不写全局槽（播放时才写）');
      var audioBtn = tester
          .widget<IconButton>(find.byKey(const Key('audioSelectorButton')));
      expect(audioBtn.color, ThemeData.dark().colorScheme.primary,
          reason: 'e1 已选轨，图标高亮');

      // 切到 e2 → 选 jpn 轨（index 7），与 e1 互不覆盖
      await tapCard(tester, 'p2');
      await openAudioSheet(tester);
      expect(_groupValueOf<int?>(tester, const Key('trackOption_7')), isNull,
          reason: 'e2 尚未预选');
      await tester.tap(find.byKey(const Key('trackOption_7')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(container.read(pendingTrackSelectionProvider), isNull);

      // 切回 e1 → 打开音轨 sheet，高亮仍是 e1 自己的 index 1
      await tapCard(tester, 'p1');
      await openAudioSheet(tester);
      expect(
        _groupValueOf<int?>(tester, const Key('trackOption_1')),
        1,
        reason: 'e1 预选未被 e2 覆盖',
      );
      await dismissSheet(tester);

      // e1 图标仍高亮、e2 的选择在切回 e2 后可见（互不覆盖）
      audioBtn = tester
          .widget<IconButton>(find.byKey(const Key('audioSelectorButton')));
      expect(audioBtn.color, ThemeData.dark().colorScheme.primary);
      await tapCard(tester, 'p2');
      await openAudioSheet(tester);
      expect(
        _groupValueOf<int?>(tester, const Key('trackOption_7')),
        7,
        reason: 'e2 预选未被 e1 覆盖',
      );
      await dismissSheet(tester);
    });

    testWidgets('选中集变化时图标行绑定跟随（字幕轨按集显示）', (tester) async {
      await _pumpDetail(tester, item: seriesItem, emby: fake());

      // e1 字幕 index 3、e2 字幕 index 4：sheet 选项跟随选中集
      final subBtn = find.byKey(const Key('subtitleSelectorButton'));
      await tester.ensureVisible(subBtn);
      await tester.pump();
      await tester.tap(subBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byKey(const Key('trackOption_3')), findsOneWidget);
      expect(find.byKey(const Key('trackOption_4')), findsNothing);
      await dismissSheet(tester);

      await tapCard(tester, 'p2');
      await tester.ensureVisible(subBtn);
      await tester.pump();
      await tester.tap(subBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byKey(const Key('trackOption_4')), findsOneWidget);
      expect(find.byKey(const Key('trackOption_3')), findsNothing);
      await dismissSheet(tester);
    });

    testWidgets('TV 模式：每集图标被 TvFocusable 包裹', (tester) async {
      await _pumpDetail(tester, tv: true, item: seriesItem, emby: fake());

      for (final key in [
        const Key('subtitleSelectorButton'),
        const Key('audioSelectorButton'),
      ]) {
        expect(
          find.ancestor(
              of: find.byKey(key), matching: find.byType(TvFocusable)),
          findsOneWidget,
        );
      }
    });
  });

  // ---- 每集播放链路：预选/版本 → 播放器（provider + mediaSourceId） ----

  group('每集播放链路', () {
    MediaStream audio(int idx, String lang) =>
        MediaStream(type: 'Audio', codec: 'aac', language: lang, index: idx);
    MediaStream sub(int idx, String lang) =>
        MediaStream(type: 'Subtitle', codec: 'srt', language: lang, index: idx);

    final seriesMv = MediaItem(
      id: 'sv10',
      name: '多版本剧集',
      type: 'Series',
      posterUrl: _posterUrl,
      overview: '简介。',
    );

    final epMv = MediaItem(
      id: 'mv1',
      name: '第1集',
      type: 'Episode',
      parentIndexNumber: 1,
      indexNumber: 1,
      posterUrl: _posterUrl,
      // 顶层流（未选版本时的回退）
      mediaStreams: [audio(0, 'chi'), audio(1, 'eng'), sub(3, 'chi')],
      mediaSources: [
        MediaSource(
          id: 'sv_a',
          name: '版本A',
          width: 1920,
          mediaStreams: [audio(0, 'chi'), audio(1, 'eng'), sub(3, 'chi')],
        ),
        MediaSource(
          id: 'sv_b',
          name: '版本B',
          width: 3840,
          mediaStreams: [audio(7, 'eng'), audio(8, 'chi'), sub(9, 'eng')],
        ),
      ],
    );

    final epPlain = MediaItem(
      id: 'pl1',
      name: '第1集',
      type: 'Episode',
      parentIndexNumber: 1,
      indexNumber: 1,
      posterUrl: _posterUrl,
      mediaStreams: [audio(0, 'chi'), audio(1, 'eng')],
    );

    final seasonsMv = [
      MediaItem(
          id: 'seaMv',
          name: '第1季',
          type: 'Season',
          indexNumber: 1,
          childCount: 1),
    ];

    Future<void> tapStartPlay(WidgetTester tester) async {
      final btn = find.text('开始播放');
      await tester.ensureVisible(btn);
      await tester.pump();
      await tester.tap(btn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('多版本集：选版本 B 后音轨列表切换，播放带 mediaSourceId 与该集预选', (tester) async {
      final container = await _pumpDetailInRouter(
        tester,
        item: seriesMv,
        emby: FakeEmbyService(
          item: seriesMv,
          itemsByParent: {
            'sv10': [epMv],
          },
          seasons: seasonsMv,
        ),
      );

      // 多版本集显示版本图标
      expect(find.byKey(const Key('versionSelectorButton')), findsOneWidget);

      // 选版本 B → 图标高亮、音轨列表切到版本 B 的轨（7/8，无 0/1）
      await tester
          .ensureVisible(find.byKey(const Key('versionSelectorButton')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('versionSelectorButton')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byKey(const Key('versionOption_sv_a')), findsOneWidget);
      expect(find.byKey(const Key('versionOption_sv_b')), findsOneWidget);
      await tester.tap(find.byKey(const Key('versionOption_sv_b')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final versionBtn = tester
          .widget<IconButton>(find.byKey(const Key('versionSelectorButton')));
      expect(versionBtn.color, ThemeData.dark().colorScheme.primary,
          reason: '已选版本图标高亮');

      final audioBtn = find.byKey(const Key('audioSelectorButton'));
      await tester.ensureVisible(audioBtn);
      await tester.pump();
      await tester.tap(audioBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byKey(const Key('trackOption_7')), findsOneWidget,
          reason: '音轨列表已切换为版本 B 的轨');
      expect(find.byKey(const Key('trackOption_0')), findsNothing);
      await tester.tap(find.byKey(const Key('trackOption_7')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      await tapStartPlay(tester);

      // 路由：该集 id + 选中版本
      expect(find.textContaining('PLAYER:mv1'), findsOneWidget);
      expect(
        find.textContaining('mediaSourceId=sv_b'),
        findsOneWidget,
        reason: '播放跳转带该集选中版本',
      );
      // 该集预选在播放时写入全局槽供播放器消费
      final selection = container.read(pendingTrackSelectionProvider);
      expect(selection, isNotNull);
      expect(selection?.audioIndex, 7);
    });

    testWidgets('无预选的集播放：清掉残留预选、路由不带 mediaSourceId', (tester) async {
      final container = await _pumpDetailInRouter(
        tester,
        item: seriesMv,
        emby: FakeEmbyService(
          item: seriesMv,
          itemsByParent: {
            'sv10': [epPlain],
          },
          seasons: seasonsMv,
        ),
      );

      // 人为残留（如上一次电影页的预选）
      container.read(pendingTrackSelectionProvider.notifier).state =
          const TrackSelection(audioIndex: 9);
      expect(container.read(pendingTrackSelectionProvider), isNotNull);

      await tapStartPlay(tester);

      expect(find.textContaining('PLAYER:pl1'), findsOneWidget);
      expect(find.textContaining('mediaSourceId'), findsNothing);
      expect(container.read(pendingTrackSelectionProvider), isNull,
          reason: '该集无预选时显式清空，防止残留串集');
    });
  });

  // ---- 建房选集面板：逐集版本单选 → episodesJson 下发 ----

  group('建房选集面板逐集版本', () {
    MediaStream audio(int idx) =>
        MediaStream(type: 'Audio', codec: 'aac', index: idx);

    final seriesRoom = MediaItem(
      id: 'sv20',
      name: '房间剧集',
      type: 'Series',
      posterUrl: _posterUrl,
      overview: '简介。',
    );

    // 多版本集：两个版本可单选
    final epMulti = MediaItem(
      id: 'eA',
      name: '第1集',
      type: 'Episode',
      parentIndexNumber: 1,
      indexNumber: 1,
      posterUrl: _posterUrl,
      mediaStreams: [audio(0)],
      mediaSources: [
        MediaSource(
            id: 'a2', name: '版本A', width: 1920, mediaStreams: [audio(0)]),
        MediaSource(
            id: 'b2', name: '版本B', width: 3840, mediaStreams: [audio(1)]),
      ],
    );

    // 单版本集：面板内无版本控件
    final epSingle = MediaItem(
      id: 'eB',
      name: '第2集',
      type: 'Episode',
      parentIndexNumber: 1,
      indexNumber: 2,
      posterUrl: _posterUrl,
      mediaStreams: [audio(0)],
    );

    final seasonsRoom = [
      MediaItem(
          id: 'sea20',
          name: '第1季',
          type: 'Season',
          indexNumber: 1,
          childCount: 2),
    ];

    final agoraOverride = agoraConfigProvider.overrideWith(
      (ref) => FakeAgoraConfigNotifier(
        AgoraConfigModel(
          appId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          appCertificate: 'certificate',
        ),
      ),
    );

    Future<ProviderContainer> pumpRoomDetail(WidgetTester tester) {
      return _pumpDetailInRouter(
        tester,
        item: seriesRoom,
        emby: FakeEmbyService(
          item: seriesRoom,
          itemsByParent: {
            'sv20': [epMulti, epSingle]
          },
          seasons: seasonsRoom,
        ),
        extraOverrides: [agoraOverride],
      );
    }

    Future<void> openEpisodePicker(WidgetTester tester) async {
      final btn = find.text('建房');
      await tester.ensureVisible(btn);
      await tester.pump();
      await tester.tap(btn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }

    testWidgets('多版本集行尾版本单选，选 B 后确认建房 episodesJson 带该集 mediaSourceId',
        (tester) async {
      final container = await pumpRoomDetail(tester);
      await openEpisodePicker(tester);

      // 多版本集有版本单选入口，单版本集没有
      expect(find.byKey(const Key('episodeVersionPick_eA')), findsOneWidget);
      expect(find.byKey(const Key('episodeVersionPick_eB')), findsNothing);

      // 打开版本单选弹窗：默认 + 两个版本，radio 单选
      await tester
          .ensureVisible(find.byKey(const Key('episodeVersionPick_eA')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('episodeVersionPick_eA')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byKey(const Key('epVersionDefault_eA')), findsOneWidget);
      expect(find.byKey(const Key('epVersion_eA_a2')), findsOneWidget);
      expect(find.byKey(const Key('epVersion_eA_b2')), findsOneWidget);

      // 选版本 B → 弹窗关闭、行尾 label 更新
      await tester.ensureVisible(find.byKey(const Key('epVersion_eA_b2')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('epVersion_eA_b2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byKey(const Key('epVersionDefault_eA')), findsNothing);
      expect(find.text('版本: 版本B'), findsOneWidget);

      // 确认全选两集 → token 弹窗 → 确定 → 跳播放器
      await tester.ensureVisible(find.text('确认'));
      await tester.pump();
      await tester.tap(find.text('确认'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('建房设置'), findsOneWidget);
      await tester.tap(find.text('确定'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('PLAYER:sv20'), findsOneWidget);

      // episodesJson：选版本的集带 mediaSourceId，未选的不下发该键
      final pending = container.read(pendingRoomEpisodesProvider);
      expect(pending, isNotNull);
      expect(pending!, hasLength(2));
      expect(pending.first['id'], 'eA');
      expect(pending.first['mediaSourceId'], 'b2',
          reason: '面板单选的版本随 episodesJson 下发');
      expect(pending.last['id'], 'eB');
      expect(pending.last.containsKey('mediaSourceId'), isFalse,
          reason: '默认版本不下发 mediaSourceId');
    });

    testWidgets('确认后版本选择回写：再次打开面板回填上次单选', (tester) async {
      await pumpRoomDetail(tester);
      await openEpisodePicker(tester);

      // 选版本 B 后确认（token 弹窗取消，不进播放器）
      await tester
          .ensureVisible(find.byKey(const Key('episodeVersionPick_eA')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('episodeVersionPick_eA')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.ensureVisible(find.byKey(const Key('epVersion_eA_b2')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('epVersion_eA_b2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      await tester.ensureVisible(find.text('确认'));
      await tester.pump();
      await tester.tap(find.text('确认'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('建房设置'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // 回到详情页，再次打开建房面板 → 版本回填为「版本: 版本B」
      await openEpisodePicker(tester);
      expect(find.text('版本: 版本B'), findsOneWidget);
      expect(find.byKey(const Key('episodeVersionPick_eB')), findsNothing,
          reason: '单版本集始终无版本控件');
      expect(find.text('版本: 默认'), findsNothing, reason: '已选版本的集不再显示默认');
    });

    testWidgets('版本单选可切回默认：label 恢复且建房不下发 mediaSourceId', (tester) async {
      final container = await pumpRoomDetail(tester);
      await openEpisodePicker(tester);

      await tester
          .ensureVisible(find.byKey(const Key('episodeVersionPick_eA')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('episodeVersionPick_eA')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.ensureVisible(find.byKey(const Key('epVersion_eA_b2')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('epVersion_eA_b2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('版本: 版本B'), findsOneWidget);

      // 再开单选 → 切回「默认（服务器选择）」
      await tester
          .ensureVisible(find.byKey(const Key('episodeVersionPick_eA')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('episodeVersionPick_eA')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        _groupValueOf<String?>(tester, const Key('epVersionDefault_eA')),
        'b2',
        reason: '重开弹窗时 groupValue 回填当前单选',
      );
      await tester.ensureVisible(find.byKey(const Key('epVersionDefault_eA')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('epVersionDefault_eA')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('版本: 默认'), findsOneWidget);

      // 确认 → token 确定 → episodesJson 不含 mediaSourceId
      await tester.ensureVisible(find.text('确认'));
      await tester.pump();
      await tester.tap(find.text('确认'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text('确定'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('PLAYER:sv20'), findsOneWidget);

      final pending = container.read(pendingRoomEpisodesProvider);
      expect(pending, isNotNull);
      expect(pending!.first.containsKey('mediaSourceId'), isFalse);
    });
  });

  group('AlternateMediaSources（Emby 4.9.x 非管理员多版本）', () {
    // Emby 4.9.x 起批量端点对非管理员每条只回 1 个 MediaSource，
    // 详情页集列表查询必须显式请求该字段，否则每集版本图标不出现
    // （v1.1.59 用户反馈：Emby Web 有 3 个版本、app 里没版本选择器）。
    testWidgets('集列表 getItems 的 fields 含 AlternateMediaSources',
        (tester) async {
      final series = MediaItem(
        id: 'sv-alt',
        name: '多版本剧集',
        type: 'Series',
        posterUrl: _posterUrl,
        overview: '简介。',
      );
      final ep = MediaItem(
        id: 'ep-alt',
        name: '第1集',
        type: 'Episode',
        parentIndexNumber: 1,
        indexNumber: 1,
        posterUrl: _posterUrl,
        mediaSources: [
          MediaSource(id: 'v1', name: '1080p'),
          MediaSource(id: 'v2', name: '2160p'),
        ],
      );
      final fake = FakeEmbyService(
        item: series,
        itemsByParent: {
          'sv-alt': [ep],
        },
        seasons: [
          MediaItem(
              id: 'sea-alt',
              name: '第1季',
              type: 'Season',
              indexNumber: 1,
              childCount: 1),
        ],
      );

      await _pumpDetail(tester, item: series, emby: fake);

      final fields = fake.lastGetItemsFields;
      expect(fields, isNotNull, reason: '集列表查询必须发出');
      expect(fields, contains('MediaSources'));
      expect(fields, contains('AlternateMediaSources'));
    });
  });

  group('TV 适配：横幅与字号', () {
    // 详情页含永续动画（settle 会超时），各断言用独立单 pump 用例
    testWidgets('TV 横幅 expandedHeight=220', (tester) async {
      await _pumpDetail(tester, tv: true);
      final bar = tester.widget<SliverAppBar>(find.byType(SliverAppBar));
      expect(bar.expandedHeight, 220, reason: 'TV 540 逻辑高下横幅降高让位正文');
    });

    testWidgets('非 TV 横幅 expandedHeight=320', (tester) async {
      await _pumpDetail(tester, tv: false);
      final bar = tester.widget<SliverAppBar>(find.byType(SliverAppBar));
      expect(bar.expandedHeight, 320, reason: '非 TV 保持原横幅高度');
    });

    testWidgets('TV 浮层标题 16、简介正文 14（默认隐藏）', (tester) async {
      await _pumpDetail(tester, tv: true);
      expect(find.text('这是一段测试简介。'), findsNothing, reason: '简介默认隐藏在海报上');

      await tester.tap(find.text('简介'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final title = tester.widget<Text>(find.text('简介')).style;
      expect(title?.fontSize, 16, reason: 'TV 浮层标题降档');

      final body = tester.widget<Text>(find.text('这是一段测试简介。')).style;
      expect(body?.fontSize, 14, reason: '简介正文保持 14 可读');
    });

    testWidgets('非 TV 浮层标题 18、简介正文 14', (tester) async {
      await _pumpDetail(tester, tv: false);
      await tester.tap(find.text('简介'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final title = tester.widget<Text>(find.text('简介')).style;
      expect(title?.fontSize, 18, reason: '非 TV 浮层标题保持 18');

      final body = tester.widget<Text>(find.text('这是一段测试简介。')).style;
      expect(body?.fontSize, 14, reason: '简介正文保持 14 可读');
    });
  });

  group('海报内简介浮层（v1.1.83 默认隐藏）', () {
    testWidgets('默认隐藏：海报有「简介」控件，正文无简介文字', (tester) async {
      await _pumpDetail(tester);
      expect(find.text('简介'), findsOneWidget, reason: '海报入口控件');
      expect(find.text('这是一段测试简介。'), findsNothing);
    });

    testWidgets('点「简介」展开浮层；点「收起」关闭', (tester) async {
      await _pumpDetail(tester);
      await tester.tap(find.text('简介'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('这是一段测试简介。'), findsOneWidget, reason: '浮层内显示完整简介');
      // 控件切「收起」+ 浮层收起按钮 = 2 个
      expect(find.text('收起'), findsNWidgets(2));

      await tester.tap(find.text('收起').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('这是一段测试简介。'), findsNothing);
      expect(find.text('简介'), findsOneWidget, reason: '回到海报入口');
    });

    testWidgets('点浮层遮罩空白区收起', (tester) async {
      await _pumpDetail(tester);
      await tester.tap(find.text('简介'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 浮层覆盖海报区（pinned SliverAppBar 顶部空白，无控件/文字）
      final size = tester.getSize(find.byType(DetailScreen));
      await tester.tapAt(Offset(size.width / 2, 40));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('这是一段测试简介。'), findsNothing);
    });

    testWidgets('overview 为空：不渲染简介入口', (tester) async {
      final item = MediaItem(
        id: 'm1',
        name: '无简介影片',
        type: 'Movie',
        posterUrl: _posterUrl,
        overview: '',
      );
      await _pumpDetail(tester, item: item);
      expect(find.text('简介'), findsNothing);
      expect(find.text('收起'), findsNothing);
    });

    testWidgets('TV 打开后焦点移入浮层收起按钮', (tester) async {
      await _pumpDetail(tester, tv: true);
      await tester.tap(find.text('简介'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final closeFinder = find.byWidgetPredicate((w) =>
          w is TvFocusable && w.focusNode?.debugLabel == 'overviewClose');
      expect(closeFinder, findsOneWidget);
      expect(_focusWithin(closeFinder), isTrue,
          reason: '遥控器 OK 可直接收起（原入口被浮层遮盖）');
    });
  });

  group('标题艺术字 Logo（hero 替换文字片名，房间模式不加）', () {
    const logoUrl = 'https://emby.test/Items/m1/Images/Logo?tag=L1';
    final movieWithLogo = MediaItem(
      id: 'm1',
      name: '完美世界剧场版',
      type: 'Movie',
      posterUrl: _posterUrl,
      logoUrl: logoUrl,
    );

    Finder logoImage() =>
        find.byWidgetPredicate((w) => w is EmbyImage && w.url == logoUrl);

    testWidgets('有 logo：hero 渲染 Logo 图（替换文字片名位置）', (tester) async {
      await _pumpDetail(tester, item: movieWithLogo);
      expect(logoImage(), findsOneWidget);
    });

    testWidgets('无 logo：不渲染 Logo 图，走文字片名', (tester) async {
      await _pumpDetail(tester, item: _item);
      expect(logoImage(), findsNothing);
      expect(find.text('测试影片'), findsOneWidget);
    });

    testWidgets('roomMode（房间模式）：不渲染 Logo 图', (tester) async {
      await _pumpDetail(tester, item: movieWithLogo, roomMode: true);
      expect(logoImage(), findsNothing);
    });

    testWidgets('开始播放：路由 query 携带 logo（URL 编码）', (tester) async {
      await _pumpDetailInRouter(tester, item: movieWithLogo);

      final btn = find.text('开始播放');
      await tester.ensureVisible(btn);
      await tester.pump();
      await tester.tap(btn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('PLAYER:m1'), findsOneWidget);
      expect(
        find.textContaining('logo=https%3A%2F%2Femby.test'),
        findsOneWidget,
        reason: '播放跳转应携带编码后的 logo URL',
      );
    });
  });

  group('hdImageUrlFor（TV 整页背景按需取图）', () {
    const backdrop =
        'https://e.test/Items/1/Images/Backdrop?maxHeight=400&tag=abc';

    test('大屏目标宽被夹到上限 1280，并追加 quality', () {
      final url = DetailScreen.hdImageUrlFor(backdrop, 1920)!;
      expect(url, contains('maxWidth=1280'));
      expect(url, isNot(contains('maxHeight=400')));
      expect(url, contains('quality=85'));
    });

    test('小目标宽被抬到下限 720', () {
      final url = DetailScreen.hdImageUrlFor(backdrop, 200)!;
      expect(url, contains('maxWidth=720'));
    });

    test('已带 quality 参数不重复追加', () {
      final url = DetailScreen.hdImageUrlFor(
          'https://e.test/Items/1/Images/Backdrop?maxHeight=400&quality=70',
          1000)!;
      expect('quality='.allMatches(url).length, 1);
      expect(url, contains('maxWidth=1000'));
    });

    test('空 URL 返回 null', () {
      expect(DetailScreen.hdImageUrlFor(null, 1000), isNull);
      expect(DetailScreen.hdImageUrlFor('', 1000), isNull);
    });
  });

  group('收藏爱心', () {
    testWidgets('电影页：点爱心收藏→实心、再点取消→空心，调用 setFavorite', (tester) async {
      final fake = FakeEmbyService(item: _item);
      await _pumpDetail(tester, emby: fake);

      final heart = find.byKey(const Key('favoriteButton'));
      expect(heart, findsOneWidget);
      await tester.ensureVisible(heart);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);

      await tester.tap(heart);
      await tester.pump();
      await tester.pump();
      expect(fake.favoriteCalls.last.id, 'm1');
      expect(fake.favoriteCalls.last.favorite, isTrue);
      expect(find.byIcon(Icons.favorite), findsOneWidget);

      await tester.tap(heart);
      await tester.pump();
      await tester.pump();
      expect(fake.favoriteCalls.last.favorite, isFalse);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    });

    testWidgets('收藏失败 → 回滚为空心', (tester) async {
      final fake = FakeEmbyService(item: _item)..favoriteSetResult = false;
      await _pumpDetail(tester, emby: fake);

      final heart = find.byKey(const Key('favoriteButton'));
      await tester.ensureVisible(heart);
      await tester.tap(heart);
      await tester.pump();
      await tester.pump();

      expect(fake.favoriteCalls.single.favorite, isTrue);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsNothing);
    });
  });

  group('标记已观看', () {
    testWidgets('电影页：点对勾→实心、再点→线框，调用 setWatched', (tester) async {
      final fake = FakeEmbyService(item: _item);
      await _pumpDetail(tester, emby: fake);

      final mark = find.byKey(const Key('watchedButton'));
      expect(mark, findsOneWidget);
      await tester.ensureVisible(mark);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

      await tester.tap(mark);
      await tester.pump();
      await tester.pump();
      expect(fake.watchedCalls.last.id, 'm1');
      expect(fake.watchedCalls.last.watched, isTrue);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);

      await tester.tap(mark);
      await tester.pump();
      await tester.pump();
      expect(fake.watchedCalls.last.watched, isFalse);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('标记失败 → 回滚为线框', (tester) async {
      final fake = FakeEmbyService(item: _item)..watchedSetResult = false;
      await _pumpDetail(tester, emby: fake);

      final mark = find.byKey(const Key('watchedButton'));
      await tester.ensureVisible(mark);
      await tester.tap(mark);
      await tester.pump();
      await tester.pump();

      expect(fake.watchedCalls.single.watched, isTrue);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNothing);
    });

    testWidgets('剧集页：标记整部剧 → 调用系列 id 且所有集对勾实心', (tester) async {
      final fake = FakeEmbyService(
        item: series,
        itemsByParent: episodesByParent,
        seasons: seasons,
      );
      await _pumpDetail(tester, item: series, emby: fake);

      final mark = find.byKey(const Key('watchedButton'));
      await tester.ensureVisible(mark);
      await tester.tap(mark);
      await tester.pump();
      await tester.pump();

      expect(fake.watchedCalls.single.id, 'sv1');
      expect(fake.watchedCalls.single.watched, isTrue);
      // 第1季 e1/e2 对勾变实心
      expect(
        find.descendant(
          of: find.byKey(const Key('episodeWatched_e1')),
          matching: find.byIcon(Icons.check_circle),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('episodeWatched_e2')),
          matching: find.byIcon(Icons.check_circle),
        ),
        findsOneWidget,
      );
    });

    testWidgets('剧集页：点某集卡右下角对勾 → 只标记该集', (tester) async {
      // 放大视口：剧集横卡在默认 600 高之外，需可见才能命中触摸控件
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fake = FakeEmbyService(
        item: series,
        itemsByParent: episodesByParent,
        seasons: seasons,
      );
      await _pumpDetail(tester, item: series, emby: fake);

      final e1 = find.byKey(const Key('episodeWatched_e1'));
      expect(e1, findsOneWidget);
      await tester.ensureVisible(e1);
      await tester.tap(e1);
      await tester.pump();
      await tester.pump();

      expect(fake.watchedCalls.last.id, 'e1');
      expect(fake.watchedCalls.last.watched, isTrue);
      // 只动该集，主对勾不受影响（仍线框）
      expect(find.byIcon(Icons.check_circle_outline), findsWidgets);
    });
  });

  group('继续观看', () {
    MediaItem resumeItem() => MediaItem(
          id: 'm1',
          name: '测试影片',
          type: 'Movie',
          posterUrl: _posterUrl,
          overview: '简介。',
          playbackPositionMs: 169000, // 02:49
          playedPercentage: 20,
        );

    testWidgets('有进度：主控件显示「继续 MM:SS」并出现「从头播放」', (tester) async {
      final item = resumeItem();
      await _pumpDetail(tester, item: item, emby: FakeEmbyService(item: item));

      expect(find.text('继续 02:49'), findsOneWidget);
      expect(find.byKey(const Key('playFromBeginningButton')), findsOneWidget);
      expect(find.text('开始播放'), findsNothing);
    });

    testWidgets('无进度：仍为「开始播放」，无「从头播放」', (tester) async {
      await _pumpDetail(tester);

      expect(find.text('开始播放'), findsOneWidget);
      expect(find.byKey(const Key('playFromBeginningButton')), findsNothing);
    });

    testWidgets('标记已观看后：恢复「开始播放」且「从头播放」消失', (tester) async {
      final item = resumeItem();
      final fake = FakeEmbyService(item: item);
      await _pumpDetail(tester, item: item, emby: fake);

      expect(find.text('继续 02:49'), findsOneWidget);

      final mark = find.byKey(const Key('watchedButton'));
      await tester.ensureVisible(mark);
      await tester.tap(mark);
      await tester.pump();
      await tester.pump();

      expect(find.text('开始播放'), findsOneWidget);
      expect(find.textContaining('继续'), findsNothing);
      expect(find.byKey(const Key('playFromBeginningButton')), findsNothing);
    });

    testWidgets('点「继续」：路由携带 startMs', (tester) async {
      final item = resumeItem();
      await _pumpDetailInRouter(tester, item: item);

      final btn = find.text('继续 02:49');
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('startMs=169000'), findsOneWidget);
    });

    testWidgets('点「从头播放」：路由不带 startMs', (tester) async {
      final item = resumeItem();
      await _pumpDetailInRouter(tester, item: item);

      final btn = find.byKey(const Key('playFromBeginningButton'));
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('PLAYER:m1'), findsOneWidget);
      expect(find.textContaining('startMs'), findsNothing);
    });

    testWidgets('返回播放器后 silent 刷新：新进度显示为「继续」', (tester) async {
      final noResume = MediaItem(
        id: 'm1',
        name: '测试影片',
        type: 'Movie',
        posterUrl: _posterUrl,
        overview: '简介。',
      );
      final withResume = MediaItem(
        id: 'm1',
        name: '测试影片',
        type: 'Movie',
        posterUrl: _posterUrl,
        overview: '简介。',
        playbackPositionMs: 169000,
        playedPercentage: 20,
      );
      final fake = _SeqItemFakeService(sequence: [noResume, withResume]);
      final container =
          await _pumpDetailInRouter(tester, item: noResume, emby: fake);

      expect(find.text('开始播放'), findsOneWidget);
      final revBefore = container.read(resumeRevisionProvider);

      // 播放 → 返回（pop 播放器路由）
      final btn = find.text('开始播放');
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('PLAYER:m1'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 600));

      // 静默刷新读到新进度 → 按钮变「继续」且 bump 续播修订号
      expect(find.text('继续 02:49'), findsOneWidget);
      expect(container.read(resumeRevisionProvider), greaterThan(revBefore));
    });

    testWidgets('点「从头播放」：目标立即进入乐观隐藏集合 + bump 修订号', (tester) async {
      final item = resumeItem();
      final container = await _pumpDetailInRouter(tester, item: item);
      final revBefore = container.read(resumeRevisionProvider);

      final btn = find.byKey(const Key('playFromBeginningButton'));
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(container.read(resumeOptimisticHiddenProvider), contains('m1'),
          reason: '点重播应乐观隐藏该条（首页立即移除）');
      expect(container.read(resumeRevisionProvider), greaterThan(revBefore));
      expect(find.textContaining('PLAYER:m1'), findsOneWidget);
    });

    testWidgets('已观看电影点「开始播放」：调用服务器取消已观看', (tester) async {
      final watched = MediaItem(
        id: 'm1',
        name: '测试影片',
        type: 'Movie',
        posterUrl: _posterUrl,
        overview: '简介。',
        isWatched: true,
      );
      final fake = FakeEmbyService(item: watched);
      await _pumpDetailInRouter(tester, item: watched, emby: fake);

      final btn = find.text('开始播放');
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        fake.watchedCalls.any((c) => c.id == 'm1' && c.watched == false),
        isTrue,
        reason: '重播已观看电影应调用服务器取消已观看（重回续播列表）',
      );
    });

    testWidgets('已观看电影点播放后返回：有进度则显示「继续 + 从头播放」', (tester) async {
      final watched = MediaItem(
        id: 'm1',
        name: '测试影片',
        type: 'Movie',
        posterUrl: _posterUrl,
        overview: '简介。',
        isWatched: true,
      );
      final withResume = MediaItem(
        id: 'm1',
        name: '测试影片',
        type: 'Movie',
        posterUrl: _posterUrl,
        overview: '简介。',
        playbackPositionMs: 169000,
        playedPercentage: 20,
      );
      final fake = _SeqItemFakeService(sequence: [watched, withResume]);
      await _pumpDetailInRouter(tester, item: watched, emby: fake);

      expect(find.text('开始播放'), findsOneWidget);

      final btn = find.text('开始播放');
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('PLAYER:m1'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('继续 02:49'), findsOneWidget);
      expect(find.byKey(const Key('playFromBeginningButton')), findsOneWidget);
    });

    testWidgets('整部已观看的剧集：目标集有进度仍显示「继续」（按集判断，不被整部卡住）',
        (tester) async {
      final series = MediaItem(
        id: 'sv1',
        name: '测试剧集',
        type: 'Series',
        isWatched: true,
      );
      final ep1 = MediaItem(
        id: 'e1',
        name: '第1集',
        type: 'Episode',
        parentIndexNumber: 1,
        indexNumber: 1,
        playbackPositionMs: 169000,
        playedPercentage: 20,
      );
      final fake = FakeEmbyService(item: series, items: [ep1]);
      await _pumpDetail(tester, item: series, emby: fake);

      expect(find.text('继续 02:49'), findsOneWidget,
          reason: '续播门槛应按目标集判断，而非整部剧的已观看');
      expect(find.byKey(const Key('playFromBeginningButton')), findsOneWidget);
    });
  });

  group('底部媒体信息（非 TV）', () {
    MediaItem infoItem() => MediaItem(
          id: 'm1',
          name: '测试影片',
          type: 'Movie',
          posterUrl: _posterUrl,
          overview: '简介。',
          path: '/media/x.mkv',
          studios: const ['Netflix'],
          providerIds: const {'Imdb': 'tt1'},
          mediaStreams: [
            MediaStream(
              type: 'Video',
              codec: 'hevc',
              width: 1920,
              height: 1080,
              profile: 'Main 10',
              bitDepth: 10,
              pixelFormat: 'yuv420p10le',
              frameRate: 23.976025,
            ),
            MediaStream(type: 'Audio', codec: 'eac3', channels: 2),
          ],
        );

    testWidgets('非 TV 渲染外部链接/工作室/媒体信息', (tester) async {
      final item = infoItem();
      await _pumpDetail(tester, item: item, emby: FakeEmbyService(item: item));

      expect(find.text('外部链接'), findsOneWidget);
      expect(find.text('工作室'), findsOneWidget);
      expect(find.text('媒体信息'), findsOneWidget);
      expect(find.text('Netflix'), findsOneWidget);
    });

    testWidgets('TV 模式不渲染底部媒体信息', (tester) async {
      final item = infoItem();
      await _pumpDetail(tester,
          tv: true, item: item, emby: FakeEmbyService(item: item));

      expect(find.text('外部链接'), findsNothing);
      expect(find.text('工作室'), findsNothing);
      expect(find.text('媒体信息'), findsNothing);
    });

    testWidgets('剧集页：媒体信息/视频音频取「当前选中集」', (tester) async {
      final seriesItem = MediaItem(id: 'sv1', name: '测试剧集', type: 'Series');
      final ep1 = MediaItem(
        id: 'e1',
        name: '第1集',
        type: 'Episode',
        parentIndexNumber: 1,
        indexNumber: 1,
        path: '/media/e1.mkv',
        mediaStreams: [
          MediaStream(type: 'Video', codec: 'hevc', width: 1920, height: 1080),
          MediaStream(type: 'Audio', codec: 'eac3', channels: 2),
        ],
      );
      await _pumpDetail(
        tester,
        item: seriesItem,
        emby: FakeEmbyService(
          item: seriesItem,
          itemsByParent: {
            'sv1': [ep1],
          },
          seasons: [
            MediaItem(
                id: 'sea1',
                name: '第1季',
                type: 'Season',
                indexNumber: 1,
                childCount: 1),
          ],
        ),
      );

      // 剧集本身无流，面板来自当前选中集
      expect(find.text('媒体信息'), findsOneWidget);
      expect(find.text('视频'), findsWidgets);
      expect(find.text('音频'), findsWidgets);
    });
  });
}

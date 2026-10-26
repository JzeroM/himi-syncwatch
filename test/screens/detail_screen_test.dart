import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/agora_config_model.dart';
import 'package:himi_syncwatch/models/emby_playback_settings.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/agora_provider.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/media_state_override_provider.dart';
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
  bool tv = false,
  List<Override> extraOverrides = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      settingsProvider
          .overrideWith((ref) => FakeSettingsNotifier(AppSettings(tvMode: tv))),
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

/// 弹层行是否为选中态（共享居中弹层：选中行内含对勾图标；替代旧
/// RadioGroup.groupValue 读取——RadioGroup 的方向键 Shortcut 会劫持
/// TV 导航，v1.1.176 起弹层统一为 showTvOptionDialog）。
bool _optionSelectedInDialog(WidgetTester tester, Key optionKey) {
  return find
      .descendant(
        of: find.byKey(optionKey),
        matching: find.byType(Icon),
      )
      .evaluate()
      .isNotEmpty;
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

  testWidgets('详情页返回键玻璃壳无悬浮投影（showShadow: false）', (tester) async {
    await _pumpDetail(tester);

    final backCapsule = find.ancestor(
      of: find.byIcon(Icons.arrow_back),
      matching: find.byType(GlassContainer),
    );
    expect(backCapsule, findsOneWidget,
        reason: 'SliverAppBar leading 应为玻璃壳返回键');
    expect(tester.widget<GlassContainer>(backCapsule).showShadow, isFalse,
        reason: '贴边小按钮不用面板级投影，避免返回键外一圈黑影');
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

    testWidgets('剧集横卡：鼠标悬停显示右翻页箭头（桌面可滚动）', (tester) async {
      tester.view.physicalSize = const Size(500, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final many = [
        for (var i = 1; i <= 10; i++) ep('m$i', season: 1, number: i),
      ];
      await _pumpDetail(
        tester,
        item: series,
        emby: FakeEmbyService(
          item: series,
          itemsByParent: {'sv1': many},
          seasons: seasons,
        ),
      );

      final card = find.byKey(const Key('episodeCard_m1'));
      await tester.ensureVisible(card);
      await tester.pump();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(card));
      await tester.pump();

      expect(find.byKey(const ValueKey('scrollArrowRight')), findsOneWidget,
          reason: '剧集横卡溢出且悬停应显示右翻页箭头');
      expect(find.byKey(const ValueKey('scrollArrowLeft')), findsNothing,
          reason: '在最左只显示右箭头');
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

    testWidgets('TV 选季走居中弹层（showMenu disabled 容器焦点判死回归，v1.1.177）',
        (tester) async {
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

      final selector = find.byKey(const Key('seriesSeasonSelector'));
      await tester.ensureVisible(selector);
      await tester.pump();
      await tester.tap(selector);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // 居中 AlertDialog 弹层（非 showMenu 的 PopupMenuItem 菜单）
      expect(find.text('选择季'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byKey(const Key('seasonOption_1')), findsOneWidget);
      expect(find.byKey(const Key('seasonOption_2')), findsOneWidget);
      expect(find.byType(PopupMenuItem<int>), findsNothing);

      await tester.tap(find.byKey(const Key('seasonOption_2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byKey(const Key('episodeCard_e3')), findsOneWidget);
      expect(find.byKey(const Key('episodeCard_e1')), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
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
      bitrate: 2000000,
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
      bitrate: 8000000,
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

    /// 点「可用版本」栏某版本行（非 TV）：即选中并刷新详情（不进播放器）。
    Future<void> pickVersion(WidgetTester t, String sourceId) async {
      final row = find.byKey(Key('mediaSource_$sourceId'));
      await t.ensureVisible(row);
      await t.pump();
      await t.tap(row);
      await t.pump();
    }

    testWidgets('单版本资源隐藏版本图标', (tester) async {
      await _pumpDetail(tester);
      expect(find.byKey(const Key('versionSelectorButton')), findsNothing);
    });

    testWidgets('多版本：无版本图标；可用版本按偏好（高码率）排序且默认高亮优选', (tester) async {
      await pumpMulti(tester);
      expect(find.byKey(const Key('versionSelectorButton')), findsNothing);
      expect(find.text('可用版本'), findsOneWidget);
      // 默认偏好「高码率优先」→ src2(8M) 在 src1(2M) 之前
      expect(
        tester.getRect(find.byKey(const Key('mediaSource_src2'))).top,
        lessThan(tester.getRect(find.byKey(const Key('mediaSource_src1'))).top),
      );
      // 未选之前默认高亮偏好最高（src2）
      expect(
        find.descendant(
          of: find.byKey(const Key('mediaSource_src2')),
          matching: find.byIcon(Icons.check_circle),
        ),
        findsOneWidget,
      );
    });

    testWidgets('「可用版本」区块：TV 与非 TV 均渲染，行可点击切换（不再弹选择器）', (tester) async {
      // TV：也渲染（版本入口从播放控件移入此栏）
      await pumpMulti(tester, tv: true);
      expect(find.text('可用版本'), findsOneWidget);
      expect(find.text('1080p版'), findsWidgets);
      expect(find.text('4K版'), findsWidgets);

      // 非 TV：区块存在（标题 + 每源一行），行可点选
      await pumpMulti(tester);
      expect(find.text('可用版本'), findsOneWidget);
      expect(
        tester
            .widget<ListTile>(find.byKey(const Key('mediaSource_src1')))
            .onTap,
        isNotNull,
        reason: '可用版本栏行可点击切换（v1.2.22 起去两步弹层）',
      );
      expect(
        tester
            .widget<ListTile>(find.byKey(const Key('mediaSource_src2')))
            .onTap,
        isNotNull,
      );
    });

    testWidgets('点可用版本行选中该版本并高亮（不再弹版本选择器）', (tester) async {
      await pumpMulti(tester);

      // 点开始播放不再弹选择器，直接进播放器
      expect(find.text('选择版本'), findsNothing);

      // 默认高亮偏好最高 src2；点 src1 行 → 高亮切到 src1
      await tester.ensureVisible(find.byKey(const Key('mediaSource_src1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('mediaSource_src1')));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byKey(const Key('mediaSource_src1')),
          matching: find.byIcon(Icons.check_circle),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('mediaSource_src2')),
          matching: find.byIcon(Icons.check_circle),
        ),
        findsNothing,
      );
    });

    testWidgets('未选版本时字幕/音轨列表跟随偏好最高版本；点选后跟随所选', (tester) async {
      await pumpMulti(tester);

      // 默认 = 偏好最高 src2（高码率 8M）：字幕仅 jpn(5)；音轨仅 1 条 → 图标隐藏
      await openSheet(tester, const Key('subtitleSelectorButton'));
      expect(find.byKey(const Key('trackOption_5')), findsOneWidget);
      expect(find.byKey(const Key('trackOption_3')), findsNothing);
      expect(find.byKey(const Key('trackOption_4')), findsNothing);
      await closeSheet(tester);
      expect(find.byKey(const Key('audioSelectorButton')), findsNothing,
          reason: 'src2 仅一条音轨 → 音轨图标按规则隐藏');

      // 两步流程切 src1：字幕 3/4（无 5），音轨图标回归（2 条）
      await pickVersion(tester, 'src1');

      await openSheet(tester, const Key('subtitleSelectorButton'));
      expect(find.byKey(const Key('trackOption_3')), findsOneWidget);
      expect(find.byKey(const Key('trackOption_4')), findsOneWidget);
      expect(find.byKey(const Key('trackOption_5')), findsNothing);
      await closeSheet(tester);
      expect(find.byKey(const Key('audioSelectorButton')), findsOneWidget);
    });

    // 自建多版本条目：版本偏好下 [hi]（高码率）是默认/生效版本，[lo] 需两步流程切换。
    MediaItem multiItem(String id, MediaSource hi, MediaSource lo) => MediaItem(
          id: id,
          name: '偏好联动',
          type: 'Movie',
          posterUrl: _posterUrl,
          mediaStreams: [...hi.mediaStreams],
          mediaSources: [lo, hi], // 服务端顺序与偏好顺序相反，验证按偏好取
        );

    testWidgets('切版本预选按语言迁移：字幕 + 音轨都迁到新版本的同语言轨', (tester) async {
      // 默认 = mv1_hi（8M）：字幕 jpn(4)/chi(3)，音轨 chi(0)/eng(1)
      final hi = MediaSource(
        id: 'mv1_hi',
        name: '高码率',
        bitrate: 8000000,
        mediaStreams: [
          MediaStream(type: 'Audio', codec: 'aac', language: 'chi', index: 0),
          MediaStream(type: 'Audio', codec: 'eac3', language: 'eng', index: 1),
          MediaStream(
              type: 'Subtitle', codec: 'srt', language: 'jpn', index: 4),
        ],
      );
      // 两步切换目标 mv1_lo（2M）：字幕 jpn(5)，音轨 eng(2)
      final lo = MediaSource(
        id: 'mv1_lo',
        name: '低码率',
        bitrate: 2000000,
        mediaStreams: [
          MediaStream(type: 'Audio', codec: 'ac3', language: 'eng', index: 2),
          MediaStream(
              type: 'Subtitle', codec: 'ass', language: 'jpn', index: 5),
        ],
      );
      final item = multiItem('mv_migrate', hi, lo);
      final container = await _pumpDetail(tester,
          item: item, emby: FakeEmbyService(item: item));

      // 默认在 hi 上预选：字幕 jpn(4)、音轨 eng(1)
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

      // 两步流程切 lo：jpn 字幕 4→5；eng 音轨 1→2
      await pickVersion(tester, 'mv1_lo');

      final after = container.read(pendingTrackSelectionProvider);
      expect(after?.subtitleIndex, 5, reason: 'jpn 字幕迁移到新版本的 index');
      expect(after?.audioIndex, 2, reason: 'eng 音轨迁移到新版本的 index');
    });

    testWidgets('切版本后无同语言轨则清空该轨预选', (tester) async {
      // 默认 = mv2_hi（8M）：音轨 chi(0)/eng(1)；目标无 chi
      final hi = MediaSource(
        id: 'mv2_hi',
        name: '高码率',
        bitrate: 8000000,
        mediaStreams: [
          MediaStream(type: 'Audio', codec: 'aac', language: 'chi', index: 0),
          MediaStream(type: 'Audio', codec: 'eac3', language: 'eng', index: 1),
        ],
      );
      final lo = MediaSource(
        id: 'mv2_lo',
        name: '低码率',
        bitrate: 2000000,
        mediaStreams: [
          MediaStream(type: 'Audio', codec: 'ac3', language: 'eng', index: 2),
          MediaStream(type: 'Audio', codec: 'ac3', language: 'fra', index: 3),
        ],
      );
      final item = multiItem('mv_clear', hi, lo);
      final container = await _pumpDetail(tester,
          item: item, emby: FakeEmbyService(item: item));

      // 默认 = hi：预选音轨 chi(0)
      await openSheet(tester, const Key('audioSelectorButton'));
      await tester.tap(find.byKey(const Key('trackOption_0')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(container.read(pendingTrackSelectionProvider)?.audioIndex, 0);

      // 两步流程切 lo：无 chi 音轨 → 该轨预选清空
      await pickVersion(tester, 'mv2_lo');
      expect(container.read(pendingTrackSelectionProvider)?.audioIndex, isNull,
          reason: '新版本无 chi 音轨 → 清空');
    });

    testWidgets('未选版本时底部媒体信息跟随偏好最高版本；点选后跟随所选（v1.1.177/v1.1.233）',
        (tester) async {
      final a = MediaSource(
        id: 'va',
        name: '1080p版',
        bitrate: 2000000,
        path: '/media/a/video.mkv',
        size: 1073741824, // 1.00 G
        mediaStreams: [
          MediaStream(type: 'Video', codec: 'h264', width: 1920, height: 1080),
          MediaStream(type: 'Audio', codec: 'aac', language: 'chi', index: 1),
        ],
      );
      final b = MediaSource(
        id: 'vb',
        name: '4K版',
        bitrate: 8000000,
        path: '/media/b/video.mkv',
        size: 2147483648, // 2.00 G
        mediaStreams: [
          MediaStream(type: 'Video', codec: 'hevc', width: 3840, height: 2160),
          MediaStream(type: 'Audio', codec: 'eac3', language: 'eng', index: 1),
        ],
      );
      final item = MediaItem(
        id: 'mv_info',
        name: '媒体信息联动',
        type: 'Movie',
        posterUrl: _posterUrl,
        // 顶层流 = va 的流集（与偏好最高的 vb 不同，用于验证跟随）
        mediaStreams: [...a.mediaStreams],
        mediaSources: [a, b],
      );
      await _pumpDetail(tester, item: item, emby: FakeEmbyService(item: item));

      // 未选版本：默认 = 偏好最高 vb（高码率 8M）→ 流/路径/大小都是 b
      expect(find.text('hevc'), findsOneWidget, reason: '默认视频编解码 = 偏好最高版本');
      expect(find.textContaining('/media/b/video.mkv'), findsOneWidget,
          reason: '默认路径 = 偏好最高版本');
      expect(find.text('2.00 G'), findsWidgets, reason: '默认大小 = 偏好最高版本');

      // 两步流程切到 va：流/路径/大小全部跟随
      await pickVersion(tester, 'va');

      expect(find.text('h264'), findsOneWidget, reason: '新版本视频编解码');
      expect(find.text('hevc'), findsNothing);
      expect(find.textContaining('/media/a/video.mkv'), findsOneWidget,
          reason: '新版本路径');
      expect(find.text('1.00 G'), findsWidgets, reason: '新版本大小（头部 + 媒体信息卡）');
    });

    testWidgets('TV：可用版本栏行由 TvFocusable 包裹（焦点移入即选中），OK=用该版本直接播放',
        (tester) async {
      await _pumpDetailInRouter(
        tester,
        item: multi,
        tv: true,
        emby: FakeEmbyService(item: multi),
      );

      final row = find.byKey(const Key('mediaSource_src1'));
      await tester.ensureVisible(row);
      await tester.pump();
      final focusable = tester.widget<TvFocusable>(
        find.ancestor(of: row, matching: find.byType(TvFocusable)),
      );
      expect(focusable.onFocusChange, isNotNull, reason: '焦点移入即选中该版本');
      expect(focusable.onTap, isNotNull, reason: 'OK 用该版本直接播放');
      // v1.2.24：行序 ↑/↓ 确定性导航接线（修复「下移后按 ↓ 焦点上移」）
      expect(focusable.focusNode, isNotNull, reason: '版本行接稳定焦点节点');
      expect(focusable.onKeyEvent, isNotNull, reason: '版本行接行序按键处理');

      final row2Focusable = tester.widget<TvFocusable>(
        find.ancestor(
          of: find.byKey(const Key('mediaSource_src2')),
          matching: find.byType(TvFocusable),
        ),
      );
      expect(
        identical(focusable.focusNode, row2Focusable.focusNode),
        isFalse,
        reason: '不同版本行使用不同节点',
      );

      // 重建（焦点移入触发选中 setState）后节点实例保持稳定，焦点不丢
      row2Focusable.focusNode!.requestFocus();
      await tester.pump();
      expect(row2Focusable.focusNode!.hasFocus, isTrue);
      final afterRebuild = tester.widget<TvFocusable>(
        find.ancestor(
          of: find.byKey(const Key('mediaSource_src2')),
          matching: find.byType(TvFocusable),
        ),
      );
      expect(identical(afterRebuild.focusNode, row2Focusable.focusNode), isTrue,
          reason: '重建复用同一节点，焦点不丢');

      // OK（点击）→ 用该版本直接进入播放器
      await tester.tap(row);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('PLAYER:mv1'), findsOneWidget);
      expect(find.textContaining('mediaSourceId=src1'), findsOneWidget);
    });
  });

  // ---- 顶部附加信息行（评分/年份/时长/分辨率/视频范围/大小） ----

  testWidgets('顶部附加信息行：评分/年份/时长/分辨率/视频范围/大小（已移除官方分级）', (tester) async {
    final item = MediaItem(
      id: 'm1',
      name: '测试影片',
      type: 'Movie',
      posterUrl: _posterUrl,
      officialRating: 'TV-MA',
      communityRating: 6.2,
      year: '2026',
      runTimeTicks: 36000000000, // 1 h 0m
      mediaStreams: [
        MediaStream(
            type: 'Video',
            codec: 'hevc',
            width: 3840,
            height: 2160,
            videoRangeType: 'HDR10'),
      ],
      mediaSources: [
        MediaSource(
          id: 's1',
          name: '4K版',
          size: 1073741824, // 1.00 G
        ),
      ],
    );
    await _pumpDetail(tester, item: item, emby: FakeEmbyService(item: item));

    expect(find.text('6.2'), findsOneWidget, reason: '评分');
    expect(find.text('2026'), findsOneWidget, reason: '年份');
    expect(find.text('1 h 0m'), findsOneWidget, reason: '时长');
    expect(find.text('4K'), findsOneWidget, reason: '分辨率简称');
    expect(find.text('HDR10'), findsWidgets, reason: '视频范围（头部徽章 + 媒体信息卡）');
    expect(find.text('1.00 G'), findsWidgets, reason: '视频大小（头部 + 媒体信息卡）');
    expect(find.text('TV-MA'), findsNothing, reason: '官方分级已从附加信息行移除');
  });

  testWidgets('顶部附加信息：杜比视界缩写为 DV P5，防过长', (tester) async {
    final item = MediaItem(
      id: 'dv1',
      name: 'DV影片',
      type: 'Movie',
      posterUrl: _posterUrl,
      mediaStreams: [
        MediaStream(
          type: 'Video',
          codec: 'hevc',
          width: 3840,
          height: 2160,
          extendedVideoType: 'DolbyVision',
          extendedVideoSubType: 'DoviProfile50',
        ),
      ],
    );
    await _pumpDetail(tester, item: item, emby: FakeEmbyService(item: item));

    expect(find.text('DV P5'), findsOneWidget);
  });

  testWidgets('剧集顶部附加信息：分辨率/范围/大小取当前选中集', (tester) async {
    final seriesItem = MediaItem(
      id: 'sv1',
      name: '测试剧集',
      type: 'Series',
      communityRating: 8.0,
      year: '2020',
    );
    final ep1 = MediaItem(
      id: 'e1',
      name: '第1集',
      type: 'Episode',
      parentIndexNumber: 1,
      indexNumber: 1,
      mediaStreams: [
        MediaStream(
            type: 'Video',
            codec: 'hevc',
            width: 3840,
            height: 2160,
            videoRangeType: 'HDR10'),
      ],
      mediaSources: [
        MediaSource(id: 'es1', name: '4K', size: 2147483648), // 2.00 G
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

    expect(find.text('8.0'), findsWidgets, reason: '剧集评分');
    expect(find.text('2020'), findsOneWidget, reason: '剧集年份');
    expect(find.text('4K'), findsWidgets, reason: '选中集分辨率简称');
    expect(find.text('HDR10'), findsWidgets, reason: '选中集视频范围');
    expect(find.text('2.00 G'), findsWidgets, reason: '选中集视频大小');
  });

  testWidgets('类型标签行居中（Center 包裹 Wrap）', (tester) async {
    final item = MediaItem(
      id: 'm1',
      name: '测试影片',
      type: 'Movie',
      posterUrl: _posterUrl,
      genres: const ['动画', '冒险', '剧情'],
    );
    await _pumpDetail(tester, item: item, emby: FakeEmbyService(item: item));

    final center = find.byKey(const ValueKey('genreRow'));
    expect(center, findsOneWidget);
    expect(tester.widget(center), isA<Center>());
    expect(
      find.descendant(of: center, matching: find.byType(Wrap)),
      findsOneWidget,
      reason: '居中包裹的就是类型标签 Wrap',
    );
    expect(find.text('动画'), findsOneWidget);
    expect(find.text('剧情'), findsOneWidget);
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
      expect(
          _optionSelectedInDialog(tester, const Key('trackOption_7')), isFalse,
          reason: 'e2 尚未预选');
      await tester.tap(find.byKey(const Key('trackOption_7')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(container.read(pendingTrackSelectionProvider), isNull);

      // 切回 e1 → 打开音轨 sheet，高亮仍是 e1 自己的 index 1
      await tapCard(tester, 'p1');
      await openAudioSheet(tester);
      expect(
        _optionSelectedInDialog(tester, const Key('trackOption_1')),
        isTrue,
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
        _optionSelectedInDialog(tester, const Key('trackOption_7')),
        isTrue,
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
      // 顶层流 = 版本A 的轨集（与偏好最高的版本B 不同，用于验证跟随）
      mediaStreams: [audio(0, 'chi'), audio(1, 'eng'), sub(3, 'chi')],
      mediaSources: [
        MediaSource(
          id: 'sv_a',
          name: '版本A',
          width: 1920,
          bitrate: 2000000,
          mediaStreams: [audio(0, 'chi'), audio(1, 'eng'), sub(3, 'chi')],
        ),
        MediaSource(
          id: 'sv_b',
          name: '版本B',
          width: 3840,
          bitrate: 8000000,
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

    testWidgets('多版本集：默认跟随偏好最高版本；点可用版本栏切版本 A 后播放带该集选中版本', (tester) async {
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

      // 无版本图标（v1.1.232 起）
      expect(find.byKey(const Key('versionSelectorButton')), findsNothing);

      // 未选版本：音轨列表默认 = 偏好最高版本B（7/8，无 0/1）
      Future<void> showAudioList() async {
        final btn = find.byKey(const Key('audioSelectorButton'));
        await tester.ensureVisible(btn);
        await tester.pump();
        await tester.tap(btn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
      }

      Future<void> closeAudioList() async {
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
      }

      await showAudioList();
      expect(find.byKey(const Key('trackOption_7')), findsOneWidget,
          reason: '默认音轨列表 = 偏好最高版本B');
      expect(find.byKey(const Key('trackOption_8')), findsOneWidget);
      expect(find.byKey(const Key('trackOption_0')), findsNothing);
      await closeAudioList();

      // 剧集「可用版本」栏在剧集横卡下方：点版本 A 行 → 刷新详情
      expect(find.byKey(const Key('versionOption_sv_a')), findsNothing,
          reason: '不再弹版本选择器');
      final rowA = find.byKey(const Key('mediaSource_sv_a'));
      // 位置：剧集横卡与「播出季」之间
      final versionTop = tester.getTopLeft(rowA).dy;
      expect(
        versionTop,
        greaterThan(
            tester.getTopLeft(find.byKey(const Key('episodeCard_mv1'))).dy),
        reason: '可用版本栏在剧集横卡下方',
      );
      expect(
        versionTop,
        lessThan(tester.getTopLeft(find.text('播出季')).dy),
        reason: '可用版本栏在播出季上方',
      );
      await tester.ensureVisible(rowA);
      await tester.pump();
      await tester.tap(rowA);
      await tester.pump();

      await showAudioList();
      expect(find.byKey(const Key('trackOption_0')), findsOneWidget,
          reason: '音轨列表已切换为版本 A 的轨');
      expect(find.byKey(const Key('trackOption_7')), findsNothing);
      await tester.tap(find.byKey(const Key('trackOption_0')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      // 选项点击会自行关闭弹层，无需再 pop

      // 再次点开始播放 → 进播放器（带该集选中版本）
      await tapStartPlay(tester);

      expect(find.textContaining('PLAYER:mv1'), findsOneWidget);
      expect(
        find.textContaining('mediaSourceId=sv_a'),
        findsOneWidget,
        reason: '播放跳转带该集选中版本',
      );
      // 该集预选在播放时写入全局槽供播放器消费
      final selection = container.read(pendingTrackSelectionProvider);
      expect(selection, isNotNull);
      expect(selection?.audioIndex, 0);
    });

    testWidgets('TV：剧集横卡 OK 打开三项操作面板，不直接播放', (tester) async {
      await _pumpDetailInRouter(
        tester,
        item: seriesMv,
        tv: true,
        emby: FakeEmbyService(
          item: seriesMv,
          itemsByParent: {
            'sv10': [epPlain],
          },
          seasons: seasonsMv,
        ),
      );

      final card = find.byKey(const Key('episodeCard_pl1'));
      await tester.ensureVisible(card);
      await tester.pump();
      final focusable = tester.widget<TvFocusable>(
        find.ancestor(of: card, matching: find.byType(TvFocusable)).first,
      );
      expect(focusable.onFocusChange, isNotNull, reason: '焦点移入即选中该集');
      expect(focusable.onTap, isNotNull, reason: 'OK 打开操作面板');

      await tester.tap(card);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('PLAYER:pl1'), findsNothing,
          reason: 'OK 不再直接进播放器');
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byKey(const Key('episodeActionPlay_pl1')), findsOneWidget);
      expect(
          find.byKey(const Key('episodeActionFavorite_pl1')), findsOneWidget);
      expect(find.byKey(const Key('episodeActionWatched_pl1')), findsOneWidget);
      expect(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.text('播放')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.text('收藏')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.text('标记已观看')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('episodeActionPlay_pl1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('PLAYER:pl1'), findsOneWidget);
    });

    testWidgets('TV：操作面板收藏/已观看切换保持打开并联动卡片状态', (tester) async {
      final fake = FakeEmbyService(
        item: seriesMv,
        itemsByParent: {
          'sv10': [epPlain],
        },
        seasons: seasonsMv,
      );
      await _pumpDetailInRouter(
        tester,
        item: seriesMv,
        tv: true,
        emby: fake,
      );

      final card = find.byKey(const Key('episodeCard_pl1'));
      await tester.ensureVisible(card);
      await tester.pump();
      await tester.tap(card);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final favRow = find.byKey(const Key('episodeActionFavorite_pl1'));
      await tester.tap(favRow);
      await tester.pump();
      await tester.pump();
      expect(fake.favoriteCalls.single, (id: 'pl1', favorite: true));
      expect(find.byType(AlertDialog), findsOneWidget, reason: '收藏切换后面板保持打开');
      expect(find.text('取消收藏'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('episodeFavorite_pl1')),
          matching: find.byIcon(Icons.favorite),
        ),
        findsOneWidget,
        reason: '卡片收藏角标同步实心',
      );

      final watchedRow = find.byKey(const Key('episodeActionWatched_pl1'));
      await tester.tap(watchedRow);
      await tester.pump();
      await tester.pump();
      expect(fake.watchedCalls.single, (id: 'pl1', watched: true));
      expect(find.byType(AlertDialog), findsOneWidget, reason: '已观看切换后面板保持打开');
      expect(find.text('取消已观看'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('episodeWatched_pl1')),
          matching: find.byIcon(Icons.check_circle),
        ),
        findsOneWidget,
        reason: '卡片已观看角标同步实心',
      );
    });

    testWidgets('TV：有进度的集显示「继续播放」并携带 startMs', (tester) async {
      final resumeEp = MediaItem(
        id: 'plresume',
        name: '可续播集',
        type: 'Episode',
        parentIndexNumber: 1,
        indexNumber: 2,
        posterUrl: _posterUrl,
        playbackPositionMs: 60000,
        playedPercentage: 20,
        runTimeTicks: 3000000000,
      );
      await _pumpDetailInRouter(
        tester,
        item: seriesMv,
        tv: true,
        emby: FakeEmbyService(
          item: seriesMv,
          itemsByParent: {
            'sv10': [resumeEp],
          },
          seasons: seasonsMv,
        ),
      );

      final card = find.byKey(const Key('episodeCard_plresume'));
      await tester.ensureVisible(card);
      await tester.pump();
      await tester.tap(card);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('继续播放'), findsOneWidget);
      expect(find.text('从上次观看进度继续'), findsOneWidget);

      await tester.tap(find.byKey(const Key('episodeActionPlay_plresume')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('PLAYER:plresume'), findsOneWidget);
      expect(find.textContaining('startMs=60000'), findsOneWidget);
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
            id: 'a2',
            name: '版本A',
            width: 1920,
            bitrate: 2000000,
            mediaStreams: [audio(0)]),
        MediaSource(
            id: 'b2',
            name: '版本B',
            width: 3840,
            bitrate: 8000000,
            mediaStreams: [audio(1)]),
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

    testWidgets('未手动选版本的多版本集：面板默认填偏好最高版本并随 episodesJson 下发', (tester) async {
      final container = await pumpRoomDetail(tester);
      await openEpisodePicker(tester);

      // 偏好最高 = 版本B（高码率）→ 行尾标签默认显示它，而非「默认」
      expect(find.text('版本: 版本B'), findsOneWidget);

      // 不改版本，直接确认建房 → 该集下发偏好最高版本
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

      final pending = container.read(pendingRoomEpisodesProvider);
      expect(pending, isNotNull);
      expect(pending!, hasLength(2));
      expect(pending.first['id'], 'eA');
      expect(pending.first['mediaSourceId'], 'b2',
          reason: '建房默认源 = 版本偏好最高（与详情页一致）');
      expect(pending.last['id'], 'eB');
      expect(pending.last.containsKey('mediaSourceId'), isFalse,
          reason: '单版本集不下发 mediaSourceId');
    });

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
        _optionSelectedInDialog(tester, const Key('epVersion_eA_b2')),
        isTrue,
        reason: '重开弹窗时回填当前单选',
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

  group('跨页乐观覆盖（详情页操作后其他页弹窗联动）', () {
    testWidgets('电影收藏/已看成功后写入覆盖', (tester) async {
      final fake = FakeEmbyService(item: _item);
      final container = await _pumpDetail(tester, emby: fake);

      final heart = find.byKey(const Key('favoriteButton'));
      await tester.ensureVisible(heart);
      await tester.tap(heart);
      await tester.pump();
      await tester.pump();
      expect(
        container.read(mediaStateOverrideProvider)['m1']?.favorite,
        isTrue,
      );

      final mark = find.byKey(const Key('watchedButton'));
      await tester.ensureVisible(mark);
      await tester.tap(mark);
      await tester.pump();
      await tester.pump();
      expect(
        container.read(mediaStateOverrideProvider)['m1']?.watched,
        isTrue,
      );
    });

    testWidgets('剧集整部已看写入主条目和所有集覆盖', (tester) async {
      final fake = FakeEmbyService(
        item: series,
        itemsByParent: episodesByParent,
        seasons: seasons,
      );
      final container = await _pumpDetail(
        tester,
        item: series,
        emby: fake,
      );

      final mark = find.byKey(const Key('watchedButton'));
      await tester.ensureVisible(mark);
      await tester.tap(mark);
      await tester.pump();
      await tester.pump();

      final overrides = container.read(mediaStateOverrideProvider);
      expect(overrides['sv1']?.watched, isTrue);
      expect(overrides['e1']?.watched, isTrue);
      expect(overrides['e2']?.watched, isTrue);
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

    testWidgets('继续按钮铺满半行、整块可点（点右侧也触发，图标文字居中）', (tester) async {
      final item = resumeItem();
      await _pumpDetailInRouter(tester, item: item);

      final btn = find.ancestor(
        of: find.text('继续 02:49'),
        matching: find.byType(FilledButton),
      );
      expect(btn, findsOneWidget);
      await tester.ensureVisible(btn);

      final rect = tester.getRect(btn);
      expect(rect.width, greaterThan(340),
          reason: '续播按钮应铺满半行（此前 Stack loose 只占内容固有宽、贴左上）');

      // 进度填充自带与胶囊一致的左圆角（iOS 溢出修复）：存在 topLeft 圆角、
      // topRight 直角的 ClipRRect。
      final progressClip =
          tester.widgetList<ClipRRect>(find.byType(ClipRRect)).any((c) {
        final br = c.borderRadius;
        return br is BorderRadius &&
            br.topLeft != Radius.zero &&
            br.topRight == Radius.zero;
      });
      expect(progressClip, isTrue, reason: '进度填充需左侧圆角裁剪，避免直角戳出胶囊（iOS）');

      // 点按钮右缘附近：修复前该区域不可点（只有左侧内容块命中）
      await tester.tapAt(Offset(rect.right - 12, rect.center.dy));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('startMs=169000'), findsOneWidget,
          reason: '整块按钮都应可点');
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

    testWidgets('整部已观看的剧集：目标集有进度仍显示「继续」（按集判断，不被整部卡住）', (tester) async {
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

  group('剧集页默认锁定集（defaultEpisodeTarget）', () {
    MediaItem ep(
      String id,
      int season,
      int num, {
      int ms = 0,
      double pct = 0,
      int? runtimeTicks = 3000000000,
      bool watched = false,
    }) =>
        MediaItem(
          id: id,
          name: '第$num集',
          type: 'Episode',
          parentIndexNumber: season,
          indexNumber: num,
          playbackPositionMs: ms,
          playedPercentage: pct,
          runTimeTicks: runtimeTicks,
          isWatched: watched,
        );

    test('有进度优先，取 (季,集) 最大的有进度集', () {
      final list = [
        ep('a', 1, 1, ms: 1000, pct: 10),
        ep('b', 1, 5, ms: 2000, pct: 20),
        ep('c', 1, 3, watched: true),
      ];
      expect(DetailScreen.defaultEpisodeTarget(list)!.id, 'b');
    });

    test('无进度取已观看的最大集', () {
      final list = [
        ep('a', 1, 1, watched: true),
        ep('b', 1, 4, watched: true),
        ep('c', 1, 2),
      ];
      expect(DetailScreen.defaultEpisodeTarget(list)!.id, 'b');
    });

    test('跨季取季号更大的有进度集', () {
      final list = [
        ep('s1e10', 1, 10, ms: 1, pct: 1),
        ep('s2e1', 2, 1, ms: 1, pct: 1),
      ];
      expect(DetailScreen.defaultEpisodeTarget(list)!.id, 's2e1');
    });

    test('都没有 → null（维持首季首集）', () {
      expect(DetailScreen.defaultEpisodeTarget([ep('a', 1, 1)]), isNull);
      expect(DetailScreen.defaultEpisodeTarget(const []), isNull);
    });

    test('当前集已看完 → 锁定其后第一个未观看集', () {
      final list = [
        ep('a', 1, 1, ms: 100, pct: 30, watched: true),
        ep('b', 1, 2),
        ep('c', 1, 3),
      ];
      expect(DetailScreen.defaultEpisodeTarget(list)!.id, 'b');
    });

    test('进度达上限视为看完 → 锁定下一未观看集', () {
      final list = [
        ep('a', 1, 1, ms: 900000, pct: 95),
        ep('b', 1, 2),
      ];
      expect(DetailScreen.defaultEpisodeTarget(list)!.id, 'b');
    });

    test('全部看完 → 返回最后已看完集（无下一集）', () {
      final list = [
        ep('a', 1, 1, watched: true),
        ep('b', 1, 2, watched: true),
      ];
      expect(DetailScreen.defaultEpisodeTarget(list)!.id, 'b');
    });

    test('进度低于下限（MinResumePct）不可续播 → 回退 null', () {
      final list = [ep('a', 1, 1, ms: 100, pct: 0.5)];
      expect(DetailScreen.defaultEpisodeTarget(list), isNull);
    });

    test('时长低于下限（MinResumeDurationSeconds）不可续播', () {
      final list = [ep('a', 1, 1, ms: 100, pct: 30, runtimeTicks: 10000000)];
      expect(DetailScreen.defaultEpisodeTarget(list), isNull);
    });

    test('按库阈值生效：上限更低时已看完判定提前', () {
      const strict = EmbyPlaybackSettings(maxResumePct: 80);
      final list = [
        ep('a', 1, 1, ms: 900000, pct: 85),
        ep('b', 1, 2),
      ];
      // 默认上限 90：85% 仍算可续播 → 锁 a
      expect(DetailScreen.defaultEpisodeTarget(list)!.id, 'a');
      // 库上限 80：85% 视为看完 → 锁下一集 b
      expect(DetailScreen.defaultEpisodeTarget(list, strict)!.id, 'b');
    });

    test('focusEpisodeId 参数：优先于 defaultEpisodeTarget', () {
      // 构造一个剧详情页，带 focusEpisodeId
      final episodes = [
        ep('a', 1, 1, ms: 1000, pct: 10),
        ep('b', 1, 5, ms: 2000, pct: 20),
        ep('c', 1, 3, ms: 500, pct: 5),
      ];
      // defaultEpisodeTarget 会选 b（季1集5，进度最大）
      expect(DetailScreen.defaultEpisodeTarget(episodes)!.id, 'b');
      // focusEpisodeId 指定 c 时应优先选 c
      final screen = DetailScreen(itemId: 's1', focusEpisodeId: 'c');
      expect(screen.focusEpisodeId, 'c');
    });

    test('focusEpisodeId 为 null 时行为不变', () {
      final screen = DetailScreen(itemId: 's1');
      expect(screen.focusEpisodeId, isNull);
    });

    test('isAnimationGenres：含「动画」/「Animation」判为动画', () {
      expect(DetailScreen.isAnimationGenres(const ['动画', '奇幻']), isTrue);
      expect(DetailScreen.isAnimationGenres(const ['Animation']), isTrue);
      expect(DetailScreen.isAnimationGenres(const ['animation']), isTrue);
      expect(DetailScreen.isAnimationGenres(const ['剧情', '动作']), isFalse);
      expect(DetailScreen.isAnimationGenres(const []), isFalse);
    });

    testWidgets('动画资源播放路由携带 anim=1', (tester) async {
      final anime = MediaItem(
        id: 'm1',
        name: '测试动画',
        type: 'Movie',
        posterUrl: _posterUrl,
        overview: '简介。',
        genres: const ['动画', '奇幻'],
      );
      await _pumpDetailInRouter(tester, item: anime);

      final btn = find.text('开始播放');
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('PLAYER:m1'), findsOneWidget);
      expect(find.textContaining('anim=1'), findsOneWidget);
    });

    testWidgets('进剧集页锁定到有进度的最大集：主控件显示继续 + 横卡滚到该卡', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final series = MediaItem(id: 'sv1', name: '测试剧集', type: 'Series');
      final eps = [
        for (var i = 1; i <= 12; i++)
          MediaItem(
            id: 'e$i',
            name: '第$i集',
            type: 'Episode',
            parentIndexNumber: 1,
            indexNumber: i,
            playbackPositionMs: i == 10 ? 5000 : 0,
            playedPercentage: i == 10 ? 10 : 0,
          ),
      ];
      await _pumpDetail(
        tester,
        item: series,
        emby: FakeEmbyService(item: series, items: eps),
      );

      // 目标集=第10集（有进度）→ 主控件显示续播
      expect(find.text('继续 00:05'), findsOneWidget);

      // 横卡行已水平滚动到第10集（offset > 0）
      final horizontal = find.byWidgetPredicate(
        (w) => w is ListView && w.scrollDirection == Axis.horizontal,
      );
      expect(horizontal, findsWidgets);
      final scrollable = find.descendant(
        of: horizontal.first,
        matching: find.byType(Scrollable),
      );
      final controller = tester.widget<Scrollable>(scrollable).controller!;
      expect(controller.offset, greaterThan(0), reason: '应水平滚动锁定到目标集卡');
    });

    testWidgets('跨季：目标集在第二季时自动切到该季并锁定', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final series = MediaItem(id: 'sv1', name: '测试剧集', type: 'Series');
      final eps = [
        MediaItem(
            id: 's1e1',
            name: '第1集',
            type: 'Episode',
            parentIndexNumber: 1,
            indexNumber: 1),
        MediaItem(
            id: 's2e1',
            name: '第1集',
            type: 'Episode',
            parentIndexNumber: 2,
            indexNumber: 1),
        MediaItem(
            id: 's2e2',
            name: '第2集',
            type: 'Episode',
            parentIndexNumber: 2,
            indexNumber: 2,
            playbackPositionMs: 3000,
            playedPercentage: 10),
      ];
      await _pumpDetail(
        tester,
        item: series,
        emby: FakeEmbyService(item: series, items: eps),
      );

      // 目标集 s2e2 有进度 → 主控件续播（00:03），且选中季切到第2季
      expect(find.text('继续 00:03'), findsOneWidget);
      expect(find.byKey(const Key('episodeCard_s2e2')), findsOneWidget);
      expect(find.byKey(const Key('episodeCard_s1e1')), findsNothing,
          reason: '已切到第2季，第一季卡不在行内');
    });
  });

  group('详情页顶部压暗罩（v1.2.21 底边归零）', () {
    test('heroScrimGradient 文字区 0x4D、底边透明', () {
      final g = DetailScreen.heroScrimGradient;
      expect(g.colors[2], const Color(0x4D000000));
      expect(g.colors[3], const Color(0x4D000000));
      expect(g.colors.last, Colors.transparent);
      expect(g.stops!.last, 1.0);
    });

    test('heroTextShadows 为轻微投影（blur ≤ 6）', () {
      expect(DetailScreen.heroTextShadows, isNotEmpty);
      for (final s in DetailScreen.heroTextShadows) {
        expect(s.blurRadius, lessThanOrEqualTo(6));
      }
    });
  });
}

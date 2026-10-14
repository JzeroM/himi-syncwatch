import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/episode_info.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/player/widgets/episode_select_panel.dart';
import 'package:himi_syncwatch/screens/player/widgets/selector_side_panel.dart';

import '../helpers/test_fakes.dart';

Widget _host(Widget child, {AppSettings settings = const AppSettings()}) {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier(settings)),
    ],
  );
  addTearDown(container.dispose);
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        // 固定视口：面板内 ListView 需要有限高度才构建卡片
        body: SizedBox(width: 320, height: 600, child: child),
      ),
    ),
  );
}

List<EpisodeInfo> _episodes() => const [
      EpisodeInfo(id: 'e1', name: '沈家灭门，嘉兰入林府', season: 1, number: 1),
      EpisodeInfo(id: 'e2', name: '撞破太奶奶秘密', season: 1, number: 2),
      EpisodeInfo(id: 'e3', name: '嘉兰身世疑云', season: 1, number: 3),
    ];

void main() {
  // ---- 标题格式 ----

  group('cardTitle', () {
    test('剧集 number.name（截图样式 1.集名）', () {
      expect(
        EpisodeSelectPanel.cardTitle(const EpisodeInfo(
            id: 'e1', name: '沈家灭门，嘉兰入林府', season: 1, number: 1)),
        '1.沈家灭门，嘉兰入林府',
      );
    });

    test('number 缺失（0）直接用名字', () {
      expect(
        EpisodeSelectPanel.cardTitle(
            const EpisodeInfo(id: 'e1', name: '无集号', seriesName: '剧')),
        '无集号',
      );
    });

    test('电影（season/number/seriesName 全空）用名字', () {
      expect(
        EpisodeSelectPanel.cardTitle(const EpisodeInfo(id: 'm1', name: '盗梦空间')),
        '盗梦空间',
      );
    });
  });

  // ---- 卡片渲染与交互 ----

  testWidgets('渲染全部剧集卡片，标题 key 存在', (tester) async {
    await tester.pumpWidget(_host(
      EpisodeSelectPanel(
        episodes: _episodes(),
        currentIndex: 0,
        onEpisodeSelected: (_) {},
      ),
    ));
    await tester.pump();

    expect(find.byKey(const Key('playerEpisodeCard_0')), findsOneWidget);
    expect(find.byKey(const Key('playerEpisodeCard_2')), findsOneWidget);
    expect(find.byKey(const Key('playerEpisodeTitle_0')),
        findsOneWidget, reason: '标题挂在 Text 上');
    expect(find.text('1.沈家灭门，嘉兰入林府'), findsOneWidget);
    expect(find.text('3.嘉兰身世疑云'), findsOneWidget);
  });

  testWidgets('点击卡片回调对应下标', (tester) async {
    int? picked;
    await tester.pumpWidget(_host(
      EpisodeSelectPanel(
        episodes: _episodes(),
        currentIndex: 0,
        onEpisodeSelected: (i) => picked = i,
      ),
    ));
    await tester.pump();

    await tester.tap(find.byKey(const Key('playerEpisodeCard_2')));
    await tester.pump();
    expect(picked, 2);
  });

  testWidgets('当前集标题白色加粗、非当前集 white70', (tester) async {
    await tester.pumpWidget(_host(
      EpisodeSelectPanel(
        episodes: _episodes(),
        currentIndex: 1,
        onEpisodeSelected: (_) {},
      ),
    ));
    await tester.pump();

    final selected = tester.widget<Text>(
        find.byKey(const Key('playerEpisodeTitle_1')));
    final normal = tester.widget<Text>(
        find.byKey(const Key('playerEpisodeTitle_0')));
    expect(selected.style?.color, Colors.white);
    expect(selected.style?.fontWeight, FontWeight.w600);
    expect(normal.style?.color, Colors.white70);
    expect(normal.style?.fontWeight, FontWeight.normal);
  });

  testWidgets('currentIndex=-1 时无选中高亮（对勾 0 个）', (tester) async {
    await tester.pumpWidget(_host(
      EpisodeSelectPanel(
        episodes: _episodes(),
        currentIndex: -1,
        onEpisodeSelected: (_) {},
      ),
    ));
    await tester.pump();

    expect(find.byIcon(Icons.check), findsNothing);
  });

  // ---- TV 焦点 ----

  testWidgets('TV：每张卡可聚焦，数量等于剧集数', (tester) async {
    await tester.pumpWidget(_host(
      EpisodeSelectPanel(
        episodes: _episodes(),
        currentIndex: 0,
        onEpisodeSelected: (_) {},
      ),
      settings: const AppSettings(tvMode: true),
    ));
    await tester.pump();

    final focusables = find.byWidgetPredicate(
        (w) => w is Focus && w.focusNode?.debugLabel == 'TvFocusable');
    expect(focusables.evaluate().length, 3, reason: '三集三卡均可 D-pad 聚焦');
  });

  testWidgets('TV：外部 focusNode 挂在当前集卡上（打开落焦）', (tester) async {
    final node = FocusNode(debugLabel: 'SelectorPanelFirstRow');
    addTearDown(node.dispose);
    await tester.pumpWidget(_host(
      SelectorSidePanel(
        title: '选集',
        child: EpisodeSelectPanel(
          episodes: _episodes(),
          currentIndex: 1,
          focusNode: node,
          onEpisodeSelected: (_) {},
        ),
      ),
      settings: const AppSettings(tvMode: true),
    ));
    await tester.pump();

    // 节点挂在当前集卡（index=1）内
    final attached = find
        .descendant(
          of: find.byKey(const Key('playerEpisodeCard_1')),
          matching: find.byWidgetPredicate(
              (w) => w is Focus && w.focusNode == node),
        )
        .evaluate()
        .isNotEmpty;
    expect(attached, isTrue, reason: '当前集卡应持有外部落焦节点');
  });

  testWidgets('TV：currentIndex=-1 时落焦节点回退第一集卡', (tester) async {
    final node = FocusNode(debugLabel: 'SelectorPanelFirstRow');
    addTearDown(node.dispose);
    await tester.pumpWidget(_host(
      EpisodeSelectPanel(
        episodes: _episodes(),
        currentIndex: -1,
        focusNode: node,
        onEpisodeSelected: (_) {},
      ),
      settings: const AppSettings(tvMode: true),
    ));
    await tester.pump();

    final attached = find
        .descendant(
          of: find.byKey(const Key('playerEpisodeCard_0')),
          matching: find.byWidgetPredicate(
              (w) => w is Focus && w.focusNode == node),
        )
        .evaluate()
        .isNotEmpty;
    expect(attached, isTrue, reason: '未选定回退首集');
  });

  testWidgets('非 TV：卡片无焦点节点，点击照常', (tester) async {
    int? picked;
    await tester.pumpWidget(_host(
      EpisodeSelectPanel(
        episodes: _episodes(),
        currentIndex: 0,
        onEpisodeSelected: (i) => picked = i,
      ),
    ));
    await tester.pump();

    final focusables = find.byWidgetPredicate(
        (w) => w is Focus && w.focusNode?.debugLabel == 'TvFocusable');
    expect(focusables.evaluate().length, 0);
    await tester.tap(find.byKey(const Key('playerEpisodeCard_1')));
    await tester.pump();
    expect(picked, 1);
  });
}

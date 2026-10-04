import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

import '../helpers/test_fakes.dart';

void main() {
  int taps = 0;

  setUp(() => taps = 0);

  Widget wrap(AppSettings initial, {bool autofocusFirst = true}) {
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith((ref) => FakeSettingsNotifier(initial)),
      ],
    );
    addTearDown(container.dispose);
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TvFocusable(
                  onTap: () => taps++,
                  autofocus: autofocusFirst,
                  child:
                      const SizedBox(width: 120, height: 60, child: Text('A')),
                ),
                TvFocusable(
                  onTap: () => taps += 10,
                  child:
                      const SizedBox(width: 120, height: 60, child: Text('B')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('TV 关闭：可点击但无 Focus 节点参与遍历', (tester) async {
    await tester.pumpWidget(wrap(const AppSettings(tvMode: false)));
    await tester.pump();

    await tester.tap(find.text('A'));
    await tester.pump();
    expect(taps, 1);
    // 非 TV 模式不渲染 TvFocusable 内部的 _TvFocusableActive（含 Focus）
    expect(
      find.byWidgetPredicate(
          (w) => w is Focus && w.focusNode?.debugLabel == 'TvFocusable'),
      findsNothing,
    );
  });

  testWidgets('TV 开启：OK 键（Enter）触发激活', (tester) async {
    await tester.pumpWidget(wrap(const AppSettings(tvMode: true)));
    await tester.pump();

    final focusableFinder = find.byWidgetPredicate(
        (w) => w is Focus && w.focusNode?.debugLabel == 'TvFocusable');
    expect(focusableFinder, findsNWidgets(2));

    // 首项 autofocus 获得焦点，Enter 激活
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('TV 开启：触摸点击仍可用', (tester) async {
    await tester.pumpWidget(wrap(const AppSettings(tvMode: true)));
    await tester.pump();

    await tester.tap(find.text('B'));
    await tester.pump();
    expect(taps, 10);
  });

  testWidgets('TV 开启：方向键在两个焦点项之间遍历', (tester) async {
    await tester.pumpWidget(wrap(const AppSettings(tvMode: true)));
    await tester.pump();

    final focusables = find.byWidgetPredicate(
        (w) => w is Focus && w.focusNode?.debugLabel == 'TvFocusable');
    FocusNode nodeOf(int index) =>
        tester.widget<Focus>(focusables.at(index)).focusNode!;

    expect(nodeOf(0).hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(nodeOf(1).hasFocus, isTrue, reason: '方向键应移动焦点到第二项');
    expect(nodeOf(0).hasFocus, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(nodeOf(0).hasFocus, isTrue, reason: '上方向键回到第一项');

    // 焦点在第二项时 Enter 激活第二项
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 10);
  });

  testWidgets('TV 开启：高亮容器随焦点出现描边', (tester) async {
    await tester.pumpWidget(wrap(const AppSettings(tvMode: true)));
    await tester.pump();

    // 找到聚焦中的 TvFocusable 内 AnimatedContainer，
    // 前景描边（不挤占布局）应有边框
    final containers = tester.widgetList<AnimatedContainer>(
      find.descendant(
        of: find.byWidgetPredicate(
            (w) => w is Focus && w.focusNode?.debugLabel == 'TvFocusable'),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect(containers, isNotEmpty);
    expect(containers.first.foregroundDecoration, isA<BoxDecoration>());
    final deco = containers.first.foregroundDecoration! as BoxDecoration;
    expect(deco.border, isNotNull, reason: '聚焦项应有高亮描边');
  });

  testWidgets('TV 开启：无初始焦点时方向键可获得焦点', (tester) async {
    await tester.pumpWidget(
        wrap(const AppSettings(tvMode: true), autofocusFirst: false));
    await tester.pump();

    final focusables = find.byWidgetPredicate(
        (w) => w is Focus && w.focusNode?.debugLabel == 'TvFocusable');
    FocusNode nodeOf(int index) =>
        tester.widget<Focus>(focusables.at(index)).focusNode!;
    expect(nodeOf(0).hasFocus, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    final anyFocused = nodeOf(0).hasFocus || nodeOf(1).hasFocus;
    expect(anyFocused, isTrue, reason: '无焦点时方向键应让某项获得焦点（否则 TV 无法起步）');
  });

  Finder _tvContainers(WidgetTester tester) => find.descendant(
        of: find.byWidgetPredicate(
            (w) => w is Focus && w.focusNode?.debugLabel == 'TvFocusable'),
        matching: find.byType(AnimatedContainer),
      );

  int _outlineCount(WidgetTester tester) => tester
      .widgetList<AnimatedContainer>(_tvContainers(tester))
      .where((c) => c.foregroundDecoration != null)
      .length;

  testWidgets('TV 开启：失焦描边瞬时移除（同屏不允许两个焦点框）', (tester) async {
    await tester.pumpWidget(wrap(const AppSettings(tvMode: true)));
    await tester.pump();

    expect(_outlineCount(tester), 1, reason: '初始仅焦点项有描边');

    // 移动焦点并 settle（等 rebuild 落地）。直接断言动画时长语义：
    // 失焦项 duration 必须为 0（零时长瞬时移除），否则旧环 120ms 淡出
    // 与新焦点淡入交叉，同屏出现"两个焦点框"（历史 bug）
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_outlineCount(tester), 1);
    final durations = tester
        .widgetList<AnimatedContainer>(_tvContainers(tester))
        .map((c) => c.duration)
        .toList();
    expect(durations, [Duration.zero, const Duration(milliseconds: 120)],
        reason: '失焦项（A）零时长瞬时移除，聚焦项（B）保留 120ms 淡入');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(_outlineCount(tester), 1, reason: '反向移动同理');
    final durationsUp = tester
        .widgetList<AnimatedContainer>(_tvContainers(tester))
        .map((c) => c.duration)
        .toList();
    expect(durationsUp, [const Duration(milliseconds: 120), Duration.zero],
        reason: '反向后 A 聚焦淡入、B 失焦瞬时移除');
  });

  testWidgets('TV 开启：描边画在缩放内层（环与内容同步缩放不露边）', (tester) async {
    await tester.pumpWidget(wrap(const AppSettings(tvMode: true)));
    await tester.pump();

    final tvFocusables = find.byWidgetPredicate(
        (w) => w is Focus && w.focusNode?.debugLabel == 'TvFocusable');
    final containers = find.descendant(
        of: tvFocusables, matching: find.byType(AnimatedContainer));
    final scales =
        find.descendant(of: tvFocusables, matching: find.byType(AnimatedScale));
    expect(containers, findsNWidgets(2));
    expect(scales, findsNWidgets(2));

    // 结构不变量：AnimatedScale 必须是 AnimatedContainer 的祖先，
    // 否则内容被 Transform 放大后会溢出描边环（焦点框"露边"）
    for (final container in tester.widgetList<AnimatedContainer>(containers)) {
      expect(
        find.ancestor(
          of: find.byWidget(container),
          matching: find.byType(AnimatedScale),
        ),
        findsOneWidget,
        reason: '描边容器必须位于 AnimatedScale 内层',
      );
    }

    // 聚焦项放大目标为默认 1.06，未聚焦项回到 1.0
    final scaleValues =
        tester.widgetList<AnimatedScale>(scales).map((s) => s.scale).toList();
    expect(scaleValues, [1.06, 1.0], reason: '焦点项微放大、非焦点项不放大（顺序同 A/B 两项）');
  });

  testWidgets('TV 开启：scale=1.0 关闭微放大（满宽行防两端文字出屏）', (tester) async {
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(
            (ref) => FakeSettingsNotifier(const AppSettings(tvMode: true))),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: TvFocusable(
                onTap: () {},
                scale: 1.0,
                autofocus: true,
                child:
                    const SizedBox(width: 400, height: 40, child: Text('row')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final tvFocusable = find.byWidgetPredicate(
        (w) => w is Focus && w.focusNode?.debugLabel == 'TvFocusable');
    final scale = tester.widget<AnimatedScale>(
        find.descendant(of: tvFocusable, matching: find.byType(AnimatedScale)));
    expect(scale.scale, 1.0, reason: '聚焦也保持 1.0，不做 Transform 放大');
    // 描边仍随焦点出现
    final outline = tester.widget<AnimatedContainer>(find.descendant(
        of: tvFocusable, matching: find.byType(AnimatedContainer)));
    expect(outline.foregroundDecoration, isA<BoxDecoration>());
  });
}

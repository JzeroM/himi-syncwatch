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
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/player/widgets/subtitle_style_panel.dart';

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
      home: Scaffold(body: Center(child: SizedBox(width: 260, child: child))),
    ),
  );
}

void main() {
  group('回显与格式化', () {
    test('formatScale / formatMarginY / formatDelay', () {
      expect(SubtitleStylePanel.formatScale(1), '1.00×');
      expect(SubtitleStylePanel.formatScale(1.45), '1.45×');
      expect(SubtitleStylePanel.formatMarginY(68), '68px');
      expect(SubtitleStylePanel.formatDelay(0), '0.0s');
      expect(SubtitleStylePanel.formatDelay(800), '+0.8s');
      expect(SubtitleStylePanel.formatDelay(-1200), '-1.2s');
    });

    testWidgets('三行滑杆回显传入值与标签', (tester) async {
      await tester.pumpWidget(_host(
        SubtitleStylePanel(
          scale: 1.4,
          marginY: 68,
          delayMs: -800,
          onScaleChanged: (_) {},
          onMarginYChanged: (_) {},
          onDelayChanged: (_) {},
          onReset: () {},
        ),
      ));
      await tester.pump();

      expect(find.text('大小'), findsOneWidget);
      expect(find.text('位置'), findsOneWidget);
      expect(find.text('延迟'), findsOneWidget);
      expect(find.text('1.40×'), findsOneWidget);
      expect(find.text('68px'), findsOneWidget);
      expect(find.text('-0.8s'), findsOneWidget);
      expect(
        tester
            .widget<Slider>(
              find.byKey(const ValueKey('subtitleStyleScaleSlider')),
            )
            .value,
        1.4,
      );
      expect(find.text('恢复默认'), findsOneWidget);
    });
  });

  group('交互（非 TV）', () {
    testWidgets('拖动大小滑杆回调新值', (tester) async {
      double? got;
      await tester.pumpWidget(_host(
        SubtitleStylePanel(
          scale: 1.0,
          marginY: 22,
          delayMs: 0,
          onScaleChanged: (v) => got = v,
          onMarginYChanged: (_) {},
          onDelayChanged: (_) {},
          onReset: () {},
        ),
      ));
      await tester.pump();

      await tester.drag(
        find.byKey(const ValueKey('subtitleStyleScaleSlider')),
        const Offset(60, 0),
      );
      await tester.pump();

      expect(got, isNotNull, reason: '拖动应触发 onChanged');
      expect(got!, greaterThan(1.0));
      expect((got! * 100).round() % 5, 0,
          reason: '取值应对齐 0.05 步进（×100 为 5 的倍数）');
    });

    testWidgets('无激活字幕轨时延迟滑杆禁用', (tester) async {
      await tester.pumpWidget(_host(
        SubtitleStylePanel(
          scale: 1.0,
          marginY: 22,
          delayMs: 0,
          delayEnabled: false,
          onScaleChanged: (_) {},
          onMarginYChanged: (_) {},
          onDelayChanged: (_) {},
          onReset: () {},
        ),
      ));
      await tester.pump();

      final slider = tester.widget<Slider>(
        find.byKey(const ValueKey('subtitleStyleDelaySlider')),
      );
      expect(slider.onChanged, isNull, reason: '无字幕轨延迟不可调');
      expect(find.text('当前无激活字幕轨，延迟不可调'), findsOneWidget);
    });

    testWidgets('点「恢复默认」触发 onReset；默认态高亮选中', (tester) async {
      bool reset = false;
      await tester.pumpWidget(_host(
        SubtitleStylePanel(
          scale: SubtitleStylePanel.defaultScale,
          marginY: SubtitleStylePanel.defaultMarginY,
          delayMs: SubtitleStylePanel.defaultDelayMs,
          onScaleChanged: (_) {},
          onMarginYChanged: (_) {},
          onDelayChanged: (_) {},
          onReset: () => reset = true,
        ),
      ));
      await tester.pump();
      expect(find.text('恢复默认'), findsOneWidget);

      await tester.tap(find.text('恢复默认'));
      await tester.pump();
      expect(reset, isTrue);
    });
  });

  group('TV 交互', () {
    testWidgets('打开面板落焦第一行滑杆，左右键调值', (tester) async {
      double? got;
      final firstRowNode = FocusNode(debugLabel: 'stylePanelFirst');
      addTearDown(firstRowNode.dispose);

      await tester.pumpWidget(_host(
        SubtitleStylePanel(
          scale: 1.0,
          marginY: 22,
          delayMs: 0,
          onScaleChanged: (v) => got = v,
          onMarginYChanged: (_) {},
          onDelayChanged: (_) {},
          onReset: () {},
          focusNode: firstRowNode,
        ),
        settings: const AppSettings(tvMode: true),
      ));
      firstRowNode.requestFocus();
      await tester.pump();

      expect(FocusManager.instance.primaryFocus, firstRowNode,
          reason: '面板打开后精确落焦第一行（大小）');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      expect(got, isNotNull, reason: '左右键应调整大小滑杆');
      expect(got!, greaterThan(1.0));
    });

    testWidgets('恢复默认行 TV 可聚焦（D-pad 焦点环）', (tester) async {
      await tester.pumpWidget(_host(
        SubtitleStylePanel(
          scale: 1.2,
          marginY: 22,
          delayMs: 0,
          onScaleChanged: (_) {},
          onMarginYChanged: (_) {},
          onDelayChanged: (_) {},
          onReset: () {},
        ),
        settings: const AppSettings(tvMode: true),
      ));
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (w) => w is Focus && w.focusNode?.debugLabel == 'TvFocusable',
        ),
        findsOneWidget,
        reason: '仅恢复默认行是 TvFocusable（滑杆直接 D-pad 聚焦）',
      );
    });
  });
}

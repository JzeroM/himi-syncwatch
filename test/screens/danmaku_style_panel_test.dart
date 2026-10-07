import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/player/widgets/danmaku_style_panel.dart';
import 'package:himi_syncwatch/screens/player/widgets/display_adjust_panel.dart';

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
        body: Center(
          child: SizedBox(width: 300, height: 500, child: child),
        ),
      ),
    ),
  );
}

DanmakuStylePanel _panel({
  double speed = 1.0,
  double fontSize = 1.0,
  double opacity = 1.0,
  ValueChanged<double>? onSpeed,
  ValueChanged<double>? onFontSize,
  ValueChanged<double>? onOpacity,
  VoidCallback? onReset,
}) =>
    DanmakuStylePanel(
      speed: speed,
      fontSizeScale: fontSize,
      opacity: opacity,
      onSpeedChanged: onSpeed ?? (_) {},
      onFontSizeChanged: onFontSize ?? (_) {},
      onOpacityChanged: onOpacity ?? (_) {},
      onReset: onReset ?? () {},
    );

DisplayAdjustPanel _display({
  double danmakuSpeed = 1.0,
  double danmakuFontSize = 1.0,
  double danmakuOpacity = 1.0,
  ValueChanged<double>? onSpeed,
  VoidCallback? onDanmakuReset,
}) =>
    DisplayAdjustPanel(
      subtitleScale: 1.0,
      subtitleMarginY: 22,
      subtitleDelayMs: 0,
      onSubtitleScaleChanged: (_) {},
      onSubtitleMarginChanged: (_) {},
      onSubtitleDelayChanged: (_) {},
      onSubtitleReset: () {},
      danmakuSpeed: danmakuSpeed,
      danmakuFontSize: danmakuFontSize,
      danmakuOpacity: danmakuOpacity,
      onDanmakuSpeedChanged: onSpeed ?? (_) {},
      onDanmakuFontSizeChanged: (_) {},
      onDanmakuOpacityChanged: (_) {},
      onDanmakuReset: onDanmakuReset ?? () {},
    );

void main() {
  group('DanmakuStylePanel 回显与格式化', () {
    test('formatSpeed / formatFontSize / formatOpacity', () {
      expect(DanmakuStylePanel.formatSpeed(1), '1.00×');
      expect(DanmakuStylePanel.formatSpeed(1.55), '1.55×');
      expect(DanmakuStylePanel.formatFontSize(0.75), '0.75×');
      expect(DanmakuStylePanel.formatOpacity(1.0), '100%');
      expect(DanmakuStylePanel.formatOpacity(0.5), '50%');
      expect(DanmakuStylePanel.formatOpacity(0.1), '10%');
    });

    testWidgets('三行滑杆回显传入值与标签', (tester) async {
      await tester.pumpWidget(
        _host(_panel(speed: 1.5, fontSize: 0.8, opacity: 0.6)),
      );
      await tester.pump();

      expect(find.text('速度'), findsOneWidget);
      expect(find.text('大小'), findsOneWidget);
      expect(find.text('透明度'), findsOneWidget);
      expect(find.text('1.50×'), findsOneWidget);
      expect(find.text('0.80×'), findsOneWidget);
      expect(find.text('60%'), findsOneWidget);
      expect(
        tester
            .widget<Slider>(
              find.byKey(const ValueKey('danmakuSpeedSlider')),
            )
            .value,
        1.5,
      );
      expect(find.text('恢复默认'), findsOneWidget);
    });

    testWidgets('拖动速度滑杆回调新值（0.05 步进）', (tester) async {
      double? got;
      await tester.pumpWidget(_host(_panel(onSpeed: (v) => got = v)));
      await tester.pump();

      await tester.drag(
        find.byKey(const ValueKey('danmakuSpeedSlider')),
        const Offset(60, 0),
      );
      await tester.pump();

      expect(got, isNotNull);
      expect(got!, greaterThan(1.0));
      expect((got! * 100).round() % 5, 0, reason: '对齐 0.05 步进');
    });

    testWidgets('点「恢复默认」触发 onReset；默认态高亮选中', (tester) async {
      bool reset = false;
      await tester.pumpWidget(
        _host(_panel(
          speed: DanmakuStylePanel.defaultSpeed,
          fontSize: DanmakuStylePanel.defaultFontSize,
          opacity: DanmakuStylePanel.defaultOpacity,
          onReset: () => reset = true,
        )),
      );
      await tester.pump();
      expect(_sideOptionSelected(tester, '恢复默认'), isTrue);

      await tester.tap(find.text('恢复默认'));
      await tester.pump();
      expect(reset, isTrue);
    });
  });

  group('DisplayAdjustPanel 组合面板', () {
    testWidgets('字幕段与弹幕段共存：段头 + 六滑杆 + 两个恢复默认', (tester) async {
      await tester.pumpWidget(_host(_display(danmakuSpeed: 1.25)));
      await tester.pump();

      expect(find.byKey(const ValueKey('字幕SectionHeader')), findsOneWidget);
      expect(find.byKey(const ValueKey('弹幕SectionHeader')), findsOneWidget);
      // 字幕三滑杆
      expect(
        find.byKey(const ValueKey('subtitleStyleScaleSlider')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('subtitleStyleMarginSlider')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('subtitleStyleDelaySlider')),
        findsOneWidget,
      );
      // 弹幕三滑杆
      expect(find.byKey(const ValueKey('danmakuSpeedSlider')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('danmakuFontSizeSlider')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('danmakuOpacitySlider')),
        findsOneWidget,
      );
      expect(find.text('恢复默认'), findsNWidgets(2));
      expect(find.text('1.25×'), findsOneWidget, reason: '弹幕速度回显');
      // 单一滚动容器（段落为 Column，不嵌套）
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('滚动到弹幕段后拖动速度滑杆可回调', (tester) async {
      double? got;
      await tester.pumpWidget(_host(_display(onSpeed: (v) => got = v)));
      await tester.pump();

      // 视口 300×500 高度不够 → 先滚到底部露出弹幕段
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();

      await tester.drag(
        find.byKey(const ValueKey('danmakuSpeedSlider')),
        const Offset(60, 0),
      );
      await tester.pump();
      expect(got, isNotNull, reason: '弹幕段滑杆在组合面板内可交互');
    });

    testWidgets('点弹幕段「恢复默认」只触发弹幕回调', (tester) async {
      bool danmakuReset = false;
      await tester.pumpWidget(
        _host(_display(onDanmakuReset: () => danmakuReset = true)),
      );
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();

      await tester.tap(find.text('恢复默认').last);
      await tester.pump();
      expect(danmakuReset, isTrue);
    });
  });
}

/// SideOptionRow 选中态（selected 时文字高亮主色）。
bool _sideOptionSelected(WidgetTester tester, String label) {
  final text = tester.widget<Text>(find.text(label));
  return text.style?.color == const Color(0xFF6366F1);
}
